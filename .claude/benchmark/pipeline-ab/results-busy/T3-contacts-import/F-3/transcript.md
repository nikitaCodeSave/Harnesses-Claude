### [spec] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim.

### [spec] agent

I've read the code. Relevant facts: the export writes the header `name,email,phone,tags`, joins tags with `;`, and leaves the phone cell empty when there's no phone. The repository is keyed by normalised email, and all validation goes through `Contact.create`.

First round of questions. Each has my suggested default, so you can just answer "yes" or correct the ones you disagree with.

**A. Partial success vs all-or-nothing**
1. If some rows are invalid, are the valid rows still imported, with the bad ones listed in `errors`? Or does any row error mean nothing is imported? *Suggested: import the valid rows and skip the bad ones. That's what a report with both `created` and `errors` implies.*
2. If the file as a whole is rejected (`ImportFileError`), does the repository stay completely untouched? *Suggested: yes.*

**B. Existing contacts (same email already in the repo)**

3. Should a row with an existing email update that contact, or be reported as an error or skipped? *Suggested: update it. That's what `updated` is for.*
4. On update, does the CSV overwrite the stored data? Specifically:
   - Name: overwritten? *Suggested: yes.*
   - Empty phone cell: does it clear the stored phone or keep it? *Suggested: keep it. Spreadsheets often have gaps, and silently erasing data is worse.*
   - Tags: replace the stored tags, or add to them? *Suggested: add to them, so tags already in the system aren't lost.*
5. If a row matches an existing contact exactly (no change), is the email listed in `updated`, or in neither list? *Suggested: neither, so `updated` means something actually changed.*

**C. Same email twice in one file**

6. Suggested: the first occurrence wins, and each later one is an error on its own row that names the earlier row. Alternatives are "last wins" or merging the rows.

**D. Header and columns**

7. Is a header row required? *Suggested: yes. Without `name` and `email` columns the whole file fails.*
8. Should header names be matched case-insensitively, ignoring surrounding spaces and column order? *Suggested: yes, because people retype headers in Excel.*
9. Are `phone` and `tags` optional columns? *Suggested: yes.*
10. Unknown extra columns (e.g. "Company"): reject the file, or ignore them with a warning? *Suggested: ignore and add one warning (`row` = 1, `column` = the column name).*
11. Same column name twice in the header? *Suggested: the file fails.*

I'll ask about encoding, row numbering, the tag separator and empty/blank-row edge cases next round.

### [spec] user

1. Yes. Valid rows go in; bad rows are listed in `errors` and skipped. A bad row isn't applied at all, not even partly to an existing contact. Only whole-file problems (e.g. missing required column) reject everything.
2. Yes, a rejected file imports nothing.
3. Yes, update it. Not an error, never a second contact; the email goes in `updated`.
4. Name: yes, the file's value replaces ours. Phone: replaced only when the cell has a value; an empty cell or no phone column never wipes a stored phone. Tags: add to the existing ones; an import never removes tags.
5. I don't mind, use your suggestion.
6. Yes, first row wins; every later row with that email is an error on that later row and isn't applied.
7. Yes, the first line is the header. A missing required column (`email` or `name`), or a completely empty file, rejects the whole file.
8. Yes: case-insensitive, surrounding spaces ignored, column order free.
9. Yes, `phone` and `tags` are optional.
10. Ignoring them is fine; a warning is fine too. Just never an error.
11. I don't mind, use your suggestion.

### [spec] agent

That settles the merge rules. Second (and probably last) round covers file format and edge cases. Again, each has a suggested default.

**E. Encoding and format**

12. Bytes input: UTF-8, with or without the BOM that Excel adds. If the bytes aren't valid UTF-8 (e.g. an old Excel "CSV (Windows)" save in cp1252), should the whole file be rejected with an `ImportFileError` saying it must be UTF-8? *Suggested: yes. Guessing encodings silently corrupts names like "Müller".*
13. Delimiter: comma only, like our export? Or also accept semicolon files, which European-locale Excel produces? *Suggested: comma only. A semicolon file then fails on "missing email column", and the error message should hint at the delimiter.*
14. Tags cell: split on `;` like the export does, ignoring blank pieces (e.g. `vip;;lead;`)? *Suggested: yes.*
15. Should cells that are quoted and contain line breaks be supported, as the CSV standard allows? *Suggested: yes.*

**F. Row numbering and issue fields**

16. What does `RowIssue.row` mean? *Suggested: the header is row 1 and the first data row is row 2, which matches what Sales sees in the spreadsheet. With multi-line cells, it's the number of the record, not the physical line.* File-level warnings (unknown column) use row 1.
17. `RowIssue.column`: the canonical column name (`name`/`email`/`phone`/`tags`) when the problem is tied to one field, `None` otherwise (e.g. duplicate email? no, that one is `email`; a ragged row would be `None`)? *Suggested: yes, canonical lowercase names, and the actual header text for unknown-column warnings.*
18. If a row has several bad fields (bad email and bad phone), should there be one error per bad field, or just the first one? *Suggested: one per bad field, so Sales can fix the whole row in one pass.*

**G. Edge cases**

