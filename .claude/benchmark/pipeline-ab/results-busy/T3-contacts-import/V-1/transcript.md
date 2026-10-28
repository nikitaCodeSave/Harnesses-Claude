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

I've added the CSV import with the interface you specified. All 49 tests pass, including 25 new ones in `tests/test_importer.py`. Nothing is committed.

**How it works**
- **Accepted files:** raw bytes in UTF-8 (with or without the BOM Excel adds) or already-decoded text. Column names in the header can be in any order and any capitalisation. `name` and `email` are required; `phone` and `tags` can be left out. Values are cleaned with the existing validators, so stored data matches what `Contact.create` produces.
- **Bad rows don't block the file.** Valid rows are imported and invalid rows are skipped and listed in `errors`. Each problem names the column, and a row with several problems gets one entry for each.
- **Row numbers match the spreadsheet:** the header is row 1, and blank rows and cells containing line breaks don't throw the numbering off.
- **`ImportFileError` is raised before anything is stored.** That covers:
  - a file that isn't UTF-8 (the message says to save it as "CSV UTF-8")
  - an empty file or a missing `name`/`email` column (with a hint if the file looks semicolon-separated)
  - a column name used twice
  - broken quoting
- **Broken quoting:** I turned on strict parsing because one stray `"` otherwise silently swallows every row after it into a single cell.
- **Export → import round-trips:** a test checks that exporting contacts and importing the result gives back the same contacts.
- **Package and docs:** `ImportFileError` is also exported from the package root, and the README layout section lists the new module.

**Decisions you may want to change**
1. **Blank cells don't erase data.** If a row's email already exists, filled-in cells overwrite the stored values and blank cells keep them. So a lead sheet with gaps can't wipe phone numbers, but an import can't clear a field either. A filled-in `tags` cell replaces the whole tag set rather than adding to it, which matches how the export writes tags.
2. **Unchanged contacts appear in neither `created` nor `updated`**, so `updated` only lists contacts that actually changed. The side effect is that the counts won't always add up to the number of rows in the file.
3. **An email repeated within one file:** the first row is imported and later rows are reported as errors that point back to it. Later rows don't silently win.
4. **Odd columns and cells:**
   - Unknown columns (e.g. `company`) give one warning on row 1 and are otherwise ignored.
   - Empty trailing cells are ignored.
   - A row with extra non-empty cells beyond the header is rejected, because its data has probably shifted columns.
5. **Other encodings aren't guessed.** Files saved as plain "CSV" from Windows Excel are cp1252 and get a clear error asking for a UTF-8 save instead. Guessing the encoding risks quietly garbling names.
