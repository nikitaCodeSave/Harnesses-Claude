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

I've read the codebase (validation, `Contact.create`, repository keyed by lower-cased email, export columns `name,email,phone,tags` with `;`-joined tags). Before I write the spec I need your call on the following. Each has my suggested default; reply with just the numbers you want changed, or "defaults OK".

**Partial imports and existing data**
1. **Partial vs all-or-nothing:** if some rows are bad, do the good rows still get imported? *Suggested: yes. Bad rows are skipped and listed in `errors`, good rows are saved.* (`ImportFileError` is only for problems with the whole file.)
2. **Email already in the repo:** update that contact. When a cell is empty, does it clear the stored value or keep it? *Suggested: the row replaces the contact entirely, including name. An empty phone clears the phone, and empty tags clear the tags. That matches "re-import an edited export".* The other option is merge: empty cells keep what's stored and tags are added to the existing ones.
3. **Row matches the stored contact exactly:** *Suggested: it goes in neither `created` nor `updated`, and the repo is left untouched (no warning).*
4. **Same email twice in one file** (compared case-insensitively): *Suggested: the first one wins, and every later one is an error on that row ("duplicate of row N").*

**Row-level rules**
5. **One invalid field** (for example a bad phone or a bad tag): *Suggested: the whole row is rejected, with one `RowIssue` per bad field, `column` set to the column name, and `message` taken from the validator.* The other option is to drop just the bad tag/phone and keep the row as a warning.
6. **Blank lines:** *Suggested: skipped silently.*
7. **Wrong number of cells:** *Suggested: too few cells means the missing ones count as empty. Too many is an error for that row (`column=None`).*
8. **Row numbers:** *Suggested: physical line number in the file, with the header on line 1, so it matches what Sales sees in a text editor. If a quoted cell spans several lines, the row's first line is used.* The other option is spreadsheet row number, which is the same unless cells contain newlines.

**File-level rules (`ImportFileError`)**
9. **Header:** *Suggested: column names are matched ignoring case and surrounding spaces, and any order is accepted. `name` and `email` are required (missing → `ImportFileError`). `phone` and `tags` are optional. Unknown extra columns are ignored, with one warning (`row=1`, column = that name). A duplicated column name is an `ImportFileError`.*
10. **Encoding (bytes):** *Suggested: UTF-8, with or without the BOM Excel adds. Anything that isn't valid UTF-8 → `ImportFileError`.* The other option is falling back to Windows-1252 for old Excel saves. I'd rather not guess, because a wrong guess silently garbles names.
11. **Delimiter:** Excel in many European locales saves with `;`, which is also our tag separator. *Suggested: comma only, matching the export. A `;`-delimited file then fails the header check with a clear message.* The other option is auto-detecting `,` vs `;`.
12. **Empty input / header only:** *Suggested: empty or whitespace-only input → `ImportFileError`. Header with no data rows → an empty report, which is a valid no-op.*
13. **Size limit:** *Suggested: none for now (non-goal).*

**Scope**
14. **Non-goals I plan to list:** no CLI or HTTP endpoint, no dry-run mode, no deleting contacts that aren't in the file, no formats other than CSV. Should any of these be in scope?

### [spec+build] user

Changes to your defaults:

2. Use merge, not replace. Name: the file's value replaces ours. Phone: replaced only when the cell has a value; an empty cell or a missing phone column never clears a stored phone. Tags: the file's tags are added to the existing ones; an import never removes tags. An existing contact goes in `updated`, never an error.

5. Split by field. A bad tag, or an empty/invalid name, makes the whole row an error (column `tags` / `name`) and nothing from that row is applied, not even to an existing contact. A bad phone must NOT cost us the contact: import/update the rest of the row, leave the phone as it was (none for a new contact), and add a warning (not an error) with column `phone`. A missing or invalid email is a row error. Name is required on every row, including rows that update an existing contact.

8. Use the spreadsheet row number as Excel shows it: header is row 1, first contact is row 2, and every line counts, blank lines included. `column` is the lower-case name: `name`, `email`, `phone` or `tags`.

9. Add one thing: our address-book export writes `first_name` and `last_name` instead of `name`. Accept that pair as the name column, with the name being first and last joined by one space. A name problem in such a file is still column `name`. Otherwise your default is fine (extra columns ignored, with or without a warning).

10. Default is right, but cover text input too: a string that still starts with the BOM character must also work. For invalid UTF-8, the ImportFileError should tell them to re-save as "CSV UTF-8".

13. Not a non-goal: reject the whole file with ImportFileError (nothing imported) if it has more than 1000 contact rows. Blank rows don't count. A header-only file is fine and gives an empty report.

Also for 6: skip rows where every cell is empty or only spaces (the `,,,` lines Excel leaves) as well as empty lines, silently.

Defaults OK for 1, 3, 4, 7, 11, 12, 14.

### [spec+build] agent

CSV import is built, and the full test suite passes.

**Command:** `python3 -m pytest`
```
collected 79 items
tests/test_export.py ..                                                  [  2%]
tests/test_importer.py ................................................. [ 64%]
......                                                                   [ 72%]
tests/test_models.py ....                                                [ 77%]
tests/test_repository.py ....                                            [ 82%]
tests/test_service.py ...                                                [ 86%]
tests/test_validation.py ...........                                     [100%]
============================== 79 passed in 0.03s ==============================
```

**What changed**
- **`SPEC.md`**: why the feature exists, the interface copied verbatim from your request, 37 numbered acceptance criteria, and the non-goals.
- **`src/contactbook/importer.py`**: `import_contacts`, `ImportReport` and `RowIssue`.
- **`src/contactbook/errors.py`**: new `ImportFileError(ContactError)`, also exported from the package.
- **`tests/test_importer.py`**: 55 new tests. Each test is tagged with the criterion number it covers, and every criterion has at least one.
- **`README.md`**: added `importer.py` to the layout list.

Your rules are all in: merge on existing contacts, bad phone is a warning (not an error), Excel row numbers with blank lines counted, `first_name`/`last_name` accepted as the name, the "CSV UTF-8" message for non-UTF-8 files, and the 1000-row limit with nothing imported when it's exceeded.

**Decisions I made myself.** These are listed at the end of `SPEC.md`, and each is a small change if you disagree:
- **Same email twice in a file:** a later row only counts as a duplicate of an earlier row that was imported. If the first row was rejected (say, no name), a later valid row with that email still gets imported.
- **Trailing commas:** extra cells past the header that are empty are ignored. Only extra cells with content make the row an error.
- **Rejected rows:** they don't also get a phone warning.
- **Unknown columns:** each one gives a warning on row 1 rather than being ignored silently.
- **`first_name`/`last_name`:** if only one is filled in, that one is used as the name.
- **Both name formats in one file:** `name` is used, and `first_name`/`last_name` get the unused-column warning.

Nothing is committed. Running the tests created untracked `__pycache__/` folders, because the repo has no `.gitignore`.
