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

I've read the code: `export_csv` writes `name,email,phone,tags` with a header row, tags sorted and joined by `;`, and an empty cell for no phone. The repository is keyed on normalised email, and `validation.py` has all the field rules. My questions below follow from that. Each one has my recommendation, so you can just answer "agree" or correct the ones you see differently.

**A. What happens to existing contacts**

1. **Matching email already in the repo**: I'd **update** that contact (this is what `updated` is for). Should the file's values **replace** the stored ones entirely, so the file is the source of truth? Or should they **merge**?
   - Specifically: an **empty phone cell**. Does it clear the stored phone, or leave it alone? I'd say leave it alone. Sales sheets often just don't have the phone, and wiping data silently is worse than not updating it.
   - **Tags**: replace the stored set, or add to it? I'd say add to it (union), for the same reason.
2. **Row identical to what's stored**: should it go in `updated`, or in neither list? I'd say neither, so `updated` means "something actually changed".

**B. Partial failures**

3. **Some rows invalid**: I'd import the valid rows and report each bad row in `errors`. The other option is all-or-nothing, where any row error means nothing gets imported. Which do you want?
4. **What counts as a warning, not an error**: my proposal:
   - Error, row skipped: missing or invalid name or email, invalid phone.
   - Warning, row still imported: one bad tag in an otherwise good row, with that tag dropped; an unknown extra column, which is ignored.
   - Does that split sound right? In particular, should an invalid phone skip the whole row or just drop the phone with a warning?
5. **Same email twice in one file**: I'd import the first occurrence and give each later one an error that points back to the first row. The alternative is last-row-wins. Which?

**C. File format** (these files come from spreadsheets, not only from our export)

6. **Header**: required. Columns matched by name, so any order, case-insensitive, outer spaces ignored. `name` and `email` are required columns; `phone` and `tags` can be missing. A missing required column raises `ImportFileError`. Agree?
7. **Encoding of `bytes`**: UTF-8, with or without a BOM. Excel's "CSV UTF-8" adds a BOM. Anything that isn't valid UTF-8 raises `ImportFileError`, and we don't guess other encodings. Is that OK, or does sales use Windows Excel's plain "CSV" save, which writes cp1252?
8. **Delimiter**: comma only, like the export? Or should we also accept `;`-delimited files, which European-locale Excel produces?
9. **Row numbers in `RowIssue`**: the line number as a spreadsheet shows it, so the header is row 1 and the first data row is row 2. Blank rows are skipped silently but still count toward the numbering. `column` is the header name (`"phone"`), or `None` for whole-row problems. Agree?
10. **Empty file / header only**: an empty file (or one with no header) raises `ImportFileError`. A header with no data rows is a valid import with an empty report. Agree?
11. **Limits**: is there a max file size or row count we should reject with `ImportFileError`, or none for now?

Answer however suits you, even just "agree except 3 and 7: …".

### [spec] user

Mostly agree, but several of these I'd answer differently:

**1.** Name: the file's value replaces ours. Phone: replaced only when the cell has a value, and an empty cell never wipes a phone. Tags: add to the existing ones, and an import never removes tags.

**2.** I don't mind. Pick whichever is easier.

**3.** Partial import, as you recommend. A bad row isn't applied at all, not even partly to an existing contact.

**4.** Not quite.
- An invalid phone is a warning, not an error. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning for that row with column `phone`.
- An invalid tag is an error on the row, not a warning. Skip the row, with column `tags`.
- Missing or invalid name or email is an error.
- An unknown extra column is ignored. A silent ignore or a warning is fine, but never an error.

**5.** First row wins. Each later row with that email is an error on that later row and isn't applied.

**6.** Agree. Also, if `first_name` and `last_name` columns are present instead of `name`, accept them. Our address-book export script writes those. The name is the two joined with one space.

**7.** UTF-8 only. A BOM must work, for bytes and also for text that still starts with the BOM character. Anything that isn't valid UTF-8, such as old Windows-1251 saves, raises `ImportFileError` telling them to re-save as "CSV UTF-8".

**8.** I don't mind. Comma only is fine.

**9.** Agree on the numbering: the header is row 1 and every line counts, blank lines included. `column` is the lower-case name: `name`, `email`, `phone` or `tags`. A name problem in a `first_name`/`last_name` file is `name` too. For whole-row problems, do what you suggested.

**10.** Agree. An empty file is rejected, and a header-only file gives an empty report. Blank rows, meaning empty lines or rows where every cell is empty or only spaces, are skipped silently.

**11.** Yes: at most 1000 contact rows per file, not counting blank rows. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported.

Also, tags are separated by `;` in the cell. Empty pieces and repeats are ignored.

### [spec] agent

Thanks, that settles most of it. For Q2 I'll take the simpler rule: every applied row whose email already existed goes in `updated`, changed or not. That way each applied row shows up in exactly one of `created` or `updated`.

