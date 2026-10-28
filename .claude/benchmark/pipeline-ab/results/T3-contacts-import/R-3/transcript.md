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

I've read the code (the `Contact` model, validators, repository, `export_csv` with columns `name,email,phone,tags`, tags joined with `;`). Here's the first round of questions. Each one has my recommended default, so you can answer "ok" or just correct the ones you disagree with.

**A. Partial success vs. all-or-nothing**
1. If some rows are invalid, do the valid rows still get imported, with the bad ones listed in `errors`? Or does any row error mean nothing is written?
   *Recommendation: valid rows are imported and bad rows are skipped and reported. All-or-nothing makes sales fix the whole sheet before anything loads.*

**B. Contacts that already exist (email matches, case-insensitive)**
2. Should the row overwrite the existing contact? *Recommendation: yes. Name, phone and tags are all replaced by what's in the file, so the file is the source of truth.*
3. If the phone cell is empty for an existing contact, should that clear the stored phone or keep it? Same question for an empty tags cell: clear the tags or keep them? *Recommendation: empty means clear. That matches the export, where "no phone" is written as an empty cell, and it keeps export→import a round trip.*
4. If the row is identical to what's already stored, should it count as `updated`, be listed nowhere, or produce a warning? *Recommendation: listed nowhere. Then re-importing the same file reports zero changes.*

**C. Problems inside the file**
5. If the same email appears twice in the file: error on the second row, last row wins, or something else? *Recommendation: the first row is imported and later duplicates are errors. Silently letting the last row win hides data entry mistakes.*
6. If one tag in a row is invalid (e.g. `vip!`), should the whole row be rejected, or the bad tag dropped with a warning? *Recommendation: reject the row. Partly importing a contact is surprising.*
7. If a row has several bad fields, should each one be reported (one `RowIssue` per column), or only the first? *Recommendation: report each, so sales can fix everything in one pass.*
8. What counts as a **warning** (imported, but worth flagging) rather than an error? My candidates:
   - unknown extra columns, which get ignored (reported once with `row` = header row)
   - fully blank rows, which get skipped
   - anything else you have in mind?

**D. Row numbering**
9. Should `RowIssue.row` match the row number sales sees in the spreadsheet (header = row 1, first contact = row 2)? *Recommendation: yes.*

**E. File format (Excel is the main source here)**
10. Should the header be required? Can columns come in any order, with header names matched case-insensitively and ignoring surrounding spaces? Should `phone` and `tags` columns be optional? *Recommendation: header required, any order, lenient matching, phone/tags optional. If `name` or `email` is missing, that's an `ImportFileError`.*
11. Encoding of `bytes`: UTF-8, with or without the BOM that Excel adds. Should non-UTF-8 files (e.g. Windows-1251/1252 from an older Excel "Save as CSV") be rejected with `ImportFileError`, or guessed? *Recommendation: reject with a clear message. Guessing encodings silently corrupts names.*
12. Delimiter: Excel in many European/Russian locales saves CSVs with `;` instead of `,`. Does your sales team's Excel do that? Should we support `;`-delimited files? (That clashes with `;` as the tag separator inside a cell, which only works if the cell is quoted.)
13. An empty file, or a file with only a header: `ImportFileError`, or an empty report? *Recommendation: an empty file (no header) is an `ImportFileError`. A header-only file gives an empty report.*

**F. Scope**
14. Is there a size limit (max rows or bytes) beyond which the whole file is rejected?
15. My assumed non-goals: no CLI/HTTP endpoint, no `ContactBook` method, no deleting contacts that are missing from the file, no dry-run/preview mode, no columns beyond the four export columns. Is anything there actually wanted?

### [spec] user

1. Agreed: good rows go in, bad rows are reported in errors and skipped. A bad row is not applied at all, not even partly to an existing contact. The exception is whole-file problems (bad header, too big, bad encoding), which reject the whole file.

2. Yes, update the existing contact. It is never an error and never a second contact. It goes into `updated`. Name: the file's value replaces ours. Phone and tags work differently, see 3.

3. I disagree. An empty phone cell, or a missing phone column, must NOT wipe the stored phone. The phone is replaced only when the cell has a value. Tags: the file's tags are added to the existing ones, and an import never removes tags. So an empty tags cell changes nothing.

