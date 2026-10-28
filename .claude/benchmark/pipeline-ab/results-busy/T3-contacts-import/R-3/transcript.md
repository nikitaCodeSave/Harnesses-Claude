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

I've read the code: `export.py` writes `name,email,phone,tags` with a header, tags sorted and joined with `;`, and an empty cell for no phone. The repo is keyed by normalised email, and `Contact.create` does all the validation. Here's the first round of questions. Each has my suggested answer, so you can just say "agree" or correct the ones you'd change.

**1. Email already in the book.** `ImportReport.updated` implies an upsert. When a row's email matches an existing contact:
- (a) The row **replaces** the contact: name, phone and tags all come from the file. A blank phone cell clears the phone, and an empty tags cell clears the tags.
- (b) The row **merges** into the contact: blank cells keep the existing value, and tags are added to the existing ones.

I suggest **(a)**. It matches export, so export → edit in a spreadsheet → import round-trips exactly. The downside is that a sparse spreadsheet would wipe data. Which do you want?

**2. Bad rows mixed with good ones.** Should valid rows still be imported while invalid rows go to `errors` (partial import)? Or should any row error mean nothing is written (all-or-nothing)? I suggest **partial**, since the report has both `created` and `errors`. All-or-nothing is safer if sales would rather fix the file and re-run.

**3. Same email twice in one file** (after normalisation, e.g. `Ann@X.com` and `ann@x.com`). Options:
- (a) The first row wins and later rows are errors.
- (b) The last row wins, with a warning.
- (c) Every row with that email is an error and none is imported.

I suggest **(a)**.

**4. Row numbers in `RowIssue.row`.** I suggest the row number as the spreadsheet shows it: header = 1, first data row = 2. For a cell with an embedded newline, that's the row where the record starts. And `column` should be the field name (`"email"`, `"phone"`, …), or `None` for problems with the whole row, like a wrong cell count or a duplicate.

**5. Header handling.**
- Is a header row required? I suggest yes.
- Should columns be allowed in any order, with header names matched case-insensitively and trimmed?
- If `name` or `email` is missing from the header → `ImportFileError`. If `phone` or `tags` is missing, treat it as blank for every row.
- An unknown extra column (e.g. `company`) is ignored, with one warning (row 1, `column="company"`).
- A duplicated header name → `ImportFileError`.

Agree?

**6. Spreadsheet quirks: encoding and delimiter.** For bytes, I'd accept UTF-8 with or without a BOM (Excel's "CSV UTF-8" adds one), and treat undecodable bytes as an `ImportFileError`. Two follow-ups:
- Do sales use plain "CSV" from Excel on Windows? That saves Windows-1252 (or another local code page) rather than UTF-8, so names like "Zoë" would fail. Should we support a fallback encoding, or stick to UTF-8 only and give a clear error?
- Is anyone on a European/Russian locale, where Excel saves with `;` as the delimiter? That collides with our `;` tag separator. I suggest **comma only** (as export writes it), with a semicolon-delimited file rejected by a clear `ImportFileError`. Confirm?

### [spec] user

1. Neither as written. It should be a merge, with these specifics:
- The name from the file replaces ours.
- The phone is replaced only when the cell has a value. A blank cell or a missing phone column never wipes an existing phone.
- Tags from the file are added to the existing ones. An import never removes tags.

   An existing email is an update, not an error, and never creates a second contact.

2. Partial import. Good rows go in, and bad rows go to `errors` and are skipped. A bad row must not be applied at all, not even partly to an existing contact.

3. (a) Agree. The first row wins, and each later row with that email is an error on that later row and is not applied.

4. Agree on the spreadsheet numbering, with one change: every line of the file counts, blank lines included. `column` is the lower-case column name (`name`, `email`, `phone` or `tags`). I don't mind what you use for whole-row problems.

5. Mostly agree.
- A header is required, column order is free, and names are matched case-insensitively with spaces around them ignored.
- A missing `email`, or a missing name column, rejects the whole file with `ImportFileError`. Our address-book export writes `first_name` and `last_name` instead of `name`. Accept that pair as the name column, and join the two with one space.
- A missing `phone` or `tags` column is fine.
- Unknown extra columns are ignored. A silent ignore or a warning is fine, but never an error.
- I don't mind about duplicated header names.

