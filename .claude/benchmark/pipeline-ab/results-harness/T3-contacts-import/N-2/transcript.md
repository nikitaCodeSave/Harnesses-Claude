### [build] operator

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

### [build] agent

I've read the code. Per CLAUDE.md this starts with an interview. Each question below has my recommended answer, so you can just reply "all defaults" or override by number.

**What an import does to the repo**

1. **Rows with errors.** Should valid rows still be imported when other rows fail, or is it all or nothing?
   *Rec:* import the valid rows and list the bad ones in `errors`. The report has both `created` and `errors`, which suggests this. `ImportFileError` is only for problems with the whole file, and then nothing is written.
2. **Email already in the repo.** *Rec:* update that contact, so it goes in `updated`. If the row matches the stored contact exactly, should it still go in `updated`, or be left out of both lists?
   *Rec:* leave it out of both. Then `updated` means "something actually changed".
3. **What an update replaces.** *Rec:* the row is the full truth for that contact, the same way the export is a full snapshot. The name is replaced. Tags are replaced, not merged. An **empty phone cell clears the phone**, matching `Contact.create`, where a blank phone means no phone. The alternative is "an empty cell means leave it unchanged". That is friendlier to sparse spreadsheets, but it means you can never clear a phone or tags through an import.
4. **Same email twice in one file.** *Rec:* the first occurrence wins. The later row goes in `errors` and points back to the row it duplicates. The other option is "last one wins, with a warning".

**File format**

