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

CSV import is added, using exactly the interface you specified: `import_contacts(repo, data) -> ImportReport` in `src/contactbook/importer.py`, and `ImportFileError` in `errors.py`, which is also exported from the package. The full test suite passes (51 tests, including 27 new ones in `tests/test_importer.py`). Nothing is committed yet.

**How rows are handled**
- **New email:** creates a contact. Values are cleaned up with the existing validators (`validation.py`), the same way manually added contacts are.
- **Email already in the repo:** the row replaces that contact's name, phone and tags, just as an exported row describes a whole contact. An empty phone cell clears the phone. Exporting, editing in a spreadsheet and importing again gives you exactly what's in the file.
- **Row identical to what's stored:** it isn't listed as created or updated, because nothing changed. So created + updated + errors won't always add up to the number of rows.
- **Any bad value in a row:** the whole row is skipped and every problem is reported, one per field. A row is never half-imported, so an invalid phone doesn't quietly drop the phone.
- **Same email twice in the file:** the first row is imported and the later one is an error ("already appears on row 2"). Neither is silently chosen over the other.
- **Row numbers** count the header as row 1, matching what sales sees in the spreadsheet, even when a cell spans several lines.

**When `ImportFileError` is raised**
- Raised for an empty file, a header missing `name` or `email`, or a column named twice in the header.
- Raised for broken quoting. Python's CSV reader would otherwise silently merge the rest of the file into one cell.
- Raised for bytes that aren't UTF-8. The message tells the user to save as "CSV UTF-8".
- In every one of these cases the repo is left untouched, even if valid rows came before the problem.

**Lenient on purpose**
- Header names ignore case and surrounding spaces.
- An Excel byte-order mark at the start of the file is accepted.
- Blank rows like `,,,` are skipped.
- A short row's missing cells count as empty.
- Unknown columns produce a warning and are ignored.

**Decisions for you**
1. **Non-UTF-8 files are rejected rather than guessed.** Excel on Windows saves plain "CSV" in a Windows-specific encoding, so some files from sales may hit this. I chose an error over mangled names. Falling back to the Windows encoding is easy to add, at the risk of occasionally garbled characters.
2. **Only `name` and `email` columns are required.** If the `phone` or `tags` column is missing entirely, existing contacts keep their current values for it. The alternative is to require all four export columns.
3. **Semicolon-separated files** (European Excel's default) are rejected, with a hint that the file must be comma-separated.

I also updated the README's layout section.

### [build] user

Two of those rules are wrong. Please change them.

1. **Existing contact (same email):**
   - Phone is replaced only when the cell has a value. An empty phone cell, or a missing phone column, must never wipe a phone we already have.
   - Tags from the file are added to the existing ones. An import never removes tags.
   - The name from the file still replaces ours.
2. **Invalid phone:** don't skip the row. Import or update the rest of the row and leave the phone as it was (none for a new contact). Report it as a warning on that row with column `phone`, not as an error. A bad phone shouldn't cost us the contact.

Your decisions 1 and 2 are fine as you recommended. I don't mind about the other points, including the semicolon files and the identical-row handling.

### [build] agent

I've changed both rules in `src/contactbook/importer.py` and updated the tests. All 55 tests pass, and nothing is committed yet.

1. **Existing contact (same email):**
   - The name from the file replaces ours.
   - The phone is replaced only by a valid phone in the cell. An empty cell or a missing phone column keeps the stored phone.
   - Tags from the file are added to the existing ones, and an import never removes tags.
2. **Invalid phone:** the row is still created or updated. The phone stays as it was, or empty for a new contact. It's reported as a warning on that row with column `phone`, for example `is not a phone number: 'call me'; phone ignored`.

**Unchanged behaviour:**
- **Other bad fields:** a row with a bad name, email or tag is still skipped and reported as an error.
- **Rows that add nothing:** a row whose tags are already stored and whose name is the same isn't listed as updated. The same goes for a row that would only clear the phone.

**One detail to know:** if a row is skipped because of another error and also has a bad phone, the phone problem is still listed as a warning, next to that row's errors. Nothing from that row is imported.

I updated the module docstring to describe the new rules and added tests for each:
- An empty phone cell keeps the stored phone.
- A phone cell with a value replaces the stored one.
- Tags are only ever added.
- An invalid phone on a new contact gives a warning and the contact has no phone.
- An invalid phone on an existing contact gives a warning, keeps the stored phone and still updates the rest.
