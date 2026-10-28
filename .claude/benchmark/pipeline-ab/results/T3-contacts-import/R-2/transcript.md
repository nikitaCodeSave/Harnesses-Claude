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

I've read the code: `export_csv` writes a header `name,email,phone,tags`, tags joined with `;`, and an empty phone cell when there's no phone. The repository is keyed by email, ignoring case, and `Contact.create` does all the validation. Here's the first round of questions. Each one has my suggested default, so you can just answer "yes" or correct the ones you disagree with.

**1. Bad rows: all-or-nothing, or skip and continue?**
If row 37 has an invalid email, do the other valid rows still get imported (row 37 goes in `errors`)? Or does any row error mean nothing is written to the repo?
*Suggested:* skip and continue. Valid rows are imported and bad rows are reported. `ImportFileError` is only for problems with the whole file.

**2. What does "update" do to an existing contact?**
Suppose `ann@x.com` already exists and the file has a row for her:
- (a) **Name:** overwrite with the file's value?
- (b) **Phone:** if the file's phone cell is empty, does that clear her phone or keep the existing one?
- (c) **Tags:** replace her tags with the file's tags, or merge them? And does an empty tags cell clear her tags?

*Suggested:* the file is the source of truth. The row fully replaces the contact, so an empty phone clears it and the tags are replaced. That makes export → edit → import round-trip cleanly. The downside: a sales sheet that has no phone numbers would wipe existing phones. If that's a real risk, "blank means keep" is the alternative.

**3. Row identical to what's stored:** if a row matches the existing contact exactly, does it count in `updated` or in neither list?
*Suggested:* neither. `updated` only lists contacts that actually changed.

**4. Same email twice in one file** (e.g. `Ann@x.com` on row 5 and `ann@x.com` on row 90):
*Suggested:* the first occurrence is imported and later duplicates are reported as errors. Alternatives: last one wins, with a warning; or reject every row with that email.

**5. Row numbers in `RowIssue.row`:** should they match what sales sees in their spreadsheet, so the header is row 1 and the first contact is row 2?
*Suggested:* yes, spreadsheet line numbers. (If a quoted cell spans several lines, the row number is where the record starts.) Which row number goes with issues about the header itself?

**6. Encoding and Excel quirks.** Spreadsheets saved by Excel often have a UTF-8 BOM, and older ones come out as Windows-1252. In some European locales Excel also uses `;` as the delimiter, which is the same character as our tag separator.
- *Suggested:* accept UTF-8 with or without a BOM. If the bytes aren't valid UTF-8, raise `ImportFileError` rather than guessing. Comma delimiter only. A semicolon-delimited file would then fail with an `ImportFileError` saying the expected columns weren't found.
- Do you need Windows-1252 or `;`-delimited files to work?

Once you've answered these, the next round covers header and column rules, warnings, empty or oversized files, and per-field errors.

### [spec] user

1. Yes, skip and continue. Good rows go in, bad rows are reported in errors and not applied at all. ImportFileError is only for whole-file problems.

2. Don't agree with your default. The file is not the full source of truth. (a) Name: the file's value replaces ours. (b) Phone: replace only when the cell has a value. An empty cell, or no phone column at all, must never wipe an existing phone. (c) Tags: merge. The file's tags are added to the existing ones, and an import never removes tags, so an empty tags cell changes nothing.

3. I don't mind, either is fine.

4. Yes, first occurrence wins. Every later row with that email is an error on that later row and is not applied.

5. Yes, spreadsheet row numbers: header is row 1, first contact is row 2, and every line of the file counts, blank lines included. For the quoted multi-line case, I don't mind. I don't have a need for issues about the header itself to carry a row number. Missing columns just reject the whole file with ImportFileError.

6. Accept UTF-8 with or without BOM. That must work for bytes, and also for text input that still starts with the BOM character. Invalid UTF-8 means ImportFileError telling them to re-save as "CSV UTF-8". No Windows-1252 guessing. Comma only, I don't need ;-delimited files.