4. I don't mind. Either way is fine.

5. Agreed: the first row wins, and every later row with that email is an error on that later row and is not applied.

6. Agreed: an invalid tag makes the whole row an error (column `tags`). Tags in the cell are separated by `;`, each is normalised with the existing tag helper, and empty pieces and repeats are ignored.

7. I don't mind whether it is one entry or several per row.

8. A warning is only this: if the phone fails validation, the rest of the row is still imported or updated. The phone is left as it was (none for a new contact), and the row gets a warning with column `phone`. Blank rows (empty lines, or rows where every cell is empty or spaces) are skipped silently, with no warning. Unknown extra columns are ignored. Silently or with a warning is fine, just never an error.

9. Yes, with one detail: every line of the file counts, blank lines included. The header is row 1 and the first contact is row 2. `column` is the lower-case column name: `name`, `email`, `phone` or `tags`.

10. Agreed: the header is required, columns can be in any order, and names are matched case-insensitively ignoring surrounding spaces. `email` and `name` are required, `phone` and `tags` are optional. If a required column is missing, the whole file is rejected with `ImportFileError`. One addition: the file may have `first_name` and `last_name` columns instead of `name`. They come from our address-book export script for Outlook and Google Contacts. That pair counts as the name column, and the name is the first and last name joined with one space. A name problem in such a file is still column `name`.

11. Agreed: reject with `ImportFileError`, telling them to re-save as "CSV UTF-8". The BOM must just work, for bytes and also for text that still starts with the BOM character.

12. I don't mind. Comma is what we need.

13. Agreed: a completely empty file is an `ImportFileError`, and a header-only file gives an empty report.

14. Yes: at most 1000 contact rows per file. Blank rows don't count. A bigger file is rejected whole with `ImportFileError` and nothing is imported, so people split it.

15. Your non-goals are fine.

Two more points on rows. The name is required on every row, also when it updates an existing contact. It is validated with the existing name helper, and empty is an error on column `name`. The email is normalised with the existing email helper (trim and lower-case). A missing or invalid email is an error on that row. `created` and `updated` list the normalised emails.

### [spec] agent

Thanks, that settles most of it. A few edge cases are still open, and the spec has to say something about each one. Defaults are again in italics:

1. **Duplicate after a failed row.** Row 2 has `ann@x.com` with an empty name (an error), and row 5 has `ann@x.com` again and is valid. Is row 5 a duplicate (error), or does it get imported because nothing was applied from row 2? *Recommendation: row 5 is imported. "First row wins" means the first row that was actually applied.* The same question applies when row 2 was applied but got a phone warning: *in that case row 5 is a duplicate error.*

2. **Name columns.**
   - What if the file has `name` and also `first_name`/`last_name`? *Recommendation: `name` wins and the other two are ignored like unknown columns.*
   - What if only one of `first_name`/`last_name` is present, with no `name`? *Recommendation: the name column counts as missing, so `ImportFileError`.*
   - What if one of the two cells is empty on a row (e.g. only a first name)? *Recommendation: the name is just the non-empty part. It's an error only if both are empty.*

3. **Broken CSV structure.**
   - What if a row has more cells than the header? *Recommendation: an error on that row with column `None`.*
   - What if a row has fewer cells? *Recommendation: the missing cells count as empty. Excel often trims trailing empty cells, so `ann,ann@x.com` with no phone/tags is normal.*
   - What if a quoted cell is never closed? *Recommendation: `ImportFileError`.*
   - What if the header repeats a column (two `email` columns)? *Recommendation: `ImportFileError`.*

4. **The 1000-row limit.** Do rows that turn out to be errors count toward the 1000? *Recommendation: yes. Every non-blank line after the header counts, so the limit can be checked before anything is applied.*

5. **Multi-line cells.** A quoted cell can contain a line break, e.g. a name typed with Alt+Enter in Excel. Since every line counts, which row number does that record get, and do the following records shift? *Recommendation: the record gets the number of the line it starts on, and later records keep counting physical lines. That way the numbers match what a text editor shows. Excel would show it as one row, so the two views can differ.* Or should a cell containing a line break just be an error?

