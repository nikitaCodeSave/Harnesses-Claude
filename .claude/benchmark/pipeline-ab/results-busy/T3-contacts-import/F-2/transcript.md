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

I've read the code: `export.py` writes `name,email,phone,tags` with a header, tags sorted and joined by `;`, and an empty phone cell when there's no phone. The repository is keyed by normalised email and has separate `add`/`update`. Validation lives in `validation.py`/`Contact.create`.

Here's the first set of questions. Each one has my suggested answer, so you can just say "agree" or tell me which ones to change.

**A. Existing contacts (this matters most)**
1. **When an email is already in the book**, does the row overwrite the contact or merge into it? I suggest:
   - **Name:** overwritten by the file.
   - **Phone:** overwritten by a non-blank phone. A blank phone cell keeps the existing phone. (Overwriting would mean an export → edit → import round trip could wipe phones.)
   - **Tags:** the file's tags are added to the existing ones and nothing is removed. Or should the file's tag set replace the existing tags exactly?
2. **A row that matches an existing contact exactly** (nothing changes): leave it out of `updated` and add no warning? Or list it under `updated` anyway?
3. **The same email appearing twice in one file** (case-insensitive): the first row wins and later rows become errors ("duplicate of row N")? Or the last row wins?

**B. Bad rows vs bad files**
4. **Partial import:** valid rows are saved, invalid rows go to `errors` and are skipped, and the repo is left untouched only when `ImportFileError` is raised. Is that right, or do you want all-or-nothing (any row error means nothing is saved)?
5. **When to raise `ImportFileError` (whole file rejected):**
   - The file is empty.
   - The `email` or `name` column is missing from the header.
   - A column name appears twice in the header.
   - The bytes can't be decoded.
   - The CSV is malformed (for example, an unclosed quote).

   A file with a header and no data rows would return an empty report, not an error. OK?
6. **A single invalid tag in a row:** reject the whole row as an error? Or drop just that tag, keep the rest of the row, and add a warning? I'd reject the row so nothing is silently lost, but salespeople may prefer the lenient option.

**C. File format tolerance**
7. **Header:**
   - Column order doesn't matter.
   - Header names are matched case-insensitively with surrounding spaces trimmed.
   - `phone` and `tags` columns are optional.
   - Unknown extra columns are ignored, with one warning naming them.