### [spec] agent

Got it. Round 2 covers columns, the edge cases your answers opened up, and what counts as a warning.

**7. Required columns and header matching.** From your answer, a file with no `phone` column is valid.
- *Suggested:* `name` and `email` are required columns, and `phone` and `tags` are optional. If a required column is missing, raise `ImportFileError` naming it.
- Header matching ignores case and surrounding whitespace (`Email ` matches `email`), and column order doesn't matter.
- If the same column appears twice in the header, raise `ImportFileError`.

Agree?

**8. Blank name on an update row.** `ann@x.com` exists, and the row has her email but an empty name cell. Since name "replaces ours":
- (a) is that row an error, or
- (b) does a blank name mean "keep the existing name", the same as phone?

*Suggested:* (a) error. A blank name is always an error, which matches how new contacts behave. (b) is just as easy if you'd rather be lenient.

**9. What goes in `warnings` (things noted, but the row still applies)?** Candidates:
- (a) Unknown extra columns, e.g. `company`, are ignored with a warning. `RowIssue.row` is an `int`, so a header-level warning needs some value. Is `row=1` fine?
- (b) Blank lines are skipped. Silently, or with a warning?
- (c) A row with more cells than the header: warn and ignore the extras, or treat it as a row error?
- (d) A row with fewer cells than the header: treat the missing cells as empty?

*Suggested:* (a) warning with `row=1`. (b) silent. (c) warning, extras ignored. (d) missing cells are empty, so the normal rules apply (a missing email becomes an email error).

**10. Errors within a row.** If a row has a bad email and a bad phone, do you get one `RowIssue` per bad field, or only the first? And should `column` be the canonical name (`email`) or the header text exactly as written in the file?
*Suggested:* one issue per bad field, with the canonical column name. `column=None` only for problems that aren't tied to a single field.

**11. Tags cell parsing.** Our export writes `key-account;vip`.
*Suggested:* split on `;`, trim each piece, and ignore empty pieces (`vip;;` is just `vip`). Each tag goes through the normal tag rules, so `Key Account` becomes `key-account`. One invalid tag makes the whole row an error.

**12. Repo state when `ImportFileError` is raised.** Some whole-file problems, such as an unterminated quote near the end, only surface partway through parsing.
*Suggested:* if `ImportFileError` is raised, the repository is left completely unchanged. Either the import happens (with its per-row errors) or nothing changes.

**13. Empty and size-limited files.**
- (a) Header only, no data rows: an empty report, or `ImportFileError`?
- (b) A completely empty file (or only whitespace): *suggested* `ImportFileError` ("no header").
- (c) Do you want a maximum row count or file size?

*Suggested:* (a) empty report. (c) no limit, since it's an in-memory repo and in scope for later.

### [spec] user

7. Mostly agree. `name` and `email` are required, and `phone` and `tags` are optional. Matching ignores case and spaces around the name, and column order is free. One addition: the pair `first_name` and `last_name` counts as the name column. Our address-book export script writes those instead of `name`. The contact's name is the first and last name joined with one space. If neither `name` nor that pair is present, reject the file with `ImportFileError`. Duplicate columns in the header: I don't mind, do what you think is sensible.

8. (a) Error. Name is required on every row, including rows that update an existing contact.

9. (a) Ignore extra columns. A warning or silence is fine, just never an error. `row=1` is fine for a warning. (b) Silent. That also covers rows where every cell is empty or only spaces, like Excel's `,,,` lines. (c) and (d) I don't mind, use your suggestions. One condition: blank lines still count in the row numbering.

10. I don't mind whether a row with several problems gives one entry or several. `column` must be the lower-case canonical name: `name`, `email`, `phone` or `tags`. A name problem in a `first_name`/`last_name` file is also `name`. One rule on phone: a phone that fails validation is not a row error. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning with column `phone`.