### [spec] user

1. If row 2 is an error, the email's first appearance is an error row. I don't mind whether row 5 counts as a duplicate, so use your recommendation. If row 2 was applied but got only a phone warning, row 5 is a duplicate error. That matches what I want.

2. I don't mind any of the three. Use your recommendations. A name problem is still column `name`.

3. Rows with more or fewer cells than the header: I don't mind, so use your recommendation. For an unclosed quote, I don't mind, so use `ImportFileError`. For a repeated header column, I don't mind either, so use `ImportFileError`.

4. Blank rows don't count toward the limit. Counting every non-blank line after the header, including rows that turn out to be errors, is fine. Over 1000 means the whole file is rejected with `ImportFileError`.

5. I don't mind. Use your recommendation.

### [spec] agent

I've written the spec to `SPEC.md`. The interface block is copied word for word from your request, and there are 43 acceptance criteria plus a list of non-goals.

**Your rules:**
- **Partial import:** good rows are imported. A bad row isn't applied at all, not even partly to an existing contact. Whole-file problems raise `ImportFileError` and leave the repository unchanged.
- **Updating existing contacts:** the name is replaced. A phone is replaced only when its cell has a value. Tags are only ever added, never removed.
- **Warnings:** the only warning is for an invalid phone. The rest of the row is still applied and the phone stays as it was.

**Where you didn't mind, the spec uses my recommendations:**
- The first *applied* row wins for an email. If an earlier row with that email was rejected, a later valid row is imported.
- `name` beats `first_name`/`last_name` if a file has all three. Having only one of the pair counts as a missing name column. If one of the two cells is empty, the name is just the other one.
- A row with too many cells is an error with column `None`. Missing trailing cells count as empty.
- An unclosed quote or a repeated header column rejects the whole file.
- A multi-line record gets the number of the line it starts on.

**Left open, as you asked:**
- Whether a row that changes nothing is listed in `updated`.
- Whether a bad row gets one error entry or several.
- Whether unknown columns are ignored silently or with a warning.

**I added a few things you didn't state.** Check you're happy with these:
- `\r\n` line endings (which Excel writes) must work.
- `created` and `updated` are in file order, and an email appears at most once across both.
- A file with exactly 1000 contact rows is accepted.
- Two round-trip checks: importing an export into an empty repository recreates the same contacts, and importing it back into its source repository changes nothing and reports nothing.

### [spec] user

Two of your additions are fine. \r\n must work, and exactly 1000 rows is accepted. I don't mind the file-order point. One needs a correction.

In the round-trip check, "importing it back into its source repository changes nothing and reports nothing" is stricter than what I want. I don't mind whether an unchanged existing contact is listed in `updated`. Please word it so that the repository is unchanged and `errors` and `warnings` are empty, and nothing is said about `updated`. It also shouldn't appear in `created`. That also keeps it consistent with your "left open" item.

Everything else matches what I told you. Please fix that line.

### [spec] agent

I've reworded criterion 43 in `SPEC.md`. It now says that importing an export back into its source repository leaves the repository unchanged (same contacts, same values, none added), and that `created`, `errors` and `warnings` are empty. It says nothing about `updated` and points to criterion 40, which leaves that open.

That was the only change. The `\r\n`, exactly-1000-rows and file-order criteria stay as they were.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've added 148 acceptance tests under `tests/acceptance/`. All of them fail right now, and only because the feature doesn't exist yet: `contactbook.importer` is missing, and so is `ImportFileError` in `contactbook.errors`. The existing 24 tests still pass.

**Command I ran:**
```
python3 -m pytest tests/acceptance -q
```
**Output (last line):**
```
148 failed in 0.35s
```
I ran it again with `--tb=line` and grouped the error messages. Every failure is one of these two:
```
No module named 'contactbook.importer'
cannot import name 'ImportFileError' from 'contactbook.errors'
```
The full suite (`python3 -m pytest -q`) gives `148 failed, 24 passed`.

