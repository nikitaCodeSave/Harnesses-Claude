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

I've read the code (`Contact.create`, the validators, `InMemoryContactRepository`, `export_csv` with columns `name,email,phone,tags` and `;`-joined tags). Here's the first round of questions. Each one has a proposed default, so you can just reply "ok" or give the number and your answer.

**A. When a row fails validation**
1. **Partial or all-or-nothing?** If row 7 has a bad email, do the other valid rows still get imported, with row 7 listed in `errors`? Or does any row error mean nothing gets written to the repo (the report still lists every error)?
   *Proposed:* partial import. Good rows are written and bad rows are skipped and reported.
2. **How many errors per row?** If a row has both a bad email and a bad phone, do we report both (one `RowIssue` per bad column) or stop at the first?
   *Proposed:* report every bad column, so Sales can fix the whole row in one pass.

**B. Rows whose email already exists in the repo (`updated`)**
3. **What does an update overwrite?** *Proposed:* the CSV row is the full truth for that contact. Name, phone and tags are all replaced.
4. **Blank phone cell for an existing contact.** Should it clear the stored phone, or leave it alone? Clearing matches export round-trip semantics. Leaving it alone is safer for sparse lead sheets.
5. **Tags for an existing contact.** Replace them with the file's tags, or add the file's tags to the existing ones?
6. **Row identical to the stored contact.** Should it appear in `updated`, or in neither list?
   *Proposed:* neither list, since the interface has no "unchanged" bucket.

**C. Duplicates inside the file**
7. **Same email on two rows** (after normalisation, e.g. `Ann@X.com` and `ann@x.com`). Options:
   - (a) the later row wins and the earlier one gets a warning
   - (b) the first row wins and the later one is an error
   - (c) both rows are errors
   
   *Proposed:* (b), because silently overwriting looks like data loss.

**D. File-level problems (`ImportFileError`) vs row-level problems**
8. *Proposed:* raise `ImportFileError` in these cases, and leave the repo untouched:
   - the bytes can't be decoded
   - the file is empty
   - there is no header row
   - the header is missing `name` or `email`
   
   A header-only file (no data rows) is not an error: it returns an empty report. Do you agree, and is there anything else that should reject the whole file?
9. **Header flexibility.** *Proposed:*
   - columns may appear in any order
   - header names are matched case-insensitively, with surrounding spaces trimmed
   - `phone` and `tags` columns are optional
   - unknown extra columns are ignored, with one warning (`row` = header row, `column` = that column)
   - a duplicated header name is an `ImportFileError`
   
   Does that work?

**E. Encoding and format (where spreadsheets usually cause trouble)**
10. **Encodings.** For bytes, accept UTF-8, with or without the BOM that Excel adds. Should we also accept Windows-1252/Latin-1 as a fallback, which is what "Save as CSV" in older Excel produces? Or should anything that isn't UTF-8 be an `ImportFileError` with a "save as CSV UTF-8" message?
11. **Delimiter.** Excel in many European locales saves CSV with `;` as the delimiter, but `;` is also our tag separator. Should we only support comma-delimited files (like the export), or detect `;` files too?

**F. Row numbers**
12. *Proposed:* `RowIssue.row` is the 1-based line as it would appear in the spreadsheet, so the header is row 1 and the first data row is row 2. Fully blank rows are skipped silently but still count toward numbering. `column` is the canonical column name (`"email"`), or `None` for whole-row problems such as the wrong number of cells.

### [spec] user

Answers by number:
1. Yes, partial import. Good rows go in, bad rows are reported in errors and skipped. A bad row is not applied at all, not even partly to an existing contact.
2. I don't mind whether it's one entry or several per row. One correction: a bad phone is NOT an error. The rest of the row is still imported or updated, the phone is left as it was (none for a new contact), and the row gets a *warning* with column `phone`. A bad email, name or tag is an error.
3. Not quite. The name from the file replaces ours. The phone is replaced only when the cell has a value. Tags are not replaced (see 5).
4. A blank phone cell, or a missing phone column, must never wipe a phone we already have. Leave it alone.
5. Add the file's tags to the existing ones. An import never removes tags.
6. I don't mind. Use your recommendation.
7. (b). The first row wins and every later row with that email is an error on that later row and is not applied.
8. I agree with all of those. Two additions:
   - A file with more than 1000 contact rows is also rejected whole. Blank rows don't count toward the 1000.
   - `name` can be replaced by a `first_name` + `last_name` pair, as our address-book export script writes it. The name is then the two joined with one space. The header is only missing a name if neither form is present.
9. Mostly fine. Any order, case-insensitive, spaces trimmed, `phone` and `tags` optional. Unknown extra columns are ignored, and I don't mind whether there's a warning, as long as it's never an error. I don't mind how you handle duplicate header names.
10. UTF-8 only, no fallback. Excel's "CSV UTF-8" adds a BOM, which must just work. That applies to bytes, and also to text input that still starts with the BOM character. Invalid UTF-8 should give an ImportFileError telling people to re-save as "CSV UTF-8".
11. I don't mind. Comma only is fine.
12. Agreed. The header is row 1, the first contact is row 2, and every line counts, blank lines included. `column` is the lower-case column name (name, email, phone or tags). A name problem in a first_name/last_name file is also `name`. I don't mind what you do for wrong cell counts.

