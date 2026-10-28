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

I've read the code (no `GLOSSARY.md`, ADRs or `specs/` exist yet). Before I write the spec I need some decisions from you. Each one has my recommendation, so you can just reply "agree" or change the numbers you disagree with.

**A. When a row's email already exists**
1. **What "update" means.** I'd overwrite name, phone and tags with what the row says, so the import works like a sync with the spreadsheet. The alternative is a merge, where tags are unioned and a blank phone keeps the stored one. Note that with overwrite, a blank phone cell clears the stored phone.
2. **Rows identical to the stored contact.** I'd leave them out of both `created` and `updated`, so `updated` only lists real changes. Alternative: list them in `updated` anyway.
3. **The same email twice in one file** (case-insensitive). I'd import the first occurrence and report each later one as an **error** on its own row. Alternative: the last row wins, with a warning.

**B. Bad rows**
4. **Partial or all-or-nothing.** I'd apply the valid rows and report the bad ones in `errors`, which suits sales fixing a few lines and re-running. Alternative: if any row has an error, change nothing.
5. **How strict per field.** I'd make any invalid field (name, email, phone, or any one tag) an error that skips the whole row. Alternative: drop just the bad phone or tag, import the rest of the row, and add a warning. In that case `warnings` would mostly hold unknown columns and similar notes.
6. **Row numbers.** I'd use spreadsheet numbering: the header is row 1 and the first data row is row 2, counting physical lines. Fully blank lines would be skipped silently but still counted.

**C. The file as a whole** (these raise `ImportFileError`)
7. **Encoding.** I'd decode bytes as UTF-8 and strip a BOM if present (Excel adds one). Bytes that aren't valid UTF-8 → `ImportFileError`, with no guessing at cp1252.
8. **Header.**
   - It must be present, and `name` and `email` are required columns. A missing required column → `ImportFileError`.
   - `phone` and `tags` columns are optional.
   - Matching ignores case and surrounding spaces, and column order doesn't matter.
   - An unknown extra column → one warning (`row=1`, with that column name), and the column is ignored.
   - A duplicated header column → `ImportFileError`.
9. **Delimiter.** I'd accept commas only, exactly like the export. Excel in some locales saves with `;`, which clashes with our `;` tag separator, so a `;`-delimited file would fail on the missing `email` column. Should I add a hint to that error message?
10. **Empty file vs header only.** I'd raise `ImportFileError` for an empty file (or one that is only whitespace or a BOM). A file with just the header returns an empty report.
11. **Rows with the wrong number of cells.** If a row has more cells than the header, I'd make that a row error. If it has fewer, the missing cells count as blank.
12. **Size limit.** I'd set none for now, since the repository is in memory anyway. Do you want a cap?

**D. Scope**
13. Is it right that `ContactBook`, the HTTP API and the CLI are out of scope, and that `import_contacts` plus the error class are the whole deliverable?

### [build] user

Going by number:
1. Disagree. It's a merge, not an overwrite. The file's name replaces ours. Phone is replaced only when the cell has a value, so a blank cell or a missing phone column never wipes a stored phone. Tags from the file are added to the existing ones, and an import never removes tags.
2. I don't mind. Either way is fine.
3. Agree. The first row wins, and each later row with that email is an error on its own row and isn't applied.
4. Agree. Partial import. Good rows go in and bad rows are reported and skipped. A bad row isn't applied at all, not even partly to an existing contact.
5. Partly disagree. An invalid name, email or tag makes the row an error. A bad phone must not cost us the contact: import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning for that row with column `phone`.
6. Agree. The header is row 1 and the first contact is row 2. Every line counts, blank lines included. Blank lines, and rows where all cells are empty or spaces, are skipped silently.
7. Agree. Also handle text input that still starts with the BOM character. The message for bad bytes should tell them to re-save as "CSV UTF-8".
8. Mostly agree. Header matching, required and optional columns, and a missing required column are fine as you describe them. One addition: the address-book export writes `first_name` and `last_name` columns instead of `name`. Accept that pair as the name column, with the name being first and last joined by one space. A name problem there is reported with column `name`. I don't mind about unknown extra columns (ignoring them or adding a warning is fine, just never an error) or about duplicated header columns.
9. Comma only is fine. I don't mind the hint.
10. Agree. An empty file is rejected, and a header-only file gives an empty report.
11. I don't mind.
12. Yes, I want a cap. At most 1000 contact rows per file, not counting blank rows. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported.
13. I don't mind. Your scoping is fine.

Also, `column` in the report is the lower-case column name: `name`, `email`, `phone` or `tags`. Tags are separated by `;` in one cell.

### [build] agent

The CSV import is built and the full test suite passes:

```
$ python3 -m pytest -q
........................................................................ [ 87%]
..........                                                               [100%]
82 passed in 0.04s
```

That's 64 new import tests plus the 18 that already existed. Each of the spec's 28 criteria has at least one test. I wrote the tests before the code and confirmed they failed first; I also broke the BOM handling on purpose to check that its test catches it.

**Where things are**
- **Spec:** `specs/csv-import.md`, with your interface copied verbatim.
- **Code:** `import_contacts`, `ImportReport` and `RowIssue` are in `src/contactbook/importer.py`. `ImportFileError` is in `src/contactbook/errors.py`. All of them are exported from the package.
- **Decision record:** `docs/adr/0001-csv-import-merges.md` records the merge rule, partial import, the bad phone being a warning, first-occurrence-wins, and the file limits, since later import paths will need to follow them.
- **Glossary:** I started `GLOSSARY.md` with the import terms. `README.md` now lists the new module.

**Choices you left to me** (marked *(my call)* in the spec, easy to change):
- A row that changes nothing on an existing contact appears in neither `created` nor `updated`.
- A column name that appears twice in the header rejects the file.
- Unknown columns get one warning each, with `row=1` and `column=None`. Empty header cells, which spreadsheets add with trailing commas, are ignored without a warning.
- If the header has both `name` and `first_name`/`last_name`, `name` is used and the other two are reported as unknown columns.
- A row with more cells than the header is an error with `column=None`. Its email doesn't block a later row with the same email.
- A row with fewer cells than the header treats the missing cells as blank.
- A file the CSV parser can't read, such as one with an unterminated quote, is rejected as a whole. So one badly quoted line blocks the entire file rather than just that row.

**Review:** because this is a parser, a fresh agent reviewed the code against the spec, covering line endings, the BOM, the 1000-row limit, header edge cases, duplicate emails and merging. It found no defects. It listed four untested edge cases. I covered three with new tests: Windows and old-Mac line endings, the email in an over-long row, and `name` alongside only `first_name`. The fourth, warning messages naming the ignored columns when the header has both `name` and the `first_name`/`last_name` pair, is still only checked by row and column. I also reworded two loose spec sentences to match what the code does. I haven't run `/code-review`.

Nothing is committed. Running the tests also left untracked `__pycache__/` folders, because the repo has no `.gitignore`.