**What's there**
- There is one file per spec section: `test_interface.py`, `test_input_encoding.py` (criteria 1–6), `test_header.py` (7–15), `test_whole_file.py` (16–18), `test_rows_general.py` (19–24, plus how rows are numbered), `test_rows_email.py` (25–28), `test_rows_name.py` (29–31), `test_rows_phone.py` (32–35), `test_rows_tags.py` (36–38), `test_created_updated.py` (39–41) and `test_round_trip.py` (42–43).
- Each test name starts with its criterion number, e.g. `test_c27_...`.
- The tests call only the names the spec lists (`import_contacts`, `ImportReport`, `RowIssue`, `ImportFileError`), plus the existing repository, `Contact`, `ContactBook` and `export_csv`.
- `support.py` holds shared helpers. It imports the importer inside each test rather than at the top of the file, so each test fails on its own instead of the whole run stopping at load time. Every test that expects `ImportFileError` also checks that the repository is unchanged afterwards (criterion 18).

**Where the spec allows more than one behaviour, the tests accept any of them:**
- A row with several problems can give one error entry or several. The tests only require at least one error with the right row number and column.
- A notice about unknown columns is optional (criterion 13). The tests only require that such a warning has column `None`.
- A row that changes nothing may or may not appear in `updated` (criteria 40 and 43). Both are accepted.

**Places where I read the spec strictly, which you might want to check:**
- `test_c22_extra_empty_cell_is_still_too_many_cells`: a trailing comma, as in `Ann Lee,ann@example.com,` under a two-column header, counts as too many cells and is an error.
- `test_c11_first_and_last_name_are_ignored_when_name_is_present`: if the `name` column exists but is empty for a row, that row is a name error even when `first_name`/`last_name` are filled in.
- `test_c05_semicolon_is_not_a_delimiter`: a header like `name;email;phone;tags` raises `ImportFileError`, because with a comma delimiter it has no email column.

Nothing is committed. The new files are untracked next to `SPEC.md`.

### [check] user

Three of the strict readings you listed go beyond what I care about, so those tests shouldn't pin one behaviour.

- test_c22_extra_empty_cell_is_still_too_many_cells: I don't mind what happens to rows with more or fewer cells than the header. A trailing comma could be accepted or flagged. Please drop the assertion that it's an error, or accept either outcome.
- test_c11_first_and_last_name_are_ignored_when_name_is_present: I don't mind how a file that has both name and first_name/last_name is handled. Please remove this test or make it accept any sensible outcome.
- test_c05_semicolon_is_not_a_delimiter: I don't mind about delimiters other than comma. Please remove the requirement that a ;-delimited file raises ImportFileError.

Everything else you described is fine. This includes the optional unknown-column warning, the several-errors-per-row leniency, updated for unchanged contacts, and the repository-unchanged check after ImportFileError. Please loosen those three tests.

### [check] agent

I've loosened the three tests. The suite now has 147 tests and all of them still fail, only because the importer doesn't exist yet.

- **Trailing comma** (`test_rows_general.py`, now `test_c22_trailing_empty_cell_is_accepted_or_flagged`): either outcome passes. If the row is accepted, Ann must be created with no errors. If it's flagged, row 2 must be in `errors` and nothing stored.
- **Empty `name` with `first_name`/`last_name` filled in** (`test_header.py`, now `test_c11_empty_name_with_first_and_last_name_is_rejected_or_uses_them`): either outcome passes. The row is either created as "Ann Lee" with no errors, or rejected with a `name` error and nothing stored.
- **Semicolon delimiter**: `test_c05_semicolon_is_not_a_delimiter` is deleted. No other test uses a non-comma delimiter.

**Command and output:**
```
python3 -m pytest tests/acceptance -q
147 failed in 0.32s
```
Grouped by error message (`--tb=line`):
```
113 ModuleNotFoundError: No module named 'contactbook.importer'
 34 ImportError: cannot import name 'ImportFileError' from 'contactbook.errors'
```
The existing suite is unchanged: `24 passed`.

**Decision for you:** some of what you said reaches further than those three tests. Other tests still pin behaviour you said you don't mind about. They follow spec criteria 11, 22 and 23, so I left them alone:
- **More cells than the header (criterion 22):**
  - `test_c22_row_with_more_cells_than_header_is_an_error_on_no_column`
  - row 6 of `test_c21_every_rejected_row_is_reported_with_its_row_number`
  - row 6 of `test_c35_only_phone_failures_produce_warnings`