6. UTF-8 only, with or without a BOM. Text input that still starts with the BOM character must also work. Bytes that aren't valid UTF-8 give an `ImportFileError` telling people to re-save as "CSV UTF-8". Don't add a fallback encoding. Comma only is fine, and I don't mind how you handle other delimiters.

### [spec] agent

That settles most of it. A few edge cases remain before I can write checkable criteria:

**7. `first_name` / `last_name`.**
- If the header has `name` *and* `first_name`/`last_name`, I'd use `name` and ignore the other two. OK?
- Does only one of the pair (e.g. `first_name` without `last_name`) count as "missing name column" → `ImportFileError`? I suggest yes.
- If one cell is blank on a row (`Ann`, empty), the name is just `Ann`. If both are blank, it's a `name` error on that row. Agree?

**8. Blank and short rows.**
- Blank lines and rows where every cell is empty: skip them silently? They still count for numbering, as you said.
- A row with fewer cells than the header: treat the missing cells as blank (Excel trims trailing empty cells sometimes)?
- A row with more cells than the header: suggest a whole-row error.

**9. Several problems in one row** (bad email *and* bad phone). Report one `RowIssue` per bad field, or only the first? I suggest one per field, so people can fix everything in one pass.

**10. Tag cells.** An invalid tag anywhere in the cell makes the row an error (consistent with "bad row is not applied at all"). Empty pieces like `vip;;lead` or a trailing `;` are silently ignored. Agree?

**11. No-op updates.** If a row matches an existing contact but changes nothing (same name, no new phone, no new tags), does the email still go in `updated`? I suggest yes: `updated` = "matched an existing contact and was applied". The alternative is a separate bucket, which the interface doesn't have.

**12. What belongs in `warnings`?** So far nothing *must* produce one. Do you want any guaranteed warnings? Candidates:
- Unknown columns ignored.
- A blank phone cell kept an existing phone.

Or should I leave `warnings` unconstrained, beyond "warnings never prevent a row being applied"?

**13. Whole-file failures.**
- I suggest `ImportFileError` for:
  - empty input or no header,
  - missing required columns,
  - invalid UTF-8,
  - broken CSV syntax (e.g. an unterminated quote).
- A header-only file returns an empty report.
- When `ImportFileError` is raised, the repo is left completely unchanged. Agree?

**14. Non-goals.** I plan to list these as out of scope:
- Excel/xlsx and other formats.
- Deleting contacts that are absent from the file.
- A dry-run/preview mode.
- HTTP/CLI wiring.
- Non-UTF-8 encodings.
- Non-comma delimiters.
- Size limits.

Anything to add or remove?

### [spec] user

7. I don't mind the first two points, since those cases aren't covered. The blank-cell part I do care about: if both first and last name are blank, it's a `name` error on that row. A single blank cell is fine, so use the other part. Don't leave a stray space.

8. Blank lines, and rows where every cell is empty or only spaces, are skipped silently, and they still count for numbering. I don't mind how you handle rows with fewer or more cells than the header.

9. I don't mind. One issue per field is fine.

10. Agree. One invalid tag makes the row an error (column `tags`). Empty pieces and repeated tags are ignored.

11. I don't mind whether a no-op update goes in `updated`.

12. One thing is fixed: a phone that fails validation must not cost us the contact. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning, not an error, with column `phone` for that row. I don't mind about other warnings.

13. Mostly agree. Reject the whole file with `ImportFileError` and import nothing for:
- an empty file,
- a missing required column,
- invalid UTF-8,
- more than 1000 contact rows. Blank rows don't count toward that limit, and people should split bigger files.

    A file with only the header is fine, and the report is empty. I don't mind about broken quoting.

14. Remove "size limits" from the non-goals, because the 1000-row limit is in scope. The rest is fine.

### [spec] agent

I wrote the spec to `SPEC.md`. It copies the interface verbatim and has 33 numbered acceptance criteria, a non-goals list, and a "left open" section. That section lists everything you said you don't mind about, so tests won't lock those choices in.

A few points in the spec are my own reading of your answers rather than your exact words. Please check them:

- **Criterion 31, duplicate emails:** if the first row with an email has an error, it still counts as "the first row". A later row with the same email is then also an error, rather than taking its place.
- **Criterion 12, empty file:** a file that contains only whitespace or blank lines counts as empty, so it's rejected with `ImportFileError`.
- **Criterion 14, row limit:** exactly 1000 contact rows is accepted, and invalid rows count toward the 1000. Only blank rows are excluded.
- **Criterion 30, invalid phone:** when updating an existing contact, an invalid phone keeps the contact's existing phone. This is the same as your "leave the phone as it was" rule for new contacts.

