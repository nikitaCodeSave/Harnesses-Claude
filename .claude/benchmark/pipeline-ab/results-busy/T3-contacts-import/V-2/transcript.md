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

CSV import is added with the exact interface you specified, in `src/contactbook/importer.py`. All 50 tests pass: the 24 existing ones plus 26 new ones in `tests/test_importer.py`. Nothing is committed.

**How it works**
- **Contacts:** a row whose email isn't in the repo creates a contact; otherwise it updates the existing one. All values go through `validation.py`, so `created`/`updated` hold normalised emails.
- **Partial imports:** bad rows are skipped and reported, and every other row is still imported. Each field is checked separately, so a row with three problems gets three errors, each naming its column.
- **Whole-file errors** raise `ImportFileError` before the repo is changed, so nothing is half-imported. These are:
  - an empty file
  - missing `name` or `email` columns
  - a column that appears twice in the header
  - text that isn't valid UTF-8
  - broken quoting, such as an unclosed `"`
- **Row numbers** match what you see in the spreadsheet: the header is row 1 and the first contact is row 2.

**Spreadsheet quirks it handles**
- The byte-order mark Excel adds to UTF-8 files, and UTF-16 files that have one.
- `;`-separated files, which Excel writes in European locales. The separator is picked from the header row.
- Header names in any letter case, with extra spaces, in any order.
- Blank rows (including `,,,`), short rows, and trailing empty cells are skipped or tolerated.
- Columns it doesn't know, or with no header, are ignored with a warning.
- A row with extra non-empty cells is rejected rather than imported with shifted values. This usually means an unquoted comma, like `Lee, Ann`.

**Choices you may want to change**
1. **Empty cells on update:** an empty `phone` or `tags` cell clears the stored value, so exporting, editing in a spreadsheet and importing again gives exactly what you edited. Each clear is reported as a warning. If the file has no `phone` or `tags` column at all, stored values are kept. If sales would rather have empty cells never erase data, it's a small change in `_save`.
2. **Unchanged rows:** a row identical to the stored contact appears in neither `created` nor `updated`, so re-importing the same file reports nothing.
3. **Duplicate emails in one file:** the first row wins and later rows are errors ("duplicate of row 2"). This applies even when the first row had its own errors, so fixing it and importing again won't turn a later row into a new duplicate.
4. **Non-UTF-8 files:** for example "CSV" saved by Windows Excel in a legacy encoding. These are rejected with a message to save as CSV UTF-8, rather than guessed at, because a wrong guess silently corrupts names.

I also exported `ImportFileError` from the package root and added the module to the README layout. Running the tests left `__pycache__/` folders, which show up as untracked because the repo has no `.gitignore`.