- **Fewer cells than the header (criterion 23):**
  - `test_c23_missing_trailing_cells_are_treated_as_empty`
  - `test_c23_short_row_for_existing_contact_keeps_phone_and_tags`
  - `test_c23_missing_email_cell_is_an_email_error`
  - `test_c26_...[Ann Lee]`
  - row 11 of `test_c35`
- **Both `name` and `first_name`/`last_name` present (criterion 11):** `test_c11_name_column_wins_over_first_and_last_name` requires `name` to win.

If you don't mind about those either, I can loosen or remove them too. If so, the spec's criteria 11, 22 and 23 should probably be relaxed to match.

### [check] user

Yes, loosen them. I don't mind about rows with more or fewer cells than the header, or about a file with both name and first_name/last_name. No test should require a particular outcome for these cases.

- Rows with extra or missing cells: where a test only needs some row to be an error or a warning (c21, c35, c26), change the row so it has the same number of cells as the header. Remove the tests whose only point is how a short or long row is handled: the c22 more-cells test and the c23 tests.
- name plus first_name/last_name: remove test_c11_name_column_wins_over_first_and_last_name.

Please leave SPEC.md alone for now. The tests are what matter at this stage.

### [check] agent

No test now requires a particular outcome for a row with more or fewer cells than the header, or for a file with both `name` and `first_name`/`last_name`. All 141 acceptance tests still fail, only because the importer doesn't exist yet. I left `SPEC.md` alone.

**Command and output:**
```
python3 -m pytest tests/acceptance -q
141 failed in 0.35s
```
Grouped by error message (`--tb=line`):
```
107 ModuleNotFoundError: No module named 'contactbook.importer'
 34 ImportError: cannot import name 'ImportFileError' from 'contactbook.errors'
```
The existing suite still gives `24 passed`.

**Rows changed to match the header width**
- **c21:** row 6 had an extra cell. It's now a 101-character name and must be an error on column `name`, which the validator rejects.
- **c35:** row 6 is now the same too-long-name error. Row 11 was short; it's now a full row that should be created normally.
- **c26:** the short `Ann Lee` row is now `Ann Lee,,+1 555 123 4567,vip`, an empty email with the other cells filled in.
- **c09, c10, c14:** these expect `ImportFileError` because of a header problem, but their filler row didn't match the header's width. A small `filler_row(header)` helper now builds a row of the right width, so the error can only come from the header.

**Removed**
- `test_c22_row_with_more_cells_than_header_is_an_error_on_no_column`
- The three `test_c23_*` tests.
- `test_c11_name_column_wins_over_first_and_last_name`
- `test_c22_trailing_empty_cell_is_accepted_or_flagged`, the trailing-comma test I loosened last round. It accepted either outcome, but its only point was how a long row is handled, which is your removal rule. Say if you want it back.

**Kept:** `test_c11_empty_name_with_first_and_last_name_is_rejected_or_uses_them`, the test you asked me to loosen last round. It accepts either outcome. If it rejects the row, though, it still expects the error on column `name`. Say if you'd rather drop it.

To find every mismatched row, I temporarily wrapped the import call in a throwaway conftest that recorded each row whose cell count differed from the header, including in tests that expect `ImportFileError`. After the edits it reported only the three deliberately unclosed-quote rows in c17/c18. Those tests are about the unclosed quote, so I kept them. I deleted the probe and its log afterwards. The working tree is back to just the untracked `SPEC.md` and `tests/acceptance/`, and nothing is committed.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

CSV import is built and everything passes: the acceptance tests, the existing suite and 6 new unit tests. I didn't change anything in `tests/acceptance/` and didn't commit.

**Command:** `python3 -m pytest`

