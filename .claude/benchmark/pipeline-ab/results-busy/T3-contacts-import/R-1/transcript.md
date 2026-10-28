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

I've read the code (`export.py`, `validation.py`, `repository.py`, `errors.py`). Export writes `name,email,phone,tags` with a header row, tags sorted and joined with `;`, and an empty cell when there's no phone. Contacts are keyed by normalised email.

Here's the first round of questions. Each has my suggested default, so you can just reply "agree" or give the number and your answer.

**Existing contacts and conflicts**

1. **Email already in the book.** I'd overwrite name, phone and tags with what the file says, so re-importing an edited export round-trips. The other option is merging, e.g. adding the file's tags to the existing ones. Which do you want?
2. **Blank phone or tags cell on an existing contact.** This depends on #1. With overwrite, a blank cell clears the field, the same way export writes "no phone" as blank. Should blank clear it, or mean "leave unchanged"?
3. **Row matches the existing contact exactly.** Should it count as `updated`, or be left out of both lists? I'd leave it out, maybe with a warning.
4. **Same email twice in one file** (after normalising, e.g. `Ann@X.com` and `ann@x.com`). Options are: error on the later row and keep the first, last one wins with a warning, or reject the whole file. I'd go with the first.

**Partial failure**

5. **Some rows are bad.** I'd import the valid rows and report the bad ones in `errors`, which is what the report shape suggests. Or should any row error mean nothing is imported?
6. **One bad field in an otherwise fine row** (e.g. an invalid phone). I'd skip the whole row as an error. The alternative is importing it without the bad field and adding a warning.

**File-level vs row-level**

7. **Header.** Should the header row be required? I'd match column names case-insensitively, ignore surrounding spaces, and accept any column order. `name` and `email` would be required, with `ImportFileError` if either is missing. If `phone` or `tags` is missing, should that be a file error, or just treated as blank for every row?
8. **Unknown extra columns** (sales sheets often have "Company" or "Notes"). Should these be ignored with a warning, or rejected?
9. **Empty file, or header only.** Should that raise `ImportFileError` or return an empty report?
10. **Blank lines and rows with the wrong number of cells.** I'd skip fully blank rows silently and treat a row with too many or too few cells as a row error. OK?

**Spreadsheet realities**

11. **Encoding of `bytes`.** I'd accept UTF-8, with or without the BOM Excel adds, and raise `ImportFileError` on anything that won't decode. Do you also need Windows-1252 or UTF-16? Excel's "Unicode text" and older "CSV" saves produce those.
12. **Delimiter.** Excel in many European locales saves CSV with `;`, which clashes with the tag separator. Should I support comma only, or also detect `;`-delimited files?
13. **Row numbering in `RowIssue.row`.** I'd use the spreadsheet row number the user sees: header = row 1, first data row = 2. For `column`, I'd use the column name from the header, or `None` for whole-row issues like duplicates or the wrong number of cells.

**Scope**

14. **Size limit.** Is there a maximum on rows or bytes, beyond which the whole file is rejected?
15. **Integration.** Should this also be exposed through `ContactBook` and the package `__init__`, or only through `importer.import_contacts`? Are a CLI or HTTP endpoint non-goals here, since the README says the HTTP API lives in another package?

### [spec] user

1. Update, but as a merge, not a blind overwrite. Name: the file's value replaces ours. Phone: replaced only when the cell has a value. Tags: the file's tags are added to the existing ones, and an import never removes tags. The email is the identity and it is normalised (trim + lower-case) with the existing helper, so ` ANN@X.COM` is the same person as `ann@x.com`. It is never a second contact, and it goes into `updated`.

2. Blank means leave unchanged. A blank phone cell, or a missing phone column, never wipes a phone we already have. Blank tags add nothing.

3. I don't mind. Either way is fine.

4. Agree with the first row winning. Every later row with that email is an error on that later row and is not applied. It's almost always a copy-paste slip and I want people to see it. Don't reject the whole file.

5. Agree. Import the good rows and report the bad ones in `errors`. A bad row is not applied at all, not even partly to an existing contact. The exceptions are the whole-file problems: a missing required column, an empty file, too many rows and bad encoding. Those reject the whole file with `ImportFileError` and nothing is imported.

6. It depends on the field. An invalid phone must not cost us the contact. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning for that row with column `phone`. An invalid email, name or tag makes the row an error. A name is required on every row, also when it updates an existing contact.