19. Should completely blank rows (all cells empty, which is common at the end of a spreadsheet) be skipped silently, not counted as errors? *Suggested: yes.*
20. Header row present but no data rows: valid, with an empty report? *Suggested: yes, not an `ImportFileError`.*
21. Ragged rows (more cells than the header, or fewer): *Suggested: missing trailing cells count as empty. Extra non-empty cells are a row error, since the data has probably shifted columns.*
22. Duplicates and invalid rows: if row 3 has `ann@x.com` but is invalid (bad phone), and row 7 has `ann@x.com` and is valid, is row 7 applied? *Suggested: yes. Only a row that was actually applied "claims" the email, so a typo in the first row doesn't block the corrected row below it.* Duplicates are detected after normalisation (`Ann@X.com` = `ann@x.com`).
23. One invalid tag in a row (e.g. `vip;key account!`): is the whole row an error? *Suggested: yes, consistent with "a bad row isn't applied at all".*
24. Should there be a size limit (rows or bytes) above which the file is rejected? *Suggested: no limit for now (non-goal).*
25. Order of `created` / `updated`: file order? *Suggested: yes.*

### [spec] user

12. Yes. Invalid UTF-8 means `ImportFileError`, and the message should tell them to re-save as "CSV UTF-8". A BOM must work for bytes, and also for text input that still starts with the BOM character.
13. I don't mind, use your suggestion.
14. Yes. Split on `;`, normalise each tag with the existing tag helper, and ignore empty pieces and repeats.
15. Yes, support them. I don't mind how rows are numbered when a quoted cell spans several lines.
16. `row` is the row number Sales sees in Excel: header is row 1, first contact is row 2. Every line of the file counts, blank lines included, so a blank line between two contacts still moves the numbers down.
17. Yes, `column` is the lower-case column name (`name`, `email`, `phone` or `tags`). For ragged rows and unknown columns I don't mind.
18. I don't mind. One entry or several is fine.
19. Yes, skip them silently with no error or warning. That covers empty lines and rows where every cell is empty or only spaces, like Excel's `,,,` lines. They still count in the row numbering from 16.
20. Yes. A file with only the header is fine: nothing happens and the report is empty.
21. I don't mind, use your suggestion.
22. I don't mind, use your suggestion.
23. Yes. An invalid tag makes the whole row an error with column `tags`, and the row isn't applied.
24. No, there is a limit. A file can have at most 1000 contact rows. Blank rows don't count towards that. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported, because I'd rather people split it than end up with a half-loaded file.
25. I don't mind.

### [spec] agent

I've written the spec to `SPEC.md` in the repo root. It covers the purpose, your interface copied word for word, 28 checkable acceptance criteria and a list of non-goals. I haven't written any code or committed anything.

Where you said "I don't mind", I used my suggested default. A few points are my own reading of your answers, so please check them:

- **1000-row limit:** invalid rows count towards it and blank rows don't. Exactly 1000 is accepted; 1001 rejects the whole file.
- **"Completely empty" file:** I treat a file with no header line as empty, so it's rejected. A file with a header followed only by blank rows is fine and returns an empty report.
- **Unknown columns:** each one produces a warning on row 1, with `column` set to the header text exactly as written. You said a warning or ignoring was fine; I chose the warning so it's checkable.
- **Duplicate-email error:** the message names the row that won, so Sales can find both rows.
- **Two extra criteria:** importing our own export into an empty repository recreates the same contacts with no issues (27). Importing the same file twice changes nothing the second time (28). Both follow from your rules, and they make good tests.
- **Exports:** the spec doesn't require `ImportFileError` or `import_contacts` to be exported from the package's `__init__.py`. Your interface only fixes the module paths. Tell me if you want that added.

If any of these are wrong, tell me and I'll update `SPEC.md`.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

The CSV import is built and the full test suite passes: 94 tests, of which the 70 new ones in `tests/test_importer.py` cover the spec's acceptance criteria.

**Command:** `python3 -m pytest`
```
collected 94 items

tests/test_export.py ..                                                  [  2%]
tests/test_importer.py ................................................. [ 54%]
.....................                                                    [ 76%]
tests/test_models.py ....                                                [ 80%]
tests/test_repository.py ....                                            [ 85%]
tests/test_service.py ...                                                [ 88%]
tests/test_validation.py ...........                                     [100%]

============================== 94 passed in 0.03s ==============================
```

**What changed**
- **`src/contactbook/importer.py`** (new): contains `import_contacts`, `ImportReport` and `RowIssue`. It reads and checks the whole file before writing anything to the repository, so a rejected file never leaves the repository half-changed. Field checks reuse the existing `validation.py` helpers.
- **`src/contactbook/errors.py`**: adds `ImportFileError(ContactError)`.
- **`__init__.py`**: exports the new names. **`README.md`**: the module list now includes the importer.
- The tests are grouped by spec section: whole-file errors, encoding and format, row processing, new vs. existing contacts, duplicate emails, and the report (including the export round trip and importing the same file twice).

**Decisions where the spec is unclear**
1. **A row that matches the stored contact exactly still counts as the first row for its email.** Read literally, the spec's "applied row" doesn't include rows that change nothing, so such a row wouldn't block a later row with the same email. That makes repeated imports flip back and forth: say row 2 matches the stored contact and row 5 has a different name for the same email. Row 5 would update the contact on one import, then row 2 would change it back on the next. So I made the first valid row win, whether or not it changes anything. `test_unchanged_row_still_wins_its_email` checks this. Tell me if you want the literal reading instead.
2. **Rows after the header** are numbered by counting rows, not physical lines. That matches what Excel shows for a quoted cell spanning several lines, which the spec leaves open.
3. **Trailing empty header cells** (`name,email,,`) are ignored instead of being treated as two columns with the same blank name, which would have rejected the file. Data under them is handled like any cell beyond the header.
4. **Each row reports all of its problems**, not just the first, which the spec allows. A row with a duplicate email also gets the duplicate error alongside any other errors.
5. **A blank first line** counts as "no header line" and rejects the file. **Malformed CSV** also raises `ImportFileError`.

Nothing is committed yet. The test run created `__pycache__/` folders, which show as untracked because the repo has no `.gitignore`.