5. **Encoding of `bytes`.** *Rec:* accept UTF-8 and strip a UTF-8 BOM, since Excel's "CSV UTF-8" adds one. Anything that isn't valid UTF-8 raises `ImportFileError`. The alternative is falling back to cp1252 (Excel's legacy "CSV" on Windows) with a warning, which risks silently garbling names. Do you know which one Sales actually exports?
6. **Delimiter.** *Rec:* comma only. Excel in German, French and some other locales saves with `;`, which is also our tag separator, so guessing the delimiter is unreliable. I'd raise `ImportFileError` with a clear hint when the header row looks semicolon-delimited. Is any of Sales on such a locale?
7. **Header.** *Rec:* the header row is required, and columns are matched by name: case-insensitive, trimmed, any order. `name` and `email` are required; if either is missing, raise `ImportFileError`. `phone` and `tags` are optional. An unknown extra column (e.g. "Notes") is ignored, with one warning (`row=1`, `column="Notes"`). A duplicated header name raises `ImportFileError`.
8. **Empty input.** *Rec:* an empty file raises `ImportFileError`. A file with only a header is fine and gives an empty report. Blank lines are skipped silently.

**What a row issue looks like**

9. **`RowIssue.row`.** *Rec:* the line number as shown in a spreadsheet, so the header is row 1 and the first contact is row 2. For a cell that spans several lines inside quotes, use the line where the record starts. `column` is the header name as written in the file, e.g. `"Phone"`. It is `None` when the issue isn't about one cell, such as a wrong cell count or a duplicate row.
10. **Error vs. warning.** *Rec:* an error means the row was **not** imported. A warning means it was imported, or the file was, but something deserves a look. Rows with too many or too few cells are errors. One bad tag in `"vip;c++"` makes the whole row an error, rather than dropping that tag with a warning. Agree?
11. **Limits.** Should there be a maximum file size or row count, enforced with `ImportFileError`? *Rec:* none for now, since the input is an in-memory `str`/`bytes` and the caller already holds it.

**Scope**

12. **Non-goals unless you say otherwise:**
    - no `ContactBook.import_csv` wrapper;
    - no dry-run mode;
    - no deleting contacts that are missing from the file;
    - no protection against formula injection (e.g. a name like `=HYPERLINK(...)` being exported back to Excel). That is an export concern; should it go on a ticket?
    - I'll add the new names to `contactbook.__init__`.

Once you answer, I'll write `specs/csv-import.md` with your interface copied word for word. I'll also start a `GLOSSARY.md` (it doesn't exist yet) and add an ADR for the update semantics in 2–3, since later persistence adapters will have to follow them. Then I'll build the import here: failing tests first, then the code, then a review of the parser in a fresh session against the spec.

### [build] user

Answers by number:

1. Agreed. Good rows go in, bad rows go in `errors` and are skipped. A bad row must not be applied at all, not even partly to an existing contact. `ImportFileError` is for whole-file problems only, and then nothing is written.
2. I don't mind whether an unchanged contact is listed in `updated`. Use your recommendation.
3. This is wrong, so please change it.
   - The file's name replaces ours.
   - Phone is replaced only when the cell has a value. An empty cell, or no phone column, never wipes an existing phone.
   - Tags from the file are added to the existing ones. An import never removes tags.
4. Agreed. The first row wins, and each later row with that email is an error on that later row and is not applied.
5. UTF-8 only, with the BOM stripped. Text input that still starts with the BOM character must work too. Bytes that aren't valid UTF-8 raise `ImportFileError` telling them to re-save as "CSV UTF-8". No cp1252 fallback.
6. I don't mind. Comma only is fine.
7. Two corrections.
   - Required columns are `email` and `name`. Our address-book export writes `first_name` and `last_name` instead of `name`. Accept that pair as the name column, and join the two with one space.
   - `column` in issues is the lower-case canonical name: `name`, `email`, `phone` or `tags`. A name problem in a `first_name`/`last_name` file is `name` too.
   
   Ignoring unknown columns is fine, with or without a warning. I don't mind about duplicate headers.
8. Agreed. An empty file raises `ImportFileError`. A header-only file gives an empty report. Blank lines, and rows where every cell is empty or only spaces, are skipped silently.
9. `row` is the spreadsheet row number, with the header as row 1. Every line counts, blank lines included. For `column`, see 7. I don't mind about multi-line cells.
10. Agreed that a bad tag makes the row an error. A phone that fails validation is different: it is a warning with column `phone`, not an error. Import or update the rest of the row and leave the phone as it was (none for a new contact). I don't mind about wrong cell counts.
11. This is wrong, so please change it. The limit is 1000 contact rows per file, and blank rows don't count. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported.
12. Those non-goals are fine, and adding the names to `__init__` is fine. I don't want formula injection on a ticket.

Also:
- Email is the identity. Normalise it with the existing helper (trim and lower-case). A missing or invalid email is an error on that row.
- Name is required on every row, including rows that update an existing contact. Validate it with the existing name helper.
- Tags are separated by `;`. Normalise each with the existing helper and ignore empty pieces and repeats.

Go ahead with the spec.

### [build] agent

The CSV import is built: `import_contacts` is in `src/contactbook/importer.py` with exactly the interface you fixed, and it's exported from `contactbook`. The suite passes:

```
$ python3 -m pytest -q; echo "exit=$?"
83 passed in 0.03s
exit=0
```

**Written:**
- **Spec:** `specs/csv-import.md`, with your interface copied word for word, acceptance criteria as checks, non-goals and scope.
- **Tests:** `tests/test_importer.py`, 64 tests, written before the code. They failed first because the module didn't exist yet.
- **Code:** `ImportFileError` added to `errors.py`, plus the exports in `__init__.py` and a line in the README layout.
- **ADR:** `docs/adr/0001-csv-import-merge-semantics.md` records the update rules from your item 3, row all-or-nothing, first row wins, UTF-8 only and the 1000-row limit.
- **Glossary:** `GLOSSARY.md` is new, holding the terms from this change.

The whole file is read and checked before anything is written. So an `ImportFileError` leaves the repo untouched, and a rejected row is never partly applied.

**Review:** a fresh session checked the change against the spec, correctness only. It found no way to partly write the repo and no unexpected crashes. It did find two places where the code didn't match the spec, a few spec gaps, and some missing tests; I handled them in the first round. For the two bug fixes, I applied the fix before writing its test, which is the wrong order. I made up for it by temporarily putting the old code back: both new tests failed against it, and pass with the fix.

**Decisions I made that you didn't settle.** They're all in the spec; say if you want any changed:
1. **A file with a cell over 131,072 characters is rejected.** That is Python's built-in csv limit, and raising it would change a process-wide setting the HTTP layer shares. The error says which row and why.
2. **Unterminated or broken quoting rejects the whole file.** Without this, one stray `"` silently swallows every row after it into a single cell.
3. **A row with more cells than the header is one error**, if any extra cell has content (usually an unquoted comma). Its email doesn't count toward the duplicate check. Rows with fewer cells treat the missing ones as empty.
4. **A duplicate-email row gets only the duplicate error.** Its other cells aren't checked.
5. **A bad phone is reported even on a row rejected for another reason**, so Sales can fix everything in one pass.
6. **Unknown columns:** each one gets a warning at the header's row. Empty header cells are ignored silently.
7. **`name` wins:** if a file has both `name` and `first_name`/`last_name`, the `name` column is used.

Nothing is committed. Running pytest also leaves untracked `__pycache__/` folders, because the repo has no `.gitignore`.