7. Agree with case-insensitive matching, ignoring spaces around names, and any column order. `email` and `name` are required, and a missing one means `ImportFileError`. `phone` and `tags` are optional, so a missing one is just treated as blank. One addition: our address-book export script writes `first_name` and `last_name` columns instead of `name`. Accept that pair as the name column, with the name being first and last joined by one space.

8. Unknown extra columns such as Company or Notes: ignore them. Never an error.

9. A completely empty file raises `ImportFileError`. A file with only the header is fine: nothing happens and the report is empty.

10. Agree on skipping blank rows silently. That covers empty lines and rows where every cell is empty or only spaces, like the `,,,` lines Excel leaves at the bottom. They don't count toward the size limit either. I don't mind how rows with too many or too few cells are handled.

11. Files are UTF-8. Excel's "CSV UTF-8" puts a BOM at the start, and that must just work, both for bytes and for text input that still starts with the BOM character. Bytes that aren't valid UTF-8 (old Excel saves in Windows-1251) raise `ImportFileError` telling the user to re-save as "CSV UTF-8". No UTF-16 or other encodings are needed.

12. Comma only. I don't mind about other delimiters.

13. Agree. `row` is the spreadsheet row number: header = row 1, first contact = row 2, and every line of the file counts, blank lines included. `column` is the lower-case name of the column: `name`, `email`, `phone` or `tags`. A name problem in a `first_name`/`last_name` file is `name` too. For whole-row issues, I don't mind whether you use `None` or the relevant column. A duplicate email can use `email`.

14. Yes. At most 1000 contact rows per file, not counting blank rows. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported, so people split it instead of ending up with a half-loaded file. There's no byte limit.

15. I don't mind. Only `importer.import_contacts` is required, and a CLI or HTTP endpoint is a non-goal. Also, the tags cell holds several tags separated by `;`, as in our export. Normalise each one with the existing tag helper and ignore empty pieces and repeats. An invalid tag makes the row an error with column `tags`.

### [spec] agent

Thanks, that covers most of it. A few edge cases are still open. For each one, here's what I'll write unless you say otherwise:

1. **`name` and `first_name`/`last_name` together.** If a file has both, does `name` win? If only one of `first_name`/`last_name` is present, I'd treat the name column as missing, so `ImportFileError`. If both columns are present but one cell is blank (e.g. no last name), the name is just the non-blank part. If both cells are blank, it's a `name` error.
2. **Duplicate after a failed row.** Say row 3 has `ann@x.com` but an invalid name, so it errors, and row 7 has `ann@x.com` again and is valid. Is row 7 a duplicate error ("an email counts as taken once it appears on any earlier row"), or does it get applied ("only rows that were applied claim the email")? I'd lean towards the first, so the slip stays visible.
3. **Cells with line breaks.** A quoted cell can contain a line break, e.g. a Notes column with two lines. In Excel that's one row, but it spans two lines of the file. Should `row` count the spreadsheet row (the record) or the file line? I'd go with the spreadsheet row, so the number matches what the user sees in Excel.
4. **Same column twice in the header** (e.g. `Email` and `email`). If it's a column we use, I'd raise `ImportFileError`, because the file is ambiguous. If it's a column we ignore, like two `Notes`, it's fine.

I'll decide these myself unless you object:
- An existing contact matched by an applied row always goes into `updated`, even if nothing changed. No warning.
- A row with too few cells has the missing cells treated as blank. Extra cells are ignored. Neither one rejects the file.
- If a row is an error, it may report one issue or several. It doesn't also get a phone warning.
- `data` of any other type than `str`/`bytes` raises `TypeError`, not `ImportFileError`. That follows the rule in `errors.py` that programming errors aren't wrapped.

### [spec] user

1. I don't mind. Those cases are rare, so go with your suggestion.

2. I don't mind. Use your lean.

3. I don't mind. Your choice is fine.

4. I don't mind. Raising `ImportFileError` for a duplicated column we use is fine.

Your other decisions are fine with me, with one exception. The `updated` list: a contact that already exists and is matched by an applied row goes into `updated`. That's fine. For a row with a bad phone, though, still import or update the rest of the row and add the phone warning. That row is not an error.

When SPEC.md is written, go ahead.

### [spec] agent

I've written `SPEC.md`, but I couldn't start the implementation: the permission settings deny edits under `src/`. My edits to `errors.py` and `__init__.py` were rejected and I didn't try another route. I also undid the README line I'd added for `importer.py`. The working tree now differs from `main` only by the new `SPEC.md`.

