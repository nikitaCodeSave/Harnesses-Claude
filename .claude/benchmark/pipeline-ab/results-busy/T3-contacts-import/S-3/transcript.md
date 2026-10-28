### [spec+build] operator

Sales keeps leads in spreadsheets and wants to load a whole CSV file into contactbook
instead of adding contacts one by one. Add a CSV import that reports what happened.
The file has the same columns as our CSV export.

Interface (other code calls exactly this):
- `src/contactbook/importer.py`: `import_contacts(repo: InMemoryContactRepository, data: str | bytes) -> ImportReport`
  where `data` is the file content: raw bytes as read from disk, or already-decoded text.
- `ImportReport` (dataclass, same module): `created: list[str]`, `updated: list[str]` (normalised
  emails), `errors: list[RowIssue]`, `warnings: list[RowIssue]`.
- `RowIssue` (dataclass, same module): `row: int`, `column: str | None`, `message: str`.
- `ImportFileError(ContactError)` in `src/contactbook/errors.py`, raised when the file as a whole
  can't be imported.

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [spec+build] agent

I've read the code (Contact/validation, the case-insensitive email-keyed repository, `export_csv` with columns `name,email,phone,tags` and `;`-joined tags). The suite passes now: 24 tests. Before I write the spec I have some questions. Each one has my recommended default, so you can answer "default" to any of them.

**A. Existing contacts and partial failure**
1. **When the email already exists:** should the file row replace the stored contact completely (name, phone, tags all from the file), or merge with it? *Default: replace completely, so a blank phone cell clears the phone, and the file's tags replace the existing tags.* The other option is merge: blank cells keep the stored values, and tags get unioned.
2. **When an existing contact is identical to its row:** should it still go in `updated`? *Default: no. Leave it out of every list, so `updated` only lists real changes.*
3. **Bad rows:** should a bad row be skipped while the good rows still import (partial import), or should any row error import nothing? *Default: partial. Bad rows go to `errors`, the rest import.*

**B. Rows**
4. **Same email twice in one file** (after normalising): *Default: the first one wins. Each later row becomes an error ("duplicate of row N") and isn't applied.* Alternative: the last one wins, with a warning.
5. **Invalid tag in a row:** should the whole row be rejected, or should only that tag be dropped with a warning? *Default: reject the row (error on column `tags`). This matches what `Contact.create` does today.*
6. **Blank rows, including whitespace-only rows:** *Default: skip them silently.*
7. **Row numbers:** *Default: the line number as a spreadsheet shows it. The header is row 1 and the first data row is row 2.* I'd use the physical line, so quoted multi-line cells count too.
8. **Rows with more or fewer cells than the header:** *Default: an error for that row.*

**C. Header and file-level problems** (anything here raises `ImportFileError`)
9. **Header row:** *Default: a header is required. Column names are matched case-insensitively and ignoring surrounding spaces, and columns can be in any order. `name` and `email` must be present; `phone` and `tags` are optional. A missing required column or a duplicate column name raises `ImportFileError`. An unknown extra column gives a warning (row 1, that column) and gets ignored.*
10. **Empty file or header only:** *Default: an empty file (or whitespace only) raises `ImportFileError`. A file with only the header returns an empty report and isn't an error.*
11. **Encoding for `bytes`:** *Default: UTF-8, with an optional BOM stripped (Excel writes one). Bytes that aren't valid UTF-8 raise `ImportFileError`. No guessing of cp1252 or other encodings.* A BOM on `str` input also gets stripped.
12. **Delimiter:** *Default: comma only. Semicolon-delimited "European Excel" files are a non-goal.* They'd most likely fail with "missing column email".
13. **Size limit:** *Default: no row limit for now (non-goal).* Do you want a cap?

**D. Scope**
14. Should anything besides `importer.py` expose this, such as a `ContactBook.import_csv` method or a re-export from `contactbook/__init__`? *Default: re-export `import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError` from the package, with no service method and no CLI or HTTP layer.*
15. **Order of `created` and `updated`:** *Default: file order.*

### [spec+build] user