11. Agree. Split on `;`, ignore empty pieces and repeats, and normalise each tag with the existing tag helper. An invalid tag makes the row an error with column `tags`.

12. Yes, agreed. For whole-file problems, nothing is imported.

13. (a) Header only is fine. Nothing happens and the report is empty. (b) A completely empty file gets `ImportFileError`. (c) I do want a limit: at most 1000 contact rows per file, and blank rows don't count. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported. People should split it rather than end up with a half-loaded file.

### [spec] agent

Nearly done. Four small questions came out of your last answers. Each has a proposed answer, so a simple "ok" is enough.

**14. Both `name` and `first_name`/`last_name` in the header.**
*Proposed:* `name` wins, and `first_name`/`last_name` are ignored like any extra column. If only one of the pair is present (say `first_name` with no `name` column), there's no name column, so the file gets `ImportFileError`.

**15. Only one half of the name filled in on a row**, e.g. `first_name` is blank and `last_name` is `Lee`.
*Proposed:* join the non-blank parts, so the name is `Lee`. If both are blank, the row gets a `name` error. The result then goes through the usual name rules (trimmed, inner spaces collapsed).

**16. Duplicate email when the first occurrence was itself an error.** Row 5 has `ann@x.com` with a blank name (error), and row 9 has `ann@x.com` and is valid.
- (a) Row 9 is still a duplicate error, because the first *occurrence* wins whether or not it was valid, or
- (b) row 9 is imported, because only rows that were *applied* block later ones.

*Proposed:* (a). It's predictable, and fixing row 5 then won't silently change what happens to row 9. Matching uses the normalised email.

**17. What counts toward the 1000-row limit.**
*Proposed:* every non-blank row after the header counts, including rows that turn out to be errors or duplicates. Exactly 1000 is allowed and 1001 is rejected.

For the two points you left to me, unless you object:
- **Duplicate header columns:** `ImportFileError`. This compares header names after ignoring case and spaces, so `Email` and `email ` count as the same.
- **Unchanged rows:** a row that leaves an existing contact exactly as it was goes in neither `created` nor `updated`.

### [spec] user

14, 15 and 16: I don't mind, use your proposals. 16 is about an edge case I haven't decided, so (a) is fine.

17. Agreed. Every non-blank row counts, including error rows and duplicates. Exactly 1000 is allowed and 1001 is rejected.

Duplicate header columns: `ImportFileError` is fine.

Unchanged rows: I don't mind whether they're listed in `updated`, so your choice is fine.

### [spec] agent

I've written the spec to `SPEC.md` (not committed). It has the interface copied word for word, 33 acceptance criteria you can check, and a list of non-goals.

Where you said "I don't mind", I wrote down my proposed defaults:
- An unchanged row goes in neither `created` nor `updated`.
- Unknown columns may produce a warning with `row=1`.
- A row with too many cells gets a warning and the extra cells are ignored. A row with too few cells treats the missing ones as empty.
- A row with several problems can produce one error entry or several.