**What the spec contains:**
- The interface from your request, copied exactly.
- A few definitions so the criteria can be checked: row number, blank row, contact row and applied row.
- 35 numbered acceptance criteria covering encoding and the BOM, header and column matching, the 1000-row limit, which problems reject the whole file, per-field validation, merging into existing contacts, and what goes in the report. The last one is a round trip: importing our own export recreates the same contacts.
- Non-goals: other delimiters and encodings, a byte limit, deleting or clearing anything, dry runs, and a CLI or HTTP endpoint.

**Choices I made where you said you didn't mind:**
- A file with both `name` and `first_name`/`last_name` uses `name`. Having only one of `first_name`/`last_name` (and no `name`) rejects the file.
- An email counts as taken once it appears on any earlier row, even if that row failed.
- Row numbers count spreadsheet rows, so a cell with a line break inside doesn't shift them.
- Rows that match an existing contact always go into `updated`, even when nothing changed.
- Rows with too few cells get the missing ones treated as blank, and extra cells are ignored.

**About your last point on bad phones:** the spec already handles it as you described (criterion 20). A row whose only problem is the phone is applied and gets a `phone` warning. What I meant earlier was narrower: a row that is already an error, because of a bad name for example, doesn't also get a phone warning (criterion 23).

To have me write `importer.py`, the `ImportFileError` class and tests, allow edits under `src/` and `tests/`, or tell me where else the code should go.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote 133 acceptance tests covering all 35 criteria in SPEC.md, plus one test for the interface section. They all fail for now, as intended: 132 because `contactbook.importer` doesn't exist yet, and one because `ImportFileError` doesn't exist yet. I didn't implement anything.

**Command:**
```
python3 -m pytest tests/acceptance -q --tb=line
```

**Output (summarised):**
```
133 failed in 0.42s

132 × ModuleNotFoundError: No module named 'contactbook.importer'
  1 × AssertionError: issubclass(<class 'conftest.ImportFileErrorMissing'>, ContactError) is False
```
The existing suite (`python3 -m pytest tests --ignore=tests/acceptance -q`) still passes: 24 passed.

**Files in `tests/acceptance/`:**

| File | Criteria |
|---|---|
| `test_acc_input.py` | 1–5: input types, UTF-8, BOM, non-UTF-8 files, CSV quoting |
| `test_acc_header.py` | 6–14: column matching, required columns, name sources, duplicate columns, empty files, short and long rows |
| `test_acc_file_errors.py` | 15–16: the 1000-row limit, and the repository staying unchanged after any `ImportFileError` |
| `test_acc_rows.py` | 17–24: checks on each field, duplicate emails within a file, error rows |
| `test_acc_create_update.py` | 25–29: creating, updating and merging contacts; values stored the same way as `Contact.create` |
| `test_acc_report.py` | interface section and 30–35: report order, row numbers, column names, messages, round trip through `export_csv` |

The tests only use what the spec names: `import_contacts`, `ImportReport`, `RowIssue`, `ImportFileError`, `ContactError`, the repository's public methods, `Contact.create` and `export_csv`. Expected values are written out directly from the spec's rules (for example `" ANN@Example.COM "` → `"ann@example.com"`, and row numbers counted from the header as row 1). Where the spec says "normalised like `Contact.create`", the test compares against `Contact.create`.

`conftest.py` loads the importer only when a test runs, not at import time. Without that, each test would show as a setup error, or the whole directory would fail to load, instead of failing on its own.

**Choices where the spec wasn't explicit:**
- **CRLF line endings:** I treated them as part of "standard CSV" (criterion 5), since that's what Excel writes.
- **Semicolon-delimited files:** the test expects `ImportFileError`, because the header then reads as one column `name;email` and there's no `email` column (criterion 7).
- **"Short" messages (criterion 33):** I took this to mean a single line of at most 200 characters.
- **`bytearray` input:** not tested, since it's unclear whether it counts as an "other type" under criterion 1.
- **Whitespace-only tag pieces** like `vip; ;lead`: not tested, since it's unclear whether they count as "empty pieces".

**One risk:** because there's no implementation yet, none of the tests' own assertions have actually run. A mistake in a test, such as a wrong row number, will only show up once the importer exists.

Nothing is committed.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

CSV import is built as SPEC.md describes, and all 157 tests pass: 133 acceptance tests plus the 24 existing ones. Before the change, those 133 acceptance tests failed because the importer didn't exist.

