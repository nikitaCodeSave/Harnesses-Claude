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

I've read the code (Contact/validation, the repository, `export_csv` with columns `name,email,phone,tags`, and tags joined with `;`). Here's the first round of questions. Each one has a proposed default, so you can just answer "ok" or override by number.

**Partial import and existing contacts**
1. **Bad rows:** Should valid rows be imported while invalid rows are skipped and listed in `errors`, or should any error cancel the whole import? *Proposal: partial import. Only file-level problems raise `ImportFileError`, and in that case the repo is left untouched.*
2. **Email already in the repo:** Should the row replace the stored contact completely (name, phone and tags all come from the file), or be merged into it? In particular, does an empty `phone` cell clear the stored phone or keep it? Do the file's tags replace the stored tags or get added to them? *Proposal: full replace, which matches "the file is an export." An empty phone cell clears the phone.*
3. **Unchanged rows:** A row for an existing contact might be identical to what's stored. Should it be listed in `updated`, or in neither list? *Proposal: neither list, and no warning.*
4. **Same email twice in one file** (after normalisation): *Proposal: the first occurrence wins. Later ones become errors that point back to the first row number. The alternative is that the last one wins and earlier ones become warnings.*

**File format**
5. **Encoding of `bytes`:** Excel's "CSV UTF-8" adds a BOM, and plain "CSV" on Windows is often cp1252. *Proposal: accept UTF-8 with or without a BOM. Anything that doesn't decode as UTF-8 raises `ImportFileError` with a message saying "save as UTF-8". No guessing of encodings. A BOM in `str` input is also stripped.*
6. **Delimiter:** Excel in many European locales saves with `;`. *Proposal: comma only, as in the export. A `;`-delimited file would fail the header check with a clear message.* Do you want `;` supported?
7. **Header:**
   - *Proposal:* the header row is required, columns can be in any order, and names are matched ignoring case and surrounding spaces.
   - `name` and `email` must be present, otherwise `ImportFileError`. `phone` and `tags` are optional.
   - Unknown extra columns are ignored, with one warning (`row` = header row).
   - A duplicated column name raises `ImportFileError`.
8. **Row numbering in `RowIssue.row`:** *Proposal: use the line number the user would see in the spreadsheet, where the header is row 1 and the first data row is row 2.* (If a quoted cell contains a newline, the row number is where that record starts.)

**Per-row rules**
9. **Errors vs warnings:**
   - *Proposal:* an error means the row was not imported. A warning means the row was imported but something was ignored.
   - A row can collect several errors, one per bad field, with `column` set to the column name. Every field gets checked, not just the first bad one.
   - `column=None` is for whole-row problems, such as a row with more cells than the header.
10. **One invalid tag in a valid row**, e.g. `lead;!!!`: *Proposal: error for the whole row, consistent with "never store unvalidated values". The alternative is to drop the bad tag, import the row and add a warning.*
11. **Blank lines and empty pieces:** *Proposal: fully blank rows (including rows that are only commas) are skipped silently. Empty pieces in the tag cell (`lead;;vip`, trailing `;`) are ignored.*
12. **Empty input:**
   - *Proposal:* empty input or whitespace-only input raises `ImportFileError` ("no header").
   - A header with no data rows returns an empty report.
   - Malformed CSV, such as an unclosed quote, raises `ImportFileError`.

**Scope**
13. **Non-goals:**
   - *Proposal:* no size or row limit.
   - No dry-run mode.
   - No `ContactBook` method, no CLI or HTTP, no export from `__init__`. Should `import_contacts` be re-exported from the package?
   - No deleting contacts that are missing from the file.
   - Does that match what you want, or do you need a row limit (e.g. for the HTTP upload)?

### [spec] user