### [spec] agent

Thanks, that settles most of it. A few gaps are left, mostly from your new rules interacting with each other. Again, each has a proposed default.

1. **First row with a given email is itself an error.** Say row 2 has `ann@x.com` with a blank name (error, skipped) and row 5 has `ann@x.com` and is valid. Does row 5 get applied, or is it still "a later row with that email"?
   *Proposed:* only a row that was actually applied claims the email, so row 5 is applied. Sales fixes row 2 by deleting it or merging it, and nothing is lost.
2. **Empty pieces in the tags cell**, e.g. `vip;;lead`, a trailing `;`, or `vip; `.
   *Proposed:* empty or whitespace-only pieces are ignored and are not an error. Any other invalid tag is an error.
3. **Both `name` and `first_name`/`last_name` in the header.**
   *Proposed:* `name` is used and the other two are ignored like any unknown column. Also, having only one of `first_name`/`last_name` (without `name`) counts as "no name", so it's an `ImportFileError`.
4. **One half of the name is blank.** If `first_name` = "Cher" and `last_name` is blank, *proposed:* the name is "Cher", with no trailing space. If both are blank, it's a `name` error.
5. **What counts toward the 1000-row limit.** *Proposed:*
   - every non-blank data row counts, including rows that later turn out to be errors or in-file duplicates
   - exactly 1000 is accepted and 1001 is rejected
   - "blank" means every cell is empty or whitespace
6. **Cells containing line breaks.** A quoted cell can contain a line break (e.g. a notes column), so one spreadsheet row can span two physical lines.
   *Proposed:* `row` is the spreadsheet row number, i.e. it matches what Sales sees in Excel, rather than the physical line in the file. Without multi-line cells the two are identical.

I'll settle these myself in the spec unless you object:
- **Wrong cell count:**
  - a short row's missing trailing cells are treated as blank
  - a row with more cells than the header is an error with `column=None`, because it usually means an unquoted comma shifted the columns
- **Duplicate header names:**
  - a duplicated recognised column (e.g. `email` twice) is an `ImportFileError`
  - duplicated unknown columns are ignored
- **Unknown columns:** one warning per unknown column, on row 1.
- **Unchanged contacts:** a row that changes nothing on an existing contact appears in neither `created` nor `updated`.
- **CRLF line endings** are accepted.
- **Non-goals:** no other delimiters or encodings, no dry-run mode, imports never delete contacts or remove tags, and a wrong argument type stays a `TypeError` as `errors.py` says.

### [spec] user

1. I don't mind. Use your proposal.
2. Agreed. Empty pieces and repeats are ignored, and an invalid tag makes the row an error.
3. I don't mind. Use your proposal.
4. I don't mind. Use your proposal.
5. Agreed. A file with exactly 1000 contact rows is fine, and blank rows don't count.
6. I don't mind. Use your proposal.

I'm fine with everything you listed to settle yourself.

### [spec] agent

I've written the spec to `SPEC.md`. It has 43 acceptance criteria that can each be checked, a non-goals list, and the interface copied word for word from your request.

**Where I chose, because you didn't mind:**
- **Duplicates in the file:** only a row that was actually applied claims an email. A rejected row with the same email doesn't block a later valid one (criteria 31–32).
- **Name columns:** if `name` is present it's used, and `first_name`/`last_name` are treated as unknown columns. Having only one of `first_name`/`last_name` counts as having no name. If one half is blank, the name is the other half alone (criteria 9–10, 24).
- **Unchanged contacts:** a row that changes nothing on an existing contact appears in neither `created` nor `updated` (criterion 39).
- **Row length:** a row with too few cells is treated as having blanks at the end. A row with too many cells is an error with `column=None` (criteria 20–21).
- **Header problems:** a repeated known column name rejects the whole file. Each unknown column gives one warning on row 1, with `column=None` and the column's name in the message, because you limited `column` to name/email/phone/tags (criteria 12–13).
- **Row numbers** follow spreadsheet rows, not physical lines. The two only differ when a quoted cell contains a line break (Terms).
- **Messages per row:** whether a row with several problems gets one error or several is up to the implementer (criterion 28).

**Added checks that follow from your answers:**
- **Round trip:** importing the output of `export_csv` into an empty repo reproduces the same contacts, with no errors or warnings (criterion 43).
- **Nothing written on rejection:** when `ImportFileError` is raised, the repo is left exactly as it was (criterion 17).
- **Every row is accounted for:** each non-blank row either created or updated a contact, changed nothing, or has an error (criterion 42).

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've written 179 acceptance tests under `tests/acceptance/`, one file per spec section, covering all 43 criteria plus the Interface section. All 179 fail for now, and they fail only because the importer doesn't exist yet.