**Command** (from the repo root): `python3 -m pytest`

```
tests/acceptance/test_acc_create_update.py ..............                [  8%]
tests/acceptance/test_acc_file_errors.py ...........                     [ 15%]
tests/acceptance/test_acc_header.py ....................................  [ 38%]
....                                                                     [ 41%]
tests/acceptance/test_acc_input.py .................                     [ 52%]
tests/acceptance/test_acc_report.py ................                     [ 62%]
tests/acceptance/test_acc_rows.py ...................................    [ 84%]
tests/test_export.py ..                                                  [ 85%]
tests/test_models.py ....                                                [ 88%]
tests/test_repository.py ....                                            [ 91%]
tests/test_service.py ...                                                [ 92%]
tests/test_validation.py ...........                                     [100%]
============================= 157 passed in 0.07s ==============================
```

**What changed**
- **`src/contactbook/importer.py`** (new): contains `import_contacts`, `ImportReport` and `RowIssue`. It reads and checks the whole file before storing anything: encoding, header, empty file and the 1000-row limit. So when an `ImportFileError` is raised, the repository is untouched. After that, each row is checked on its own with the existing helpers. Bad rows are reported and skipped. Good rows create a new contact or merge into the existing one: the name is replaced, the phone only if valid, and tags are only ever added.
- **`src/contactbook/errors.py`**: added `ImportFileError(ContactError)`.
- **`src/contactbook/__init__.py`**: also exports `ImportFileError`, like the other errors. The spec made this optional.
- **`README.md`**: one line added to the file layout for `importer.py`.

**Choices the spec left open**
- **Messages:** each one starts with the column name, matching how `ValidationError` formats itself, e.g. `email: already used on row 2`. A warning for a bad phone ends with `; phone not imported`. Messages are cut to 120 characters so a huge cell can't produce a huge message.
- **One row, several problems:** a row with more than one problem reports all of them (name, email and tags), not just the first.
- **Parser failures:** if Python's CSV reader fails on a file, that becomes an `ImportFileError`.

Nothing is committed. `tests/acceptance/` and `SPEC.md` were not modified.

### [review1] operator

Review the changes since commit feb5e026d9bb2405fba57a1ed22a44de3fdb70a4 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found one gap against SPEC.md, and it's a judgement call. Everything else in the spec is implemented correctly. All 157 tests pass, and I ran extra checks on the edge cases (listed at the end).

**1. Content past the last header column turns a blank row into an error row.** `src/contactbook/importer.py:84`
- `contact_rows` decides whether a row is blank by checking every cell in it, including cells to the right of the header's last column.
- Criterion 14 says those cells are ignored. With them ignored, a row like `,,,,x` under a 4-column header is a blank row under the spec's definition.
- What the code does instead: it reports that row as an error row (two errors at row 3: `email: is required` and `name: is required`). The row also counts toward the 1000-row limit in criterion 15, so a file could be rejected because of stray cells off to the right.
- Fix: check only `cells[:len(header)]` when deciding whether a row is blank.
- If you read "Blank row: every cell is empty" as meaning every cell in the record, the current behaviour is defensible. I count it as a gap because criterion 14 explicitly says to ignore those cells.

**Also checked and correct:**
- Input and encoding:
  - Only `str` and `bytes` are accepted.
  - A leading BOM is handled for both `str` and `bytes`.
  - Text that isn't UTF-8 gets the "CSV UTF-8" message.
  - An empty, BOM-only or whitespace-only file is rejected.
- Rows:
  - Row numbers stay correct with blank rows and with line breaks inside quoted cells.
  - Header matching ignores case and surrounding whitespace.
  - Repeated used columns are rejected, while repeated unknown columns are allowed.
  - `first_name`/`last_name` are joined correctly, and short rows are filled with blanks.
  - Tags are split, normalised and de-duplicated.
  - An invalid phone gives a warning only on rows that are applied.
  - A repeated email is caught even when the earlier row was an error row.
- Results:
  - Every whole-file error is raised before the repository changes.
  - Updates merge (name replaced, tags added, phone kept unless valid), and the round trip from `export_csv` works.

FINDINGS: 1

### [fix1] operator

A fresh reviewer who has not seen your reasoning reported:

I found one gap against SPEC.md, and it's a judgement call. Everything else in the spec is implemented correctly. All 157 tests pass, and I ran extra checks on the edge cases (listed at the end).

