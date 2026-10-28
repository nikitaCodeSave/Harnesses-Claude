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

I added the CSV import with the interface you specified. All 46 tests pass: the 24 existing ones plus 22 new ones in `tests/test_importer.py`, which include round-tripping our own `export_csv` output back in. Nothing is committed yet.

**Files:** the new `src/contactbook/importer.py`, `ImportFileError` in `errors.py`, exports added to `__init__.py`, and a README line.

**Choices I made that you may want to change:**

- **Bad rows don't stop the import.** Each bad row is skipped and listed in `errors`, and the other rows still go in. I tried to report every problem in a row at once (e.g. name *and* email *and* phone), so Sales can fix the sheet in one go.
- **Problems with the whole file leave the repository untouched.** These raise `ImportFileError`: an empty file, bytes that aren't UTF-8, a missing `name` or `email` column, a column listed twice, or broken quoting. The file is fully read before anything is saved, so even broken quoting near the end imports nothing.
- **Updating a contact never deletes data.** If the email already exists, the name is replaced, the phone is replaced only when the cell is filled in, and the row's tags are added to the existing ones. The downside is that a spreadsheet can't clear a phone or remove a tag.
- **`updated` only lists contacts that actually changed.** Importing the same file twice reports nothing the second time. Rows that match a contact without changing it appear in neither `created` nor `updated`.
- **Duplicate email in the file:** the first valid row wins and later rows are errors ("duplicate of row 2").
- **Row numbers match what the spreadsheet shows:** the header is row 1, and blank lines and cells with line breaks are counted correctly.

**Spreadsheet quirks it handles:**

- Header names ignore case and surrounding spaces, columns can be in any order, and `phone`/`tags` can be left out.
- Unknown columns, like `Company`, are ignored with a warning.
- The marker Excel puts at the start of UTF-8 files (BOM) and Windows line endings are fine.
- If a row has more values than the header has columns, it's an error, since that usually means a comma inside a value wasn't quoted.
- If the file uses `;` or tabs between columns, the error message says to save it as comma-separated CSV.
- If the file isn't UTF-8 (older Excel), the error says to save it as "CSV UTF-8". I chose not to guess the encoding, because a wrong guess would quietly garble names.

**Decision for you:** should updates merge, as now, or should the spreadsheet overwrite everything? If Sales treats their sheet as the master copy, overwriting is better, but then a blank cell would erase existing data. The change is small, in the merge step of `import_contacts`.