```
collected 171 items

tests/acceptance/test_created_updated.py .....                           [  2%]
tests/acceptance/test_header.py ....................................     [ 23%]
tests/acceptance/test_input_encoding.py ...............                  [ 32%]
tests/acceptance/test_interface.py ....                                  [ 35%]
tests/acceptance/test_round_trip.py ...                                  [ 36%]
tests/acceptance/test_rows_email.py ...............                      [ 45%]
tests/acceptance/test_rows_general.py ........                           [ 50%]
tests/acceptance/test_rows_name.py .................                     [ 60%]
tests/acceptance/test_rows_phone.py .............                        [ 67%]
tests/acceptance/test_rows_tags.py ...............                       [ 76%]
tests/acceptance/test_whole_file.py ..........                           [ 82%]
tests/test_export.py ..                                                  [ 83%]
tests/test_importer.py ......                                            [ 87%]
tests/test_models.py ....                                                [ 89%]
tests/test_repository.py ....                                            [ 91%]
tests/test_service.py ...                                                [ 93%]
tests/test_validation.py ...........                                     [100%]

============================= 171 passed in 0.13s ==============================
```

**What changed:**
- **`src/contactbook/importer.py`** (new): `import_contacts`, `ImportReport` and `RowIssue`. The import checks the whole file before it changes anything, so when it raises `ImportFileError` the repository is untouched. It uses its own small CSV parser instead of Python's `csv` module, so it can give rows their physical line numbers and reject a quoted field that is never closed. All values go through the existing validators, so stored values match what `ContactBook.add` would store.
- **`src/contactbook/errors.py`**: added `ImportFileError(ContactError)`, also exported from the package `__init__`.
- **`tests/test_importer.py`** (new): covers rows with too many cells (error with no column) and too few (missing cells treated as empty), plus a few of the choices below.
- **`README.md`**: one layout line for `importer.py`.

**Choices where the spec was open:**
- **Unknown columns** are ignored with no warning, even if one appears twice. Only the known columns are checked for duplicates.
- **Blank lines before the header** are skipped: the header is the first non-blank line, and line numbering still counts the skipped lines.
- **A row that changes nothing** on an existing contact goes in neither `created` nor `updated`. It still counts as the first row for its email, so later rows with the same email are rejected.
- **Text after a closing quote** (e.g. `"Ann" Lee`) is kept as part of the field rather than rejecting the file.

The test run also created `__pycache__/` folders, which show up as untracked because the repo has no `.gitignore`.

### [review1] operator

Review the changes since commit 81be59dc91184ffe10bbd0ce22948949dc428cd2 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found nothing to fix. I checked `src/contactbook/importer.py` and the changes to `errors.py` and `__init__.py` against all 43 acceptance criteria in SPEC.md, and found no gaps that affect correctness. All 171 tests pass, including the acceptance suite.

Areas I checked:
- **Input and encoding (1–6):** bytes and text give the same result. A leading BOM is removed in both cases. Invalid UTF-8 raises `ImportFileError` with the "CSV UTF-8" hint. `\n`, `\r\n` and quoted line breaks are all handled.
- **Row numbering:** a record gets the number of the physical line it starts on, including after multi-line quoted cells and blank lines.
- **Whole-file rejection (16–18):** every file-level check runs before anything is written: decoding, an unclosed quote, the header checks, and the 1000-row limit (blank rows don't count). So the repository is never partly updated.
- **Header (7–15):** the code checks:
  - names match regardless of case and surrounding spaces;
  - the `email` column is required;
  - the name comes from `name`, or from `first_name` plus `last_name`, and `name` wins when both are present;
  - duplicate known columns raise an error;
  - a header-only file returns an empty report.
- **Rows (19–41):**
  - Rows with too many cells are errors; rows with too few are padded with empty cells.
  - Only applied rows count for duplicate emails, so a valid row after a rejected one with the same email still goes in.
  - All errors are collected before deciding, so a rejected row changes nothing in the repository.
  - A bad phone gives a warning only, and only on rows that are otherwise valid.
  - Tags are merged with the stored ones, never removed, and an empty phone cell keeps the stored phone.
  - Stored values go through the same validators as `ContactBook.add`.
- **Round trip (42–43):** importing `export_csv` output reproduces the same contacts. Importing it back into its source repository changes nothing, adds nothing, and reports no creations, errors or warnings.

One spec ambiguity, not counted as a finding: criterion 14 says any column that appears twice should raise an error, but criterion 13 says unknown columns never cause an error. The code only rejects duplicates among the known columns, so a header with two identical unknown columns (for example `notes,notes`) is accepted. That fits criterion 13, and it's the safer choice for files from Excel.

FINDINGS: 0