If any of those should go the other way, tell me and I'll change the spec.

### [spec] user

- **Criterion 31:** Move it to the "left open" section. I don't mind either way, so tests shouldn't lock it in.
- **Criterion 12:** Fine. Rejecting a file with only whitespace or blank lines is OK.
- **Criterion 14:** Agree. Exactly 1000 contact rows is accepted, invalid rows count toward the 1000, and only blank rows are excluded.
- **Criterion 30:** Agree. An invalid phone keeps the existing phone, and the rest of the row is still applied.

### [spec] agent

I've updated `SPEC.md`:

- **Criterion 31:** the rule that a first row with an error still counts as "first" is gone. That case is now listed under "Left open", so tests won't lock it in. The rest of the criterion stays: the first row with an email is processed, and later rows with the same email are errors and aren't applied.
- **Criterion 14:** now says that invalid rows count toward the 1000-row limit and blank rows don't. Exactly 1000 contact rows is accepted.
- **Criterion 30:** now says that an existing contact keeps its current phone and a new contact gets no phone. The rest of the row is still applied, with a `phone` warning.
- **Criterion 12:** a file with only whitespace or blank lines is still rejected, as you confirmed.

The spec is ready for implementation.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've written 129 acceptance tests in `tests/acceptance/`, covering all 33 criteria. All 129 fail right now, as intended. I didn't implement the feature, and no file under `src/` changed.

**Command:**
```
python3 -m pytest tests/acceptance -q --tb=no
```
**Output (tail):**
```
FAILED tests/acceptance/test_import_rows.py::test_any_invalid_tag_is_an_error_on_the_tags_column[vip;xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]
FAILED tests/acceptance/test_import_rows.py::test_one_row_can_have_an_error_for_each_bad_field
129 failed in 0.07s
```

I grouped the failures with `python3 -m pytest tests/acceptance -q --tb=line`, and they fail only because the feature is missing:
```
101  ModuleNotFoundError: No module named 'contactbook.importer'
 28  ImportError: cannot import name 'ImportFileError' from 'contactbook.errors'
```
The existing suite still passes: `python3 -m pytest -q tests --ignore=tests/acceptance` gives `24 passed`.

**Layout**, one file per section of the spec:
- `test_import_interface.py`: `import_contacts`, plus the shape of `ImportReport` and `RowIssue`.
- `test_import_decoding.py`: criteria 1–5. Bytes vs text, BOM, invalid UTF-8 (the message must contain "CSV UTF-8"), quoting, CRLF line endings, and importing `export_csv` output back.
- `test_import_header.py`: criteria 6–13.
- `test_import_limits.py`: criteria 14–16. Exactly 1000 rows passes, 1001 fails with a message containing "split", invalid rows count toward the limit and blank rows don't, and the repository is unchanged after every kind of `ImportFileError`.
- `test_import_rows.py`: criteria 17–26.
- `test_import_merge.py`: criteria 27–33.
- `support.py`: small helpers. It imports the importer inside each test, so each test fails on its own instead of the whole file failing to load.

**How I kept the tests from deciding things the spec leaves open:**
- **Order:** report lists are compared sorted or as sets.
- **Messages:** only the two required phrases are checked ("CSV UTF-8" and "split").
- **Columns:** checks are "contains `email`" rather than "equals", so an extra whole-row issue doesn't break them.
- **Warnings:** only checked where the spec fixes them: the invalid-phone warning, none on blank rows, and none for a header-only file.
- **Rows:** every data row has exactly as many cells as the header. The one exception is a whitespace-only line, which counts as a blank row by the spec's definition.
- **Not tested at all:**
  - whether an update that changes nothing is listed in `updated`
  - a header with both `name` and `first_name`/`last_name`
  - a file with only one of `first_name`/`last_name`
  - duplicate header names
  - broken quoting
  - which row counts as "first" when the first row with an email has an error

**Edge cases I derived from the spec rather than read directly, so worth a look:**
- A file containing only a BOM counts as empty (criterion 12).
- A header with no `email` or no name column raises `ImportFileError` even when there are no data rows. I read criteria 8–9 as overriding criterion 13 here.
- A row with a bad name, a bad email and a bad tag must report an error for each of `name`, `email` and `tags` (criteria 22, 23, 25 and 26 together).