**1. Content past the last header column turns a blank row into an error row.** `src/contactbook/importer.py:84`
- `contact_rows` decides whether a row is blank by checking every cell in it, including cells to the right of the header's last column.
- Criterion 14 says those cells are ignored. With them ignored, a row like `,,,,x` under a 4-column header is a blank row under the spec's definition.
- What the code does instead: it reports that row as an error row (two errors at row 3: `email: is required` and `name: is required`). The row also counts toward the 1000-row limit in criterion 15, so a file could be rejected because of stray cells off to the right.
- Fix: check only `cells[:len(header)]` when deciding whether a row is blank.
- If you read "Blank row: every cell is empty" as meaning every cell in the record, the current behaviour is defensible. I count it as a gap because criterion 14 explicitly says to ignore those cells.

**Also checked and correct:**
- Input and encoding:
  - Only `str` and `bytes` are accepted.
  - A leading BOM is handled for both `str` and `bytes`.
  - Text that isn't UTF-8 gets the "CSV UTF-8" message.
  - An empty, BOM-only or whitespace-only file is rejected.
- Rows:
  - Row numbers stay correct with blank rows and with line breaks inside quoted cells.
  - Header matching ignores case and surrounding whitespace.
  - Repeated used columns are rejected, while repeated unknown columns are allowed.
  - `first_name`/`last_name` are joined correctly, and short rows are filled with blanks.
  - Tags are split, normalised and de-duplicated.
  - An invalid phone gives a warning only on rows that are applied.
  - A repeated email is caught even when the earlier row was an error row.
- Results:
  - Every whole-file error is raised before the repository changes.
  - Updates merge (name replaced, tags added, phone kept unless valid), and the round trip from `export_csv` works.

FINDINGS: 1

Reproduce each finding before changing anything; fix the real ones and reject the rest in one sentence each. Report the command and its output.

### [fix1] agent

The reviewer's finding was real and is now fixed; all 157 tests still pass.

**The problem:** a row under a 4-column header like `,,,,x` was reported as an error row, and the bug showed up exactly as described. The cause was that the code decided whether a row is blank by looking at all its cells, including ones past the header. Criterion 14 says those cells are ignored, so ignoring them when deciding blankness too is the consistent reading. Otherwise one stray cell could make a row fail or push a file over the 1000-row limit.

**The fix:** in `src/contactbook/importer.py`, the blank-row check now looks only at the cells under the header columns (`cells[:width]`, where `width` is the header's length). Nothing else changed.

**Checks after the fix:**
- The reproduction row is now treated as blank:
  ```
  ImportReport(created=['ann@example.com'], updated=[], errors=[], warnings=[])
  ```
- A file with 1000 valid rows, each followed by a `,,,,junk` row, imports all 1000 instead of being rejected for having too many rows.
- Full suite, `python3 -m pytest -q`:
  ```
  ........................................................................ [ 91%]
  .............                                                            [100%]
  157 passed in 0.06s
  ```

No findings were rejected. Nothing is committed.

### [review2] operator

Review the changes since commit feb5e026d9bb2405fba57a1ed22a44de3fdb70a4 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review2] agent

I found one correctness gap in the changes since `feb5e02`. The other 34 criteria in SPEC.md hold up when I trace them through the code, and the full test suite passes (157 tests).

**`src/contactbook/importer.py:121-123`: one oversized cell rejects the whole file**

The importer reads the file with Python's `csv.reader`, which by default refuses any single cell longer than 131,072 characters. The importer turns that refusal into an `ImportFileError`, so the whole file fails.

- **What I ran:** a file with header `name,email,notes` and a row `Ann,a@x.com,<200,000-character note>`.
- **What happened:** it raised `ImportFileError: the file is not valid CSV: field larger than field limit (131072)`, and no contacts were imported.
- **What the spec says:**
  - Criterion 10 says unknown columns like `Notes` never cause an error, so that row should import.
  - The Non-goals section says there is no size limit other than the 1,000-row cap.
  - If the oversized cell is in a column the importer uses, such as `name`, criteria 18 and 24 say it should be an error on that row only, with the rest of the file still imported.
- **Fix:** raise the parser's per-cell limit while parsing, for example `csv.field_size_limit(sys.maxsize)` restored afterwards, or a limit sized to the input length. A row whose name is too long will then get the normal per-row "name is longer than 100 characters" error.

FINDINGS: 1

### [fix2] operator

A fresh reviewer who has not seen your reasoning reported:

I found one correctness gap in the changes since `feb5e02`. The other 34 criteria in SPEC.md hold up when I trace them through the code, and the full test suite passes (157 tests).