1. Not default: merge. Name from the file replaces ours. Phone is replaced only if the cell has a value; an empty cell or missing phone column never wipes an existing phone. Tags from the file are added to the existing ones; an import never removes tags. A bad row is not applied at all, not even partly.
2. Don't mind, your call.
3. Partial import, as you propose. Bad rows go to errors, good ones import. The exceptions are whole-file problems (see 9-13), which reject everything.
4. First wins, later rows are errors on that later row. OK.
5. Reject the row, error on column tags. Tags are separated by ';', each normalised with the existing tag helper, with empty pieces and repeats ignored.
6. Skip silently. That covers empty lines and rows where every cell is empty or spaces.
7. Row = the number Excel shows: header is 1, first contact is 2, and every line counts, blank lines included. Fine.
8. Don't mind.
9. Header required, case-insensitive, spaces ignored, any order. Required: email and name. Optional: phone, tags. Missing required column raises ImportFileError. One change: the address-book export writes first_name and last_name instead of name. Accept that pair as the name column, joined with one space. Extra columns: ignore silently or warn, but never an error. Duplicate column names: don't mind.
10. Completely empty file raises ImportFileError. Header only is fine, with an empty report. OK.
11. OK. A BOM on bytes and on str must both work. Invalid UTF-8 raises ImportFileError telling them to re-save as "CSV UTF-8".
12. Comma only, fine.
13. Yes, a cap: at most 1000 contact rows (blank rows don't count). A bigger file raises ImportFileError and nothing is imported.
14. Don't mind. Re-exporting is fine.
15. Don't mind.

### [spec+build] agent

CSV import is built: `import_contacts` in `src/contactbook/importer.py`, with the interface copied word for word into `SPEC.md`. The full test suite passes.

```
$ python3 -m pytest
collected 72 items

tests/test_export.py ..                                                  [  2%]
tests/test_importer.py ................................................  [ 69%]
tests/test_models.py ....                                                [ 75%]
tests/test_repository.py ....                                            [ 80%]
tests/test_service.py ...                                                [ 84%]
tests/test_validation.py ...........                                     [100%]

============================== 72 passed in 0.03s ==============================
```

That's the existing 24 tests plus 48 new ones in `tests/test_importer.py`, grouped to match the spec's sections. To check the new tests catch mistakes, I broke the code nine ways by hand (e.g. letting a blank phone wipe the stored phone, replacing tags instead of adding, an off-by-one in the 1000-row cap, row numbering, ignoring the BOM). The suite failed every time. Two cases have no test of their own: the error message names the missing column, and the empty-file message.

**What changed**
- `SPEC.md`: why the feature exists, 29 checkable criteria, and the non-goals.
- `src/contactbook/importer.py`: the import itself, plus `ImportReport` and `RowIssue`.
- `src/contactbook/errors.py`: `ImportFileError(ContactError)`.
- `src/contactbook/__init__.py` re-exports all four names, and `README.md` now lists the new module.

**Decisions I made where you said "don't mind" or we didn't discuss it.** They're marked **[decision]** in the spec; tell me if you want any changed:
- **Unchanged contact:** an existing contact the row leaves identical goes in neither `created` nor `updated`.
- **Too many or too few cells:** a row with extra non-empty cells beyond the header is an error with `column=None`. Missing trailing cells count as empty.
- **Duplicate column names** in the header (e.g. `email,EMAIL`) reject the whole file.
- **Extra columns** give a warning on row 1, not silence.
- **`name` alongside `first_name`/`last_name`:** if a file has all three, `name` is used and the other two get the unknown-column warning.
- **Several bad cells in one row** each get their own error, so sales can fix everything in one pass.
- **Duplicates when the first row is bad:** the first row with an email still claims it even if that row is rejected for another reason, so a later copy of that email is also an error.
- **Header position:** row 1 must be the header. Blank lines before it reject the file.
- **Unreadable CSV:** a file the CSV parser can't read raises `ImportFileError`. Python 3.12 accepts NUL bytes, so the spec's example is an oversized cell instead.

Nothing is committed. Running the tests also left untracked `__pycache__/` folders in the repo because it has no `.gitignore`.