A few things I decided myself that you didn't explicitly confirm:
- **Duplicate-column rule:** this applies only to the columns we recognise: `name`, `email`, `phone`, `tags`, `first_name`, `last_name`. Excel often adds empty header cells at the end, and rejecting those as duplicates would turn away harmless files.
- **Broken CSV structure** (for example, a quote that's never closed) rejects the whole file with `ImportFileError`.
- **Non-`str`/`bytes` input** raises `TypeError` rather than `ImportFileError`. That follows the rule in `errors.py` that programming errors aren't wrapped.
- **`\r\n` line endings** must work, because Excel writes them.
- **Round trip:** exporting with `export_csv` and importing the result into an empty repo recreates the same contacts. Re-importing an export into the repo it came from changes nothing and reports nothing.

Tell me if you'd like any of these changed.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote 153 acceptance tests covering all 33 criteria in `tests/acceptance/`. They all fail, and every failure is because the feature doesn't exist yet. I didn't change anything under `src/`.

## Command and output

```
$ python3 -m pytest tests/acceptance -q -p no:cacheprovider
...
FAILED tests/acceptance/test_import_rows.py::test_error_row_does_not_change_an_existing_contact
FAILED tests/acceptance/test_import_rows.py::test_row_with_several_problems_is_reported_on_its_row
FAILED tests/acceptance/test_import_rows.py::test_valid_rows_around_error_rows_are_all_applied
153 failed in 0.49s
```

Counting the error lines in that output gives two causes:
```
    116 E   ModuleNotFoundError: No module named 'contactbook.importer'
     37 E   AttributeError: module 'contactbook.errors' has no attribute 'ImportFileError'
```

The full suite (`python3 -m pytest -q`) gives `153 failed, 24 passed`, so the existing tests still pass.

## Layout (one file per spec section)

| File | Criteria |
|---|---|
| `test_import_input.py` | 1–6: UTF-8 decoding and BOM handling, the "CSV UTF-8" message, `\n`/`\r\n` line endings, comma-only delimiter, `TypeError` for other input types |
| `test_import_header.py` | 7–11: header matching, the required name source, duplicate columns, unrecognised columns |
| `test_import_file_rejection.py` | 12–15: whole-file errors, the 1000/1001 row limit, repository unchanged after a late failure, header-only files |
| `test_import_rows.py` | 16–23: row numbering (blank lines and multi-line cells), short and long rows, email/name/tags/phone rules, isolating bad rows |
| `test_import_create_update.py` | 24–28: matching existing contacts, create vs. update, never removing data, duplicate emails within a file, stored values normalised |
| `test_import_report.py` | Interface shapes and 29–31: file order, row order, columns limited to the four canonical names |
| `test_import_round_trip.py` | 32–33: `export_csv` → import, and re-importing a repository's own export |

## Choices worth knowing about

- **Interface only.** The tests use only `import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError`, plus the existing `Contact`, `InMemoryContactRepository` and `export_csv`. Expected stored values are built with `Contact.create`, which criterion 28 says the stored values must match.
- **Lazy lookups.** `conftest.py` imports the importer and `ImportFileError` only when a test runs. Without that, a missing module would stop collection for each whole file, or show up as setup errors instead of individual test failures.
- **Things the spec leaves open are not tested:**
  - whether a row with several problems produces one error or several;
  - whether unrecognised columns produce a warning (if one does, it must be `row=1, column=None`);
  - the exact message wording. The tests only check that messages contain "CSV UTF-8" (criterion 3), name the missing column (criterion 8), and are non-empty.
- **Two tests take the spec literally, so check them before implementing:**
  - `bytearray` input must raise `TypeError`, because the spec says "anything other than `str` or `bytes`".
  - An update where only the phone is invalid leaves the contact identical. That email then appears in neither `created` nor `updated`, and the row still gets a phone warning.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

CSV import is built, and both the acceptance tests and the existing tests pass. I didn't modify anything under `tests/acceptance/`.

**Command:** `python3 -m pytest` (from the repo root)

```
tests/acceptance/test_import_file_rejection.py ......................... [ 28%]
tests/acceptance/test_import_header.py ..........................        [ 42%]
tests/acceptance/test_import_input.py ....................               [ 54%]
tests/acceptance/test_import_report.py ..........                        [ 59%]
tests/acceptance/test_import_round_trip.py ....                          [ 62%]
tests/acceptance/test_import_rows.py ................................... [ 81%]
........                                                                 [ 86%]
tests/test_export.py ..                                                  [ 87%]
tests/test_models.py ....                                                [ 89%]
tests/test_repository.py ....                                            [ 92%]
tests/test_service.py ...                                                [ 93%]
tests/test_validation.py ...........                                     [100%]
============================= 177 passed in 0.12s ==============================
```
(The first few lines of output were cut off; the totals line covers the whole run.)

**What changed**
- **`src/contactbook/importer.py`** (new): `import_contacts`, `ImportReport` and `RowIssue`. It reads and checks the whole file before changing anything, so when it raises `ImportFileError` (bad encoding, broken CSV, header problems, more than 1000 rows) the contact book is left exactly as it was. Once the file passes, each row is checked on its own with the existing rules in `validation.py`.
- **`src/contactbook/errors.py`**: added `ImportFileError(ContactError)`. It is also exported from the package's `__init__.py`.
- **`README.md`**: added `importer.py` to the file layout.

**Choices the spec left open**
- **Strict CSV parsing:** a malformed quote, such as `"Ann" Lee,…`, rejects the whole file as unparseable rather than being guessed at.
- **Extra cells:** a row with more cells than the header gets a warning even if the extra cells are empty, so a stray trailing comma triggers one. This follows the spec's wording.
- **Phone warnings:** an invalid phone is only reported on rows that are actually imported. Rows already rejected for another reason don't also get a phone warning.
- **Unrecognised columns:** each named one produces one warning on row 1. Empty header cells are ignored without a warning.
- **Several problems in one row:** the row gets one error per problem field (name, email, tags).

Nothing is committed yet.

### [review1] operator

Review the changes since commit 28ef20afc43e715ce6c1d20ca8a3510dabf22442 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

The implementation meets almost all of SPEC.md. All 177 tests pass, including the acceptance suite. I also ran the edge cases by hand and they behave as the spec says:
- **Row numbering:** blank lines and quoted cells that span several lines are numbered correctly, with `\n` or `\r\n` line endings.
- **Byte-order mark:** a leading BOM is ignored for both bytes and text input.
- **Rejected files:** a quote that is never closed or a stray character after a closing quote raises `ImportFileError`, as does a duplicated `first_name` column even when `name` is present.
- **First/last-name files:** a row with only `last_name` gives the name "Lee"; a row with both blank is a name error.
- **Bad phone:** the row is still imported without the phone, plus a phone warning.
- **Duplicate emails:** the first row wins, even when that row was itself an error.
- **Repository left unchanged:** every check that can reject the whole file runs before the first row is applied.

One gap:

1. **`src/contactbook/importer.py:156`: a header-only file with an unrecognised column doesn't return an empty report.** For example, `"name,email,company\n"` returns `warnings=[RowIssue(row=1, column=None, message="column 'company' is not recognised and was ignored")]`. Criterion 15 says a file with a valid header and no data rows "returns an empty report". Criterion 11 only says an unrecognised column *may* produce a warning, so the mandatory rule should win. A caller or test checking `report == ImportReport()` for a header-only file will fail. The fix is to add the row-1 header warnings only when the file has at least one data row (`rows` is non-empty). This is a judgement call on two clauses that pull against each other; if you read "empty report" as meaning only no created, updated or errors, there is nothing to fix.

FINDINGS: 1

### [fix1] operator

A fresh reviewer who has not seen your reasoning reported:

The implementation meets almost all of SPEC.md. All 177 tests pass, including the acceptance suite. I also ran the edge cases by hand and they behave as the spec says:
- **Row numbering:** blank lines and quoted cells that span several lines are numbered correctly, with `\n` or `\r\n` line endings.
- **Byte-order mark:** a leading BOM is ignored for both bytes and text input.
- **Rejected files:** a quote that is never closed or a stray character after a closing quote raises `ImportFileError`, as does a duplicated `first_name` column even when `name` is present.
- **First/last-name files:** a row with only `last_name` gives the name "Lee"; a row with both blank is a name error.
- **Bad phone:** the row is still imported without the phone, plus a phone warning.
- **Duplicate emails:** the first row wins, even when that row was itself an error.
- **Repository left unchanged:** every check that can reject the whole file runs before the first row is applied.

One gap:

1. **`src/contactbook/importer.py:156`: a header-only file with an unrecognised column doesn't return an empty report.** For example, `"name,email,company\n"` returns `warnings=[RowIssue(row=1, column=None, message="column 'company' is not recognised and was ignored")]`. Criterion 15 says a file with a valid header and no data rows "returns an empty report". Criterion 11 only says an unrecognised column *may* produce a warning, so the mandatory rule should win. A caller or test checking `report == ImportReport()` for a header-only file will fail. The fix is to add the row-1 header warnings only when the file has at least one data row (`rows` is non-empty). This is a judgement call on two clauses that pull against each other; if you read "empty report" as meaning only no created, updated or errors, there is nothing to fix.

FINDINGS: 1

Reproduce each finding before changing anything; fix the real ones and reject the rest in one sentence each. Report the command and its output.

### [fix1] agent

The reviewer's one finding was real, and it's fixed.

**Reproduced before the change:** `import_contacts(repo, "name,email,company\n")` returned a `company` warning on row 1, so `report == ImportReport()` came out `False`. Criterion 15 says a header-only file *must* return an empty report, and criterion 11 only says an unrecognised column *may* produce a warning, so criterion 15 wins.

**Fix** (`src/contactbook/importer.py`, in `import_contacts`): the header is still checked first, so a bad header still rejects the file. If the file then has no data rows, an empty `ImportReport()` is returned. When there are data rows, the warnings for unrecognised columns are reported as before.

**Check after the fix:**
```
'name,email,company\n' -> ImportReport(created=[], updated=[], errors=[], warnings=[]) | empty: True
'name,first_name,last_name,email\n\n,,,\n' -> ImportReport(created=[], updated=[], errors=[], warnings=[]) | empty: True
'name,email,company\nAnn Lee,ann@example.com,Acme\n' -> ImportReport(created=['ann@example.com'], updated=[], errors=[], warnings=[RowIssue(row=1, column=None, message="column 'company' is not recognised and was ignored")]) | empty: False
```

**Full suite:** `python3 -m pytest -q`
```
177 passed in 0.12s
```

Nothing was rejected, and nothing is committed yet.

### [review2] operator

Review the changes since commit 28ef20afc43e715ce6c1d20ca8a3510dabf22442 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review2] agent