1. Agreed: only file-level problems raise ImportFileError, then nothing is imported; a bad row is not applied at all, not even partly to an existing contact.
2. No, this one differs. Existing contact (same normalised email) is updated, listed in `updated`, never an error. Name: file's value replaces ours. Phone: replaced only when the cell has a value; an empty cell or missing phone column never wipes a stored phone. Tags: file's tags are ADDED to existing ones; import never removes tags.
3. Don't mind either way.
4. Agreed: first row wins, every later row with that email is an error on that later row and is not applied.
5. Agreed, including stripping a BOM from str input.
6. Don't mind; comma only is fine.
7. Mostly agreed, plus one addition: the address-book export writes `first_name` and `last_name` instead of `name`. That pair counts as the name column, name = first and last joined with one space. So required = `email` plus either `name` or that pair; a missing required column rejects the whole file. Unknown extra columns: ignore, with or without a warning, but never an error. Duplicate column names: don't mind.
8. Agreed, but every line of the file counts, blank lines included (header = row 1, first contact = row 2).
9. Mostly agreed, with one correction: an invalid phone is NOT an error. Import/update the rest of the row, leave the phone as it was (none for a new contact), and add a warning with column `phone`. `column` is the lower-case name: name, email, phone or tags (a name problem in a first_name/last_name file is `name` too). Several errors per row is fine.
10. Agreed: an invalid tag makes the row an error, column `tags`. Normalise each tag with the existing tag helper; empty pieces and repeats are ignored.
11. Agreed: rows that are empty or where every cell is empty/only spaces are skipped silently.
12. Mostly agreed: a completely empty file is an ImportFileError; header-only gives an empty report. Malformed CSV handling: don't mind.
13. I do need a row limit: more than 1000 contact rows (blank rows don't count) rejects the whole file with ImportFileError, nothing imported. Re-export from the package: don't mind. Other non-goals are fine.
Also: normalise email with the existing email helper (trim + lower-case); a missing or invalid email is an error on that row; created/updated list normalised emails. Name is required on every row, also for updates, validated with the existing name helper; empty name is an error on column `name`. Phone goes through the existing phone helper. Non-UTF-8 bytes raise ImportFileError telling them to re-save as "CSV UTF-8".

### [spec] agent

Thanks. That settles most of it. A few edge cases are still open, mostly where your new rules interact with each other. Again each has a proposed default:

1. **Both `name` and `first_name`/`last_name` columns in one file:** *Proposal: `name` wins and the pair is ignored, like any unknown column.* Related: if only one of `first_name`/`last_name` is present and there's no `name`, I'll treat it as a missing required column, so the whole file is rejected. If one of the two cells is empty in a row, the name is just the other cell. If both are empty, it's a `name` error.
2. **Duplicate email where the first occurrence was itself an error** (e.g. a bad tag): *Proposal: the first row with that email "wins" even though it failed. Later rows with that email are still errors and aren't applied. This keeps the result independent of which row happened to be valid.* The alternative is that the first *valid* row wins.
3. **Phone warning on a row that's rejected anyway** (bad phone plus bad tag): *Proposal: report the phone problem in that row's issues anyway (as a warning, column `phone`), so the user can fix everything in one pass.* The alternative is to report only errors for rejected rows.
4. **Cell count doesn't match the header:** *Proposal:* missing trailing cells count as empty. Extra cells beyond the header make the row an error with `column=None`.
5. **Blank lines before the header:** *Proposal: the header must be the first line (row 1). A file whose first line is blank is rejected because the required columns are missing.* Alternatively, I skip leading blank lines and the header takes the row number it's on.

For the points where you said "don't mind" (unchanged rows, duplicate column names, how malformed CSV is handled, a warning for unknown columns, re-exporting from the package), I'll write them into the spec as left to the implementer, so tests don't pin them down. Is that OK?

### [spec] user

All five are cases I don't mind, so go with your proposals (1-5). Leaving my 'don't mind' points to the implementer is OK too. Once SPEC.md is written, I'll take it from there.

### [spec] agent

I've written `SPEC.md` at the repo root. I haven't committed it.

It contains:
- the four interface items, copied word for word from your request;
- a short "Terms" section defining row number, blank row, contact row, error, warning and `RowIssue.column`;
- 29 acceptance criteria you can check one by one;
- a "Left to the implementer" section with each of your "don't mind" points, marked as things tests must not pin down;
- non-goals.

Three details came from me, not from you. Check them before you start:
- **List order:** `created` and `updated` list emails in file order, with each email at most once (criterion 25). I added this so tests get a predictable result.
- **Duplicate-email error column:** a duplicate email in the file is reported on column `email`, and the message must give the first row's number (criterion 27). You agreed to pointing back to the first row, but the column choice was mine.
- **"Changes nothing" exception:** criterion 24 says updated rows are listed in `updated`, except a row that changes nothing, which may be left out. That reconciles your answer 2 with your "don't mind" on unchanged rows.

### [spec] user

Two of your three additions go further than I asked, so please loosen them. (1) Criterion 25: I don't care about the order of entries in created/updated/errors/warnings, so tests must not pin file order; listing each email at most once is fine. (2) Criterion 27: column `email` for the duplicate is fine, but message wording is up to the implementer, so tests must not require the first row's number in the message (pointing back is fine as a courtesy). Criterion 24 is fine as written. Once those two are changed I'm happy with the spec.

### [spec] agent

I've loosened both points in `SPEC.md`:

- **Criterion 25:** it now only requires each normalised email to appear at most once, and never in both `created` and `updated`. I removed "file order."
- **Criterion 27:** a duplicate email is still an error on the later row, on column `email`, and isn't applied. The message no longer has to give the first row's number.
- **"Left to the implementer":** this section now says the order of entries in all four lists is up to the implementer. The message-wording exception now names only criterion 4, the "CSV UTF-8" hint. It also notes that pointing back to the first row is a courtesy, not a requirement.

Criterion 24 is unchanged. The spec is still uncommitted.

### [spec] user

One more point: wording of ImportFileError messages is also up to the implementer, so criterion 4 shouldn't require the 'CSV UTF-8' text. The message should still tell people to re-save the file, but tests must not check specific words. Everything else is fine. Once that's changed I'm done with the spec.

### [spec] agent

I've updated `SPEC.md`, which is now final per your notes:

- **Criterion 4:** non-UTF-8 bytes still raise `ImportFileError`. The message should tell the user to re-save the file as UTF-8, but tests must not check its wording.
- **"Left to the implementer":** this section now says the wording of every message is up to the implementer, both in `RowIssue.message` and in `ImportFileError`. Pointing back to the first row for a duplicate email and suggesting a UTF-8 re-save are described as courtesies that tests don't check.

Nothing else changed, and the spec is still uncommitted for you to take from here.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

I've built the CSV import described in SPEC.md, and the full test suite passes.

**Command:** `python3 -m pytest`
```
============================= 101 passed in 0.04s ==============================
```
That's 24 tests that were already there plus 77 new ones in `tests/test_importer.py`.

**What changed**
- **`src/contactbook/importer.py`** (new): `import_contacts`, `ImportReport` and `RowIssue`, with the signatures the spec fixes. It reads and checks the whole file before touching the repository. So when it raises `ImportFileError`, nothing has been added or changed (criterion 2); valid rows are only saved once every check has passed.
- **`src/contactbook/errors.py`**: adds `ImportFileError(ContactError)`.
- **`src/contactbook/__init__.py`, `README.md`**: the package now exports the four new names, and the README describes the new module.

**Coverage:** the new tests cover all 29 criteria. They check row and column numbers but not message wording, list order, or any behaviour the spec leaves open. As a check that the tests can catch real bugs, I broke the importer on purpose twice: once by removing the BOM handling, once by miscounting row numbers. The tests failed both times, and I put the correct code back.

**Choices where the spec left it open**
- **Broken CSV** (e.g. an unclosed quote) rejects the whole file with `ImportFileError`, and the message gives the row number.
- **An existing contact the row doesn't change** is left out of `updated`.
- **Repeated column names in the header:** the first one is used.
- **Unknown columns** are ignored with no warning.
- **A row with more cells than the header** gets the whole-row error (`column=None`). Its other fields are still checked, and its email still counts for spotting duplicates later in the file.
- **Error messages** for a repeated email give the row where that email first appeared, and the not-UTF-8 message tells the user to re-save the file as UTF-8.

Nothing is committed: the changes are in the working tree, alongside `SPEC.md`, which was already untracked.