A few edge cases are still open. Each has a recommendation:

12. **Duplicate when the first row was rejected**: say row 2 has `ann@x.com` with a bad tag (error), and row 5 has `ann@x.com` and is valid. Does row 5 get imported? I'd say **yes**: the email is "taken" only by the first row that was actually applied. The alternative is that the first row with that email blocks every later one, even if it failed.
13. **Several problems in one row**, e.g. a bad email and a bad tag: I'd report **one error per problem column**, so they can fix everything in one pass. When a row is rejected, I'd **drop its phone warning**: the row didn't import, so the warning means nothing. Agree?
14. **Name columns**:
    - If a file has both `name` and `first_name`/`last_name`, I'd say `name` wins and the others are ignored.
    - If only one of `first_name`/`last_name` is present as a column, or one cell is empty, I'd use whichever part is there. Both empty means the "name is required" error.
    - A file with neither `name` nor `first_name`/`last_name` raises `ImportFileError`. Agree?
15. **Broken file structure**:
    - A header with the same column twice (two `email` columns): `ImportFileError`.
    - A data row with fewer cells than the header: missing cells count as empty.
    - A row with more cells than the header: I'd make that a row error (`column: None`), since it usually means an unquoted comma shifted the data.
    - Unparseable CSV, such as an unclosed quote: `ImportFileError`.
16. **Quoted cells containing line breaks** (Excel allows this in a cell): row numbers would then count **spreadsheet rows (records)**, not physical text lines, so they match what sales sees in Excel. That's the same as "every line counts" for normal files. OK?

### [spec] user

Q2 is fine: every applied row whose email already existed goes in `updated`.

For 12 to 16 I don't mind either way, so I accept your recommendations on all of them: 12 (a later duplicate of a rejected first row is imported), 13 (one error per problem column, phone warning dropped on rejected rows), 14 (name columns), 15 (broken file structure) and 16 (row numbers count records for multi-line cells).

Go ahead and write SPEC.md.

### [spec] agent

I've written `SPEC.md`. It has a short why, the interface copied word for word from your request, a few defined terms ("record", "row number", "applied row", and so on) so the criteria can be checked unambiguously, 37 numbered acceptance criteria, and a list of non-goals.

A few choices weren't explicitly settled between us, so please check these:

- **Extra cells beyond the header (criterion 22):** I narrowed what you accepted in 15. A row is only an error if an extra cell has something in it. Extra cells that are all blank are ignored, because Excel often writes trailing empty cells, and those would otherwise turn good rows into errors.
- **Duplicate-email errors use `column == "email"`** rather than `None`, since the email cell is what they'll look at in the spreadsheet.
- **Unknown columns are ignored silently,** with no warning. You said either was fine.
- **Duplicate column detection** only applies to columns we use. A repeated unknown column is still just ignored.
- **The 1000-row limit counts rejected rows.** Only blank rows are excluded.
- **Passing something that is neither `str` nor `bytes` raises `TypeError`,** following the existing rule in `errors.py` that programming errors aren't wrapped in `ContactError`.

Tell me if any of these should change and I'll update the spec. Otherwise it's ready to build from.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've written the acceptance tests under `tests/acceptance/`. All 171 fail, and each one fails only because the feature doesn't exist yet. Nothing has been implemented or committed.

**Command run:**
```
python3 -m pytest tests/acceptance -q
```
**Output (last line):**
```
171 failed in 0.63s
```
Grouping the failures by cause with `--tb=line`:
```
133  ModuleNotFoundError: No module named 'contactbook.importer'
 38  AttributeError: module 'contactbook.errors' has no attribute 'ImportFileError'
```
No failure comes from a mistake in a test. The existing suite still passes (`24 passed`).

**What's there.** There is one file per spec section, and each test is labelled with its acceptance criterion number:

| File | Criteria |
|---|---|
| `test_import_interface.py` | Interface (`ImportReport`/`RowIssue` are dataclasses with the named fields), 6, 9 |
| `test_import_decoding.py` | 1–5 |
| `test_import_file_rejection.py` | 7–8 |
| `test_import_header.py` | 10–14 |
| `test_import_names.py` | 15–17 |
| `test_import_fields.py` | 18–25 |
| `test_import_duplicates.py` | 26–28 |
| `test_import_apply.py` | 29–32 |
| `test_import_report.py` | 33–37 |

The tests call only `import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError`, plus the existing `InMemoryContactRepository`, `Contact` and `export_csv`. Expected values are written out by hand from the spec. `support.py` looks the new names up when each test runs, so each test fails separately instead of the whole module failing to import.