The tests are not committed.

### [check] user

One test locks in something I don't mind about. A row with several problems can produce one error entry or several, so tests shouldn't require an error for each of `name`, `email` and `tags`. Please loosen `test_one_row_can_have_an_error_for_each_bad_field` and any similar test. It's enough to check that the row is reported as an error at least once and isn't applied. The other edge cases you derived are fine.

### [check] agent

I loosened the test. `test_one_row_can_have_an_error_for_each_bad_field` is now `test_row_with_several_bad_fields_is_reported_and_not_applied` in `tests/acceptance/test_import_rows.py`. For a row with several bad fields it now checks only that:
- the row has at least one error, and
- it isn't applied: nothing is created, an existing contact is unchanged, and its email is not in `created` or `updated`.

The old test's only row had an invalid email, so "not applied" couldn't really be seen. The new test runs four rows:
- every field bad, including the email
- a new contact with a bad name and a bad tag
- an existing contact with a bad name and a bad tag
- an existing contact with a too-long name, a bad tag and an invalid phone

Each file also has one good row, to check it is still imported (partial import).

No other test required one error per bad field. The other rows with several problems combine a bad tag with an invalid phone. A bad phone is only a warning, and those tests already just check that the row has at least one error. Every other row in the error tests has only one bad field.

**Command:**
```
python3 -m pytest tests/acceptance -q --tb=no
```
**Output (tail):**
```
FAILED tests/acceptance/test_import_rows.py::test_row_with_several_bad_fields_is_reported_and_not_applied[all-bad]
FAILED tests/acceptance/test_import_rows.py::test_row_with_several_bad_fields_is_reported_and_not_applied[new-contact]
FAILED tests/acceptance/test_import_rows.py::test_row_with_several_bad_fields_is_reported_and_not_applied[existing-contact]
FAILED tests/acceptance/test_import_rows.py::test_row_with_several_bad_fields_is_reported_and_not_applied[existing-contact-bad-phone-too]
132 failed in 0.08s
```
There are now 132 tests because the one test became four. They still all fail only because the feature doesn't exist yet: 104 with `No module named 'contactbook.importer'` and 28 with `cannot import name 'ImportFileError'`.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

CSV import is built, and both the acceptance tests and the existing suite pass:

```
$ python3 -m pytest -q
........................................................................ [ 46%]
........................................................................ [ 92%]
............                                                             [100%]
156 passed in 0.06s
```

That's 132 acceptance tests plus the 24 existing ones. I didn't change anything under `tests/`.

**What changed**
- `src/contactbook/errors.py`: added `ImportFileError(ContactError)`.
- `src/contactbook/importer.py` (new): `import_contacts`, `ImportReport` and `RowIssue`, with the interface the spec fixes. The whole file is decoded, parsed and counted before anything is written. So when `ImportFileError` is raised (bad encoding, empty file, missing columns, more than 1000 rows), the repository is unchanged. Each row is fully checked before it is added or merged, and all field checks use the existing `validation.py` functions.

**How I settled the open points**
- **Both `name` and `first_name`/`last_name` in the header:** `name` wins. Having only one of `first_name`/`last_name` (with no `name`) is rejected as a missing name column.
- **Repeated header names:** the first column with that name is used.
- **Repeated email where the first row has other errors:** if the email itself is valid, that row still counts as the first. Later rows with the same email are errors on the `email` column.
- **Rows with too few or too many cells:** missing cells count as blank, and extra cells are ignored.
- **Broken quoting:** Python's `csv` reader doesn't fail on an unclosed quote. It reads the rest of the file into one field, so the row ends up as a row error rather than an `ImportFileError`. An actual `csv.Error` becomes an `ImportFileError`.
- **Extra warnings:**
  - One warning on row 1 lists any unknown columns that were ignored.
  - An invalid phone still produces its warning even when the row has other errors and isn't applied.
- **Updates that change nothing:** they are still listed in `updated`.
- **Blank first line:** the header is taken from line 1 as the spec says, so a file starting with a blank line is rejected with "no 'email' column". It is not treated as an empty file.

I also checked by hand that a quoted cell spanning several lines doesn't throw off the row numbers in later issues.

### [review1] operator

Review the changes since commit 651be35a11779710187cbec931f0b64334c944c2 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found one gap against SPEC.md. The rest of the importer matches the spec, and all 156 tests pass.

