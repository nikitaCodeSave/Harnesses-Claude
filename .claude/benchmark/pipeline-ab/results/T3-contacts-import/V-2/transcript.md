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

CSV import is in place with the interface you specified: `import_contacts(repo, data) -> ImportReport` in `src/contactbook/importer.py`, plus `RowIssue` and `ImportFileError`. A file exported by `export_csv` imports back exactly, and importing the same file a second time changes nothing. All 39 tests pass, including 15 new ones in `tests/test_importer.py`.

**What happens on import**
- **Errors in one row don't stop the rest.** A row with a bad value is added to `errors` and skipped; the other rows still import. All bad values in a row are reported, not just the first, e.g. `RowIssue(row=2, column='email', message="is not a valid address: 'not-an-email'")`.
- **Row numbers match the spreadsheet.** The header is row 1, so the numbers match what Sales sees in Excel or Sheets.
- **Whole-file problems change nothing.** The file is fully read and checked before anything is saved. If it isn't UTF-8, the CSV is malformed, or the header is missing `name`/`email` or repeats a column, `ImportFileError` is raised and the repository stays as it was.
- **New email creates a contact; known email updates it.** Updates are deliberately non-destructive: the name is replaced, tags are added to the existing ones rather than replacing them, and a blank phone cell keeps the stored phone. `updated` only lists contacts that actually changed.
- **The same email twice in one file** is an error on the later row ("duplicate of row 2; row skipped"), so you never get one email in both `created` and `updated`.

**Spreadsheet leniency**
- These are accepted without comment: a UTF-8 byte-order mark (Excel adds one), header names in any case or with extra spaces, empty rows like `,,,`, and short rows.
- Unknown columns, and values outside the named columns, are ignored and added to `warnings`.
- Files using semicolons or tabs as separators are also accepted, which is what Excel produces in many European locales.

**Decisions you may want to revisit**
1. **Non-UTF-8 files are rejected.** Old Excel "CSV" files in Windows encodings get a clear error telling the user to save as "CSV UTF-8". I chose not to guess the encoding, because a wrong guess would quietly garble names.
2. **Updates add to existing data and never clear it.** That means an import can't remove a phone number or a tag. If Sales expects "the file is the source of truth" behaviour, that's a small change.

I also exported `ImportFileError` from the package's `__init__` alongside the other errors and added the module to the README layout. Nothing is committed.