**`src/contactbook/importer.py:121-123`: one oversized cell rejects the whole file**

The importer reads the file with Python's `csv.reader`, which by default refuses any single cell longer than 131,072 characters. The importer turns that refusal into an `ImportFileError`, so the whole file fails.

- **What I ran:** a file with header `name,email,notes` and a row `Ann,a@x.com,<200,000-character note>`.
- **What happened:** it raised `ImportFileError: the file is not valid CSV: field larger than field limit (131072)`, and no contacts were imported.
- **What the spec says:**
  - Criterion 10 says unknown columns like `Notes` never cause an error, so that row should import.
  - The Non-goals section says there is no size limit other than the 1,000-row cap.
  - If the oversized cell is in a column the importer uses, such as `name`, criteria 18 and 24 say it should be an error on that row only, with the rest of the file still imported.
- **Fix:** raise the parser's per-cell limit while parsing, for example `csv.field_size_limit(sys.maxsize)` restored afterwards, or a limit sized to the input length. A row whose name is too long will then get the normal per-row "name is longer than 100 characters" error.

FINDINGS: 1

Reproduce each finding before changing anything; fix the real ones and reject the rest in one sentence each. Report the command and its output.

### [fix2] agent

The reviewer's finding was real and is now fixed; all 157 tests still pass.

**The problem:** a file with a 200,000-character `notes` cell was rejected as a whole, exactly as reported:
```
ImportFileError the file is not valid CSV: field larger than field limit (131072)
```
Python's `csv.reader` refuses any cell over 131,072 characters by default. That broke criterion 10 (unknown columns never cause errors) and the spec's "no byte-size limit" non-goal.

**The fix:** in `_parse` in `src/contactbook/importer.py`, the parser's per-cell limit is raised to the length of the input while it parses, since no cell can be longer than the file. The previous limit is put back in a `finally` block, so other code that uses `csv` isn't affected. This setting is shared across the whole process, so concurrent imports could interfere with each other; the spec lists thread safety as a non-goal.

**Checks after the fix:**
- The oversized `notes` cell is ignored and the contact imports:
  `ImportReport(created=['a@x.com'], updated=[], errors=[], warnings=[])`
- An oversized `name` cell is now an error on that row only, and the next row still imports:
  `errors=[RowIssue(row=2, column='name', message='name: is longer than 100 characters')]`, `created=['b@x.com']`
- The limit is back at its default afterwards: `limit restored: 131072`
- Full suite, `python3 -m pytest -q`:
  ```
  ........................................................................ [ 91%]
  .............                                                            [100%]
  157 passed in 0.06s
  ```

No findings were rejected. Nothing is committed.

### [review3] operator

Review the changes since commit feb5e026d9bb2405fba57a1ed22a44de3fdb70a4 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review3] agent

I found no correctness gaps against SPEC.md in the changes since `feb5e02`.

I checked the 35 acceptance criteria against `src/contactbook/importer.py`, the `ImportFileError` addition in `errors.py` and the `__init__.py` export. The existing tests pass (157), and I also ran some edge cases by hand:

- **Row numbers:** they come out right with blank lines, quoted cells containing line breaks, and old Mac `\r` line endings.
- **BOM:** it's removed from the first column name for both bytes and str input.
- **Header matching:** column names are matched ignoring case and surrounding spaces, and a repeated used column raises `ImportFileError`. Repeated `first_name`/`last_name` columns are only allowed when a `name` column is present.
- **Duplicate emails:** a repeat is caught even when the earlier row was itself an error.
- **Error rows:** they report no warnings and change nothing in the repository.
- **Whole-file errors:** every check that raises `ImportFileError` runs before anything is written, including the 1000-row limit.
- **Updates:** they merge without loss. The name is replaced, tags are only added, and the phone changes only when the cell holds a valid phone.
- **Round trip:** importing `export_csv` output recreates equal contacts in an empty repository, and leaves the original repository unchanged with every email in `updated`.

One judgement call, which I didn't count as a gap: `importer.py:84` decides whether a row is blank by looking only at cells within the header's width. So in a two-column file, a row like ` , ,Z` is treated as blank and skipped. SPEC.md defines a blank row as one where "every cell is empty", which would make it a contact row and an error. But criterion 14 says cells beyond the header are ignored, which supports what the code does. If the definition is meant to win, check every cell instead of `cells[:width]`.

FINDINGS: 0