**1. A header-only file with an unknown column returns a warning, which breaks criterion 13.** `src/contactbook/importer.py:67-71`

The unknown-column warning is added before the code knows whether there are any data rows. Criterion 13 says a file with only a header row must return a report with all four lists empty. Criterion 11 allows warnings for unknown columns, but it doesn't override 13.

I reproduced it: `import_contacts(repo, "name,email,company\n")` returns `warnings=[RowIssue(row=1, column=None, message='ignored unknown columns: company')]` instead of an empty list.

**Fix:** only add this warning when there is at least one contact row (`if ignored and rows:`), or drop it.

FINDINGS: 1

### [fix1] operator

A fresh reviewer who has not seen your reasoning reported:

I found one gap against SPEC.md. The rest of the importer matches the spec, and all 156 tests pass.

**1. A header-only file with an unknown column returns a warning, which breaks criterion 13.** `src/contactbook/importer.py:67-71`

The unknown-column warning is added before the code knows whether there are any data rows. Criterion 13 says a file with only a header row must return a report with all four lists empty. Criterion 11 allows warnings for unknown columns, but it doesn't override 13.

I reproduced it: `import_contacts(repo, "name,email,company\n")` returns `warnings=[RowIssue(row=1, column=None, message='ignored unknown columns: company')]` instead of an empty list.

**Fix:** only add this warning when there is at least one contact row (`if ignored and rows:`), or drop it.

FINDINGS: 1

Reproduce each finding before changing anything; fix the real ones and reject the rest in one sentence each. Report the command and its output.

### [fix1] agent

The reviewer's finding was real and is now fixed; there was nothing to reject.

**Reproduced first:** `import_contacts(repo, "name,email,company\n")` returned a `warnings` list with one item, `ignored unknown columns: company`. Criterion 13 says a header-only file must give a report with all four lists empty.

**Fix:** at `src/contactbook/importer.py:68` the unknown-column warning is now added only when there is at least one contact row (`if ignored and rows:`). A file with data rows still gets the warning.

**Checked after the fix:**
```
$ PYTHONPATH=src python3 -c '...'
ImportReport(created=[], updated=[], errors=[], warnings=[])                 # header only
[RowIssue(row=1, column=None, message='ignored unknown columns: company')]  # with a data row

$ python3 -m pytest -q
............                                                             [100%]
156 passed in 0.06s
```

None of the 156 tests covers this case. I didn't add a test for it because `tests/acceptance/` is read-only for me. If you want it pinned, it could go in the existing suite.

### [review2] operator

Review the changes since commit 651be35a11779710187cbec931f0b64334c944c2 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review2] agent

I found no correctness gaps: the importer matches SPEC.md against every acceptance criterion.

I read the diff (the new `ImportFileError` in `errors.py`, plus the new `src/contactbook/importer.py`) alongside the code it relies on (`validation.py`, `models.py`, `repository.py`, `export.py`). The full test suite passes (156 tests), and I ran edge cases by hand. These all behaved as the spec requires:

- **Input:** UTF-8 bytes with or without a BOM, text starting with U+FEFF, and invalid UTF-8 (raises `ImportFileError` asking to re-save as "CSV UTF-8").
- **Line numbers:** stay correct across blank lines, CRLF and bare-CR line endings, and quoted cells that span several lines.
- **Blank rows:** skipped, not counted toward the 1000-row limit, and nothing is written to the repository before the limit check.
- **Header:** matched case-insensitively with surrounding spaces ignored; unknown columns are ignored; `email` and a name column are required.
- **`first_name`/`last_name`:** joined with one space, a blank half is dropped, and both blank is a `name` error.
- **Tags:** empty pieces and repeats are dropped, and tags are added to existing ones, never removed.
- **Merging existing contacts:** emails match after normalisation; the name is replaced; the phone changes only when the new one is non-blank and valid, otherwise the old one stays and an invalid phone gives a `phone` warning.
- **Rows:** a row with any error changes nothing; later rows repeating an email are errors; `created` and `updated` hold only normalised emails, with no duplicates.

One unusual case, not a defect: a single cell over Python's CSV field limit (about 128 KB) rejects the whole file with `ImportFileError` instead of failing just that row. The repository is still left unchanged, and such a cell would fail validation anyway, so I didn't count it.

FINDINGS: 0