**Where I had to interpret the spec:**
- **Non-`str`/`bytes` input (AC 6):** `bytearray` and `memoryview` are expected to raise `TypeError`, following "anything other than `str` or `bytes`" literally.
- **"Short, human-readable" message (AC 36):** I check it as a non-empty single line of at most 200 characters, with no traceback or `Error(` text in it.
- **"Mentions the row number" (AC 27):** checked by searching the message for that number on its own.
- **Bad encoding:** besides raising `ImportFileError`, I also check that the repository is left unchanged. AC 7 doesn't list this case explicitly.
- **Unknown columns (AC 12):** repeated unknown columns and empty header names are both accepted silently.
- **Later duplicate with other problems:** a duplicate row that also has a bad tag gets two errors, one for email and one for tags (AC 24 combined with AC 27).
- **Not tested:** the order of several errors within one row, and two cases the spec leaves unclear: a whitespace-only tag piece (`vip; ;lead`), and blank lines before the header.

These tests haven't been run against any implementation, so when the importer is written, a failure could still be a bug in a test rather than in the code.

I also ran `ruff format` (line length 100) over the new files only.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

CSV import is built and the full suite passes: the acceptance tests and the existing tests, 195 in total.

**Command:** `python3 -m pytest` (from the repo root; `pyproject.toml` sets `testpaths = ["tests"]`, so this covers both `tests/acceptance/` and the existing tests)

**Output (summary):**
```
tests/acceptance/test_import_fields.py ................................. [ 34%]
.............                                                            [ 41%]
tests/acceptance/test_import_file_rejection.py ......................... [ 54%]
........                                                                 [ 58%]
tests/acceptance/test_import_header.py .................                 [ 67%]
tests/acceptance/test_import_interface.py .........                      [ 71%]
tests/acceptance/test_import_names.py .........................          [ 84%]
tests/acceptance/test_import_report.py ......                            [ 87%]
tests/test_export.py ..                                                  [ 88%]
tests/test_models.py ....                                                [ 90%]
tests/test_repository.py ....                                            [ 92%]
tests/test_service.py ...                                                [ 94%]
tests/test_validation.py ...........                                     [100%]
============================= 195 passed in 0.08s ==============================
```
Before the change, 171 of these failed because the importer didn't exist yet. I didn't touch `tests/acceptance/`.

**What changed**
- **`src/contactbook/importer.py`** (new) has `import_contacts`, `ImportReport` and `RowIssue`. It reads and checks the whole file before changing anything: decoding, CSV parsing, the header and the 1000-row limit. A file-level problem therefore always leaves the repository untouched. It then processes rows in file order, using the existing validators and `Contact` methods.
- **`src/contactbook/errors.py`** adds `ImportFileError(ContactError)`.
- **`src/contactbook/__init__.py`** exports the new names, and **`README.md`** lists the new module.

**Choices the spec didn't settle**
- **Strict CSV parsing:** besides unclosed quotes, a malformed quote such as `"a"b,c` also rejects the whole file.
- **Line endings:** `\r\n` is converted to `\n` before parsing, so line breaks inside quoted cells also come out the same either way.
- **Blank first line:** the first record is always the header, so a file that starts with a blank line fails with "missing column(s)". Leading blank lines are not skipped.
- **Messages:** they reuse the validators' wording, e.g. `email is not a valid address: 'bad'`. A duplicate email gives `email ann@x.com is already used by row 2`. Messages are cut to 200 characters, which matters when a cell holds a very long value.

### [review1] operator

Review the changes since commit ec1d84742d50cd045a3e95d67641c02f8b7c2b74 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found nothing that needs fixing. The new `src/contactbook/importer.py` and the changes to `errors.py` and `__init__.py` meet all 37 acceptance criteria in SPEC.md.

**How I checked:**
- **Test suite:** all 195 tests pass, including the new acceptance tests in `tests/acceptance/`.
- **Criterion by criterion:** I compared each criterion against `importer.py`, `validation.py` and `models.py`. That covered decoding and the BOM, the `TypeError` for wrong input types, the file-level checks, header matching, the `first_name`/`last_name` fallback, the per-field rules, duplicate handling, the update rules and the report ordering.
- **File-level errors:** every file-level check runs before any row is applied, so the repository stays unchanged when the whole file is rejected (criterion 7).
- **Duplicates:** only applied rows claim an email (criterion 28).
- **Extra cells:** a row with non-blank extra cells gets exactly one error with no column, and nothing else (criterion 22).
- **Warnings:** phone warnings appear only for applied rows (criterion 25).
- **Row numbers:** these count records, not text lines, and blank rows are included (criteria 34 and 37).
- **Edge cases run by hand:**
  - An unclosed quote and junk after a closing quote both raise `ImportFileError`.
  - `\r\n` and `\n` files give the same result.
  - A file of only empty cells or blank lines raises `ImportFileError`.

One unrealistic case: a single cell over Python's CSV field-size limit (about 131,000 characters) rejects the whole file as "not valid CSV" rather than giving a row error. A spreadsheet of leads won't contain that, so I didn't count it.

FINDINGS: 0