8. **Encoding of `bytes`:** UTF-8, with or without a BOM (Excel's "CSV UTF-8" adds one). Should we also fall back to Windows-1252? That's what plain "CSV" from Excel on Windows produces, but guessing the encoding can silently garble names. My suggestion is UTF-8 only, raising `ImportFileError` with a hint to re-save the file as "CSV UTF-8".
9. **Delimiter:** comma only? Excel in some European locales saves files with `;`, which clashes with our tag separator. I'd keep comma-only and give a specific `ImportFileError` ("looks semicolon-separated") when the header is a single cell containing `;`.
10. **Rows with the wrong number of cells:**
    - Blank lines are skipped silently.
    - Missing trailing cells are treated as empty.
    - Extra non-empty cells beyond the header produce a warning, and the row is still imported.

**D. Reporting**
11. **Meaning of `RowIssue.row`:** the spreadsheet row number, so the header is row 1 and the first data row is row 2. That way sales can jump straight to the row in Excel. `RowIssue.column` is the header column name (`"email"`, `"tags"`, …), or `None` for issues about the whole row. Messages reuse the validator's wording (for example, `is not a valid address: 'x'`).
12. **One error or several per row:** report only the first problem in each row, or every invalid field in it? I'd report every invalid field so people can fix the whole row in one pass.
13. **Order:** `created` and `updated` follow file order, and `errors`/`warnings` are sorted by row.

**E. Scope**
14. **Non-goals:**
    - A row/size limit.
    - Deleting contacts that are missing from the file.
    - A dry-run mode.
    - Adding an import method on `ContactBook`.
    - Exporting the new names from `contactbook/__init__.py`.
    - A CLI or HTTP endpoint.
    - Any change to `export_csv`.

    Should any of these be in scope?

### [spec] user

Answers by number.
1. Agree on all three: the file's name replaces ours; phone is replaced only when the cell has a value; tags are added to the existing ones and an import never removes tags.
2. I don't mind, use your recommendation.
3. Agree: first row wins, every later row with that email is an error on that later row and isn't applied.
4. Partial import is right. A bad row is not applied at all, not even partly to an existing contact.
5. Agree on the empty file, a missing required column and undecodable bytes. A header-only file gives an empty report. I don't mind about duplicate header names or malformed CSV. One addition: a first_name + last_name pair counts as the name column. The contact's name is the two joined with one space, and a name problem there is still reported as column `name`.
6. Reject the row as an error (column `tags`).
7. Agree. For unknown columns, ignoring them or adding a warning are both fine, but never an error.
8. UTF-8 only, with a hint to re-save as "CSV UTF-8". The BOM must also work when the input is text that still starts with the BOM character, not only for bytes.
9. I don't mind, use your recommendation.
10. Blank lines are skipped silently. That includes rows where every cell is empty or only spaces, like Excel's `,,,` lines. I don't mind about rows with too many or too few cells.
11. Agree on the spreadsheet row number, header = row 1. Every line of the file counts, blank lines included. `column` should be the lower-case column name: `name`, `email`, `phone` or `tags`. I don't mind about `None`.
12. I don't mind, use your recommendation.
13. I don't mind, use your recommendation.
14. Row limit: this IS in scope. A file has at most 1000 contact rows (blank rows don't count). A bigger file is rejected as a whole with ImportFileError and nothing is imported. The other non-goals are fine.

### [spec] agent

Thanks, that covers nearly everything. Your first_name/last_name addition and the row limit raise a few new edge cases. Each has my suggested answer:

**a. A header with both `name` and `first_name`+`last_name`:** the `name` column wins, and `first_name`/`last_name` are treated as unused columns (warning only). Alternatively, the file could be rejected as ambiguous with `ImportFileError`.

**b. Only one of `first_name`/`last_name` in the header (and no `name`):** treated as a missing required column, so `ImportFileError`. It only counts as a name column when both are present.

**c. One of the two cells is blank in a row:** the name is just the other cell, with no stray space. If both are blank, it's a row error: column `name`, "is required". A combined name over 100 characters is also a `name` error.

**d. Header matching for these columns:** same rule as the others (case-insensitive, spaces trimmed), so `First_Name` matches but `First Name` and `firstname` don't. Or should those variants also be accepted?

**e. A quoted cell containing a line break:** a row error gets the line number where that record starts. The extra line still counts toward later row numbers, so numbers match a text editor, which can drift by one from Excel's view after such a cell. Is that OK given "every line of the file counts"?

**f. The 1000-row limit:** every non-blank data row counts, including invalid rows and in-file duplicates. Exactly 1000 is accepted and 1001 is rejected.

For the points you left to me, I'll go with:
- **Unchanged contacts:** not listed in `updated`.
- **Semicolon files:** comma only, with a specific "looks semicolon-separated" `ImportFileError`.
- **Duplicate header names or unparseable CSV:** `ImportFileError`.
- **Unknown columns:** one warning.
- **Too many cells in a row:** warning; too few: treated as empty.
- **Errors per row:** every invalid field is reported, not just the first.
- **Order:** `created`/`updated` in file order; issues sorted by row.

### [spec] user

I don't mind about a, b, d and e, so use your recommendations. On c, the name must be validated with the existing name helper, and an empty name is an error on column `name`. Your plan fits that.

f is fine: blank rows don't count, and exactly 1000 contact rows is accepted. I accept the rest of your list as well.

Go ahead and write SPEC.md.

### [spec] agent

I've written `SPEC.md`. It copies your interface word for word and has 41 checkable acceptance criteria, plus a non-goals list. Your answers and the defaults you approved are all in it.

I had to settle three small points myself. Please check them:

- **Duplicates after a rejected row (criterion 31):** following "first row wins" literally, a later row with the same email is an error even if the first row was itself rejected. So a corrected copy of a bad row lower in the file won't be imported.
- **Blank tag items (23):** empty pieces of a tags cell, like a trailing `;` or `vip;;lead`, are ignored rather than treated as invalid tags.
- **Round trip (38–39):** I added two criteria. Importing an `export_csv` file into an empty book recreates the same contacts, and importing it again changes nothing.

Tell me if any of these should change and I'll update the spec.

### [spec] user

All three are fine. The first one I don't mind. The second matches what I want. On the third, round-trip criteria are fine as long as they only check the state of the book. Don't require that an unchanged contact is absent from `updated`, because I don't mind whether it's listed there. Please check that 38–39 don't say that.

### [spec] agent

You were right to ask. Criterion 39 did require it: it said `updated` must be empty on re-import. I've fixed that in `SPEC.md`:

- **38–39:** these now check only what's in the book. Importing an `export_csv` file into an empty book leaves it holding exactly those contacts, and importing it again leaves the book unchanged. Neither criterion says anything about the report anymore.
- **34:** this had the same requirement from my earlier default. It now says an unchanged contact keeps its values and isn't listed in `created`, and it doesn't produce an error or warning. Whether it shows up in `updated` is left open; either way is fine.

I checked every other place `updated` appears in the spec. None of them requires an unchanged contact to be left out.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

I built the CSV import and the full test suite passes.

**Command:** `python3 -m pytest`

```
tests/test_repository.py ....                                            [ 86%]
tests/test_service.py ...                                                [ 89%]
tests/test_validation.py ...........                                     [100%]

============================= 102 passed in 0.05s ==============================
```

That's the 24 tests that were already there plus 78 new ones in `tests/test_importer.py`. The new tests are grouped by the spec's sections (input and encoding, header, whole-file rejection, row values, row errors, applying rows, round trip), and every criterion from 1 to 39 has at least one test. 40 (standard library only) and 41 (`export_csv` and the existing API unchanged, old tests pass) hold too.

**What changed**
- `src/contactbook/errors.py`: added `ImportFileError(ContactError)`.
- `src/contactbook/importer.py` (new): `import_contacts`, `ImportReport` and `RowIssue`. The whole file is read and checked before the repository is touched, so a file-level error leaves the repository unchanged (criterion 16). Each row is numbered by the line it starts on, so blank lines and line breaks inside quoted cells count. Values go through the existing validators, so error messages are the validators' own.

**Choices where the spec left room**
- **Several bad tags in one row:** the row gets a single `tags` error naming the first bad tag, following "each invalid field as its own `RowIssue`". If you'd rather list every bad tag, that's a small change.
- **Unchanged contacts:** if a row would leave an existing contact exactly as it was, its email is not added to `updated` (the spec allows either).
- **Empty header cells** (e.g. a trailing comma in the header) don't count as duplicate column names. They show up in the unknown-columns warning as "(unnamed column N)".
- **Strict parsing:** the CSV is parsed strictly, so an unterminated quote or text right after a closing quote (`"a"b`) rejects the whole file. Python 3.12's CSV parser accepts NUL characters, so those are not treated as unparseable.

Nothing is committed yet; `SPEC.md` is still untracked as it was.