**Command run:**
```
python3 -m pytest tests/acceptance -q
```
**Output (tail):**
```
FAILED tests/acceptance/test_import_row_errors.py::test_error_row_does_not_claim_its_email_for_an_existing_contact
179 failed in 0.63s
```
Grouping the failures by error message:
```
    141 E   ModuleNotFoundError: No module named 'contactbook.importer'
     38 E       AttributeError: module 'contactbook.errors' has no attribute 'ImportFileError'
```
The full suite (`python3 -m pytest -q`) gives `179 failed, 24 passed`, so the existing 24 tests still pass.

**How they're built**
- They only use what the spec names: `import_contacts`, `ImportReport`, `RowIssue`, `ImportFileError`, the repository, `Contact`, and `export_csv` for the round trip.
- Expected values come from the spec. Where it says values follow "the package's existing rules" (criterion 22), I used the documented normalisations, such as `"+1 (555) 123-4567"` → `"+15551234567"` and `"Key Account"` → `"key-account"`.
- The importer is loaded inside each test (via `tests/acceptance/_support.py`), not at the top of each file. Otherwise pytest would stop at collection and skip all the tests, existing ones included. Once the feature exists the tests behave normally.
- Every test that expects `ImportFileError` also checks that the repository is unchanged (criterion 17).
- Where the spec leaves a choice open (criterion 28: one issue or several for a row with several problems), the tests accept either.

**Calls I made where the spec is less explicit**
- A row with more cells than the header is an error even if the extra cell is empty (`Ann,ann@x.com,,vip,`). Criterion 21 says "more cells", with no exception.
- A row whose cells are all empty is blank and skipped, even if it has more cells than the header. The spec defines a blank row by its contents, not its width.
- An empty phone cell gives no warning; only an invalid one does (criterion 33). For a whitespace-only phone cell, the tests only check that an existing phone is kept.

**Not verified:** I tried to check the expected values against a throwaway reference importer in a scratch copy under `/tmp`, outside the repo. That command was denied, so I didn't pursue it. The tests are confirmed to fail for the right reason, but not yet confirmed to pass against a correct implementation. Errors in my expected values, such as a wrong row number, would only show up once the importer is written.

Nothing is committed.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

CSV import is built as SPEC.md describes, and all 203 tests pass: the 179 acceptance tests plus the 24 existing ones. I didn't change anything under `tests/`.

**Command and output** (from the repo root):

```
$ python3 -m pytest
...
tests/test_service.py ...                                                [ 94%]
tests/test_validation.py ...........                                     [100%]
============================= 203 passed in 0.07s ==============================
```

**What changed**
- **`src/contactbook/importer.py`** (new): `import_contacts(repo, data)`, `ImportReport` and `RowIssue` with the fixed interface. It decodes and reads the whole file and checks the header and the 1000-row limit before it touches the repository. So when the file as a whole is rejected, nothing has been created or updated. Field checks reuse the package's existing validators.
- **`src/contactbook/errors.py`**: added `ImportFileError(ContactError)`. It is also exported from `contactbook/__init__.py`.
- **`README.md`**: added `importer.py` to the layout list.

**Choices the spec left open**
- **Rows with several problems** get one error per problem (name, email, each bad tag), not a single combined error.
- **Rows with too many cells** get only that one error; their other cells aren't checked.
- **Invalid phones** get a warning even when the row is rejected for another reason, so Sales sees everything that needs fixing in one pass.
- **Badly formed CSV** that Python's CSV reader can't parse (rare, e.g. an oversized cell) is reported as `ImportFileError`, so the import still raises no other domain error.
- **Data that is `bytearray` or anything else other than `str`/`bytes`** raises `TypeError`, as the spec's "programming error" rule says.

Nothing is committed yet.

### [review1] operator

Review the changes since commit 9b84b9d8e19cf7a4dfe589650ac29a156eac20c1 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found nothing that needs fixing. `src/contactbook/importer.py` and the changes to `errors.py` and `__init__.py` meet all 43 acceptance criteria in SPEC.md.

I checked each criterion against the code and ran the test suite: all 203 tests pass, including the acceptance tests. I also ran some extra edge cases by hand, and each gave the result the spec asks for:

- **Row numbers:** with CRLF line endings, blank rows and a quoted cell containing a line break, rows are still numbered as they appear in the spreadsheet (criteria 5 and 19).
- **BOM and header names:** a file starting with the BOM, with header names in mixed case and in a different order, is read correctly (criteria 3 and 7).
- **Round trip:** importing the `export_csv` output for contacts whose names contain quotes and commas, with formatted phones and tags containing spaces, recreates the same contacts in the same order (criterion 43).
- **`first_name`/`last_name`:** if both are blank the row is a name error; if only one is filled in, the name is that one alone with no stray space. An invalid phone in a row that also has an error still produces a phone warning (criteria 24 and 33).
- **Extra cells:** a row with a trailing extra cell is an error with `column=None` (criterion 21).
- **File-level errors:** every `ImportFileError` is raised before the repository is changed (criterion 17).

One edge case that I'm not counting as a finding: a single cell over 131,072 characters hits a limit in Python's CSV reader. It then raises `ImportFileError` (`importer.py:110`) even if the cell is in an unknown column. Excel can't produce such a file, since its cells hold at most 32,767 characters, so this doesn't affect the files the spec describes.

FINDINGS: 0
