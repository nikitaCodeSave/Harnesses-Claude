### [build] operator

/harness:task Sales keeps leads in spreadsheets and wants to load a whole CSV file into contactbook
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

Before I write the spec I need some decisions from you. I've read the code: `export.py` writes `name,email,phone,tags` with tags joined by `;`, and the repository uses the email as the key. Each question below has my suggested answer, so you can reply "ok" or override by number.

**What happens to the repository**
1. **Email already in the repo.** Suggestion: the row replaces the stored contact completely, the way an edit would. A blank phone cell clears the phone, and the tags cell replaces the stored tags rather than adding to them. Should it merge instead, e.g. keep the old phone when the cell is blank, or add tags to the existing ones?
2. **Rows with errors.** Suggestion: import is partial. Valid rows are saved, bad rows are skipped and listed in `errors`. The other option is all-or-nothing: if any row is bad, nothing changes.
3. **Same email twice in one file.** Suggestion: the first row is used. Each later row with that email becomes an error ("duplicate of row N") and isn't applied. Other options: the last row wins, with a warning.
4. **Updated but identical.** If a row exactly matches the stored contact, should it still be listed in `updated`? Suggestion: yes, keep it simple. Or should unchanged rows be left out of the report?

**Cell-level problems: reject the row, or keep it with a warning?**
5. **Invalid phone** (e.g. `call me`). Suggestion: an error, and the row is skipped. Importing the contact without a phone would quietly lose data.
6. **One invalid tag** among several (e.g. `vip;c++`). Suggestion: also an error for the whole row, for the same reason.
7. **What counts as a warning.** Suggestion: warnings are only for things that don't stop a row: unknown extra columns (ignored), and completely blank rows (skipped). Anything else you want flagged without being rejected?

**File format**
8. **Header.** Suggestion: required. Columns can be in any order, and names are matched ignoring case and surrounding spaces. `name` and `email` are required, so if either is missing the whole file fails with `ImportFileError`. `phone` and `tags` are optional columns. A column name appearing twice also raises `ImportFileError`.
9. **Encoding for `bytes`.** Suggestion: UTF-8, with the Excel BOM accepted and stripped. Bytes that aren't valid UTF-8 raise `ImportFileError`. No guessing between Latin-1 and cp1252. Is that acceptable, or does Sales export from an Excel that saves in cp1252?
10. **Delimiter.** Suggestion: comma only, like our export. European Excel often saves with `;`, but `;` is also our tag separator. Should we detect `;`-delimited files and raise a clear `ImportFileError` instead of misreading them?
11. **`RowIssue.row` numbering.** Suggestion: the row number as a spreadsheet would show it, so the header is row 1 and the first data row is row 2. Does that match what Sales will look for?
12. **`RowIssue.column`.** Suggestion: the canonical field name (`name`/`email`/`phone`/`tags`), or `None` for issues about the whole row (blank row, duplicate, wrong number of cells).
13. **Empty input and limits.** Suggestion: an empty file or one with only whitespace raises `ImportFileError`. A file with only a header returns an empty report. Do you want a maximum number of rows or a maximum file size? Suggestion: none for now.

**Wiring**
14. Should `ContactBook` also get an `import_csv` method, and should `ImportFileError` be exported from the package `__init__`? Suggestion: add the `__init__` export, but no `ContactBook` method, since you fixed the interface as a module function.

### [build] user

1. No, merge. A blank phone cell must never wipe a phone we already have; the phone is replaced only when the cell has a value. Tags from the file are added to the existing ones, and an import never removes tags. The name from the file replaces ours. An existing contact is updated, never duplicated, and it goes into `updated`.
2. Partial import, as you suggest. Bad rows are skipped and not applied at all, not even partly to an existing contact.
3. First row wins. Later rows with that email are errors, as you suggest.
4. I don't mind. Use your recommendation.
5. No. A bad phone must not cost us the contact. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning for that row with column `phone`.
6. Agreed. An invalid tag makes the row an error, column `tags`.
7. Not as you describe. Blank rows are skipped silently, with no error and no warning. An unknown extra column may be ignored silently or warned about, as you prefer. The only warning I need is the bad phone from 5.
8. Agreed on the required header, any column order, and case-insensitive matching ignoring spaces. A missing required column rejects the whole file. One addition: our address-book export writes `first_name` and `last_name` columns instead of `name`. Accept that pair as the name column, with the name being the two joined by one space. I don't mind about duplicate column names.
9. UTF-8 with the BOM accepted is right. The BOM must also work for text input that still starts with the BOM character, not just for bytes. Invalid UTF-8 raises `ImportFileError` telling them to re-save as "CSV UTF-8".
10. I don't mind. Comma only is fine.
11. Yes. The header is row 1, the first contact is row 2, and every line of the file counts, blank lines included.
12. The column is the lower-case name: `name`, `email`, `phone` or `tags`. A name problem in a `first_name`/`last_name` file is `name` too. For whole-row issues like a duplicate, `None` is fine by me.
13. An empty file raises `ImportFileError`. A header-only file gives an empty report. There is a limit: at most 1000 contact rows per file, not counting blank rows. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported.
14. I don't mind. Your suggestion is fine.

### [build] agent

The CSV import is built and the full test suite passes: `python3 -m pytest -q` printed `80 passed in 0.03s` and exited 0. Nothing is committed yet.

**Files**
- **Spec:** `specs/csv-import.md`. Your interface is copied in word for word, and each acceptance criterion has at least one test.
- **Code:** `src/contactbook/importer.py`, plus `ImportFileError` in `errors.py`, which the package also exports.
- **Tests:** `tests/test_importer.py`.
- **Docs:** I created `GLOSSARY.md`, added ADR `docs/adr/0001-csv-import-merges-never-removes.md` for your merge rules, and added a line to the README.

**Behaviour you didn't specify that I decided**
- **Malformed CSV:** a file with an unterminated quote is rejected with `ImportFileError`, and the message gives the line number. Before this fix, such a file swallowed every row after the quote without reporting them, and could get past the 1000-row limit.
- **Same email twice:** the first row with an email wins even if that row is itself rejected (say, for a bad tag). Every later row with that email is then an error, so none of them is applied. I treated the file as ambiguous about that contact rather than guessing.
- **Too many cells:** a row with more cells than the header is an error with column `None`.
- **Name columns:** if a file has both `name` and `first_name`/`last_name`, `name` is used.
- **Row numbers:** a row's number is the line it starts on, which matters for quoted cells that span lines. Lines ending in `\r` alone, as in some Mac files, also count.
- **Blank first line:** gets a clear "the first line must be the header" error instead of a misleading "missing column".

**Checks and reviews**
- **Mutations:** I deliberately broke the code in eight places (merge, row numbers, row limit, BOM, duplicates, name precedence) and the tests caught every one.
- **Fresh agent, against the spec:** it found the unterminated-quote bug and the inconsistent duplicate handling. Both got a failing test first, then the fix.
- **`/code-review`:** I fixed four findings: the line number in malformed-CSV errors, the blank-first-line message, the phone-warning wording (it no longer says "left unchanged" for a new contact), and reusing `normalize_tags`. I left four alone:
  - **`bytearray` input:** it raises `TypeError`. Your interface only allows `str | bytes`; this is a one-line change if the HTTP layer ever passes buffers.
  - **Two refactors:** moving duplicate tracking out of row parsing, and the helper functions that are rebuilt for each row. Both are style changes, not bugs.
  - **README outside the spec's scope list:** I added the README to the scope list instead.