I found no correctness gaps. I checked the changes against SPEC.md, mainly the new file `src/contactbook/importer.py`, plus the new `ImportFileError` in `errors.py` and its export from `__init__.py`. The full test suite passes (177 tests), and I also fed the importer a set of edge-case files by hand. All of these behave as SPEC.md requires:

- **Row numbering:** quoted cells that span several lines are numbered by the line they start on. Blank lines and `,,` lines still count toward the numbering, and `\r\n` endings work.
- **Rejecting the whole file:** a quote that is never closed is rejected even when it's near the end. Exactly 1000 data rows import; 1001 are rejected. Trailing blank rows don't count. In every rejected case the repository was left unchanged, because the whole file is checked before any row is applied.
- **Header:** names match regardless of case and surrounding spaces, and column order is free. A file with `first_name`/`last_name` and no `name` builds the name from the parts and gives "Lee" when only `last_name` is filled. When `name` is also present, `first_name`/`last_name` are treated as unrecognised columns.
- **Rows:** cells beyond the header produce a warning. A bad phone gives a warning and the contact is imported without it. Bad tags make the row an error. Tags are normalised and repeats collapse. The first occurrence of an email wins, even if that row was itself an error.
- **Updates:** existing tags are kept and the new ones added, an existing phone is never cleared, and a contact that ends up unchanged is listed in neither `created` nor `updated`.
- **Round trip:** importing an export back into the same contact book reports nothing created, nothing updated and no errors.

One non-blocking note: the comment at `src/contactbook/importer.py:74-75` says a header-only file returns "header warnings included", but the code returns a fresh empty report. The code is what SPEC.md asks for (an empty report); only the comment is wrong.

FINDINGS: 0
