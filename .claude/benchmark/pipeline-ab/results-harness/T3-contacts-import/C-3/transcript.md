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

Before I write the spec I need some decisions from you. I've read the code: `export.py` writes `name,email,phone,tags`, with tags joined by `;` in a single cell. There's no GLOSSARY.md or ADRs yet. Each question below has my recommendation, so you can just say "agree" or override individual items.

**A. Rows that match an existing contact (same email, case-insensitive)**
1. Should the import update the stored contact or leave it alone? *Rec: update it and list it in `updated`.*
2. When updating, what does the file replace? *Rec: the file row is the full truth. Name, phone and tags are replaced, so an empty phone cell clears the phone and an empty tags cell clears the tags. That mirrors export, so export → edit → import round-trips.* The alternative is "empty cell = keep existing; tags are merged, not replaced".
3. If a row matches the stored contact exactly, should it still go in `updated`? *Rec: no. It appears in neither list.*

**B. Bad data within a row**
4. Is it partial import (bad rows are skipped and reported in `errors`, good rows are saved) or all-or-nothing? *Rec: partial.*
5. One bad tag, e.g. `c++`, in an otherwise valid row: reject the row, or drop the tag and add a warning? *Rec: reject the row. Only `warnings` gets things that don't lose data.*
6. The same email appears twice in one file: *Rec: the first occurrence wins and the later row is an error ("duplicate of row N").* Alternatives: last one wins, or both rows are errors.
7. A row has more or fewer cells than the header: *Rec: too few means the missing cells are treated as empty. Too many is an error for that row.*
8. Completely blank rows: *Rec: skip them silently.*

**C. The file as a whole (→ `ImportFileError`)**
9. Header: is it required as the first row? *Rec: yes. Matching ignores case and surrounding whitespace, and column order is free. A missing `name` or `email` column is an `ImportFileError`. A missing `phone` or `tags` column is fine. Unknown extra columns are ignored, with one warning (`row=1, column=<name>`).*
10. Encoding of bytes: *Rec: UTF-8, with an optional BOM because Excel adds one. Anything that won't decode raises `ImportFileError`.* Should I add a fallback to cp1252/Latin-1 for older Excel "CSV" saves? *Rec: no fallback, because guessing silently can garble names.*
11. Delimiter: European Excel saves with `;`, which clashes with our tag separator. *Rec: comma only. A file whose header doesn't parse into the required columns raises `ImportFileError`, and the message hints at the delimiter.*
12. Empty file, or a header with no data rows: *Rec: an empty file (no header) raises `ImportFileError`. Header-only returns an empty report.*
13. Any limit on file size or row count? *Rec: none for now.*

**D. Reporting**
14. Row numbering: *Rec: the 1-based physical line where the record starts, with the header as row 1. That way it matches the row number Sales sees in their spreadsheet.*
15. `RowIssue.column`: *Rec: the field name (`name`/`email`/`phone`/`tags`) for validation errors, and `None` for row-level issues such as a duplicate or too many cells.*
16. Order of `created`/`updated`: *Rec: file order.*

Also: should `import_contacts` and the new types be re-exported from `contactbook/__init__.py`? *Rec: export `ImportFileError` there like the other errors. The importer stays reachable through its module path.*

### [build] user

A.
1. Agree: update the contact and list it in `updated`.
2. Don't do that. The name from the file replaces ours. Phone is replaced only when the cell has a value, so an empty cell or a missing phone column never wipes an existing phone. Tags from the file are added to the existing ones, and an import never removes tags.
3. I don't mind. Use your recommendation.

B.
4. Agree: partial import. A bad row is skipped entirely, with nothing applied even partly to an existing contact.
5. Agree: reject the row, with column `tags`.
6. Agree: the first row wins. Each later row with that email is an error and is not applied.
7. I don't mind. Use your recommendation.
8. Agree: skip silently. That includes rows where every cell is empty or only spaces, like Excel's `,,,` lines.

C.
9. Agree, with one addition. Our address-book export script writes `first_name` and `last_name` columns instead of `name`. Accept that pair as the name column, with the name being the two joined by one space. Extra columns are ignored. A warning is fine, but never an error.
10. Agree: UTF-8, no fallback. The BOM must work for bytes and also for text that starts with the BOM character. An invalid-UTF-8 error should tell people to re-save as "CSV UTF-8".
11. I don't mind. Comma only is fine.
12. Agree on both: an empty file raises `ImportFileError`, and header-only gives an empty report.
13. Don't do that. The limit is 1000 contact rows per file, and blank rows don't count. A bigger file raises `ImportFileError` and nothing is imported.

D.
14. Agree, with one clarification. The header is row 1 and every line counts, blank lines included.
15. `column` is the lower-case column the problem is in: `name`, `email`, `phone` or `tags`. A problem with a name from `first_name`/`last_name` is `name` too. A duplicate email is an `email` problem.
16. I don't mind. File order is fine.

Re-exports: I don't mind. Use your recommendation.

### [build] agent

CSV import is built, and the full suite passes:

```
$ python3 -m pytest -q
........................................................................ [ 88%]
.........                                                                [100%]
81 passed in 0.03s
```

That's the 24 existing tests plus 57 new ones. Every acceptance criterion in the spec has at least one test. I also broke the merge rules on purpose to confirm the tests catch it (4 failures), then restored the code.

**What changed**
- **Spec:** `specs/csv-import.md` has your answers, 25 acceptance criteria, non-goals, and your interface copied word for word.
- **Code:** `import_contacts`, `ImportReport` and `RowIssue` are in the new `src/contactbook/importer.py`. `ImportFileError` is in `errors.py` and also exported from `contactbook`.
- **Tests:** `tests/test_importer.py`, written before the code.
- **Docs:** I created `GLOSSARY.md` (it didn't exist before) and `docs/adr/0001-csv-import-merge-rules.md`. The ADR records that an import never clears a phone, never removes tags, imports good rows even when others fail, and imports nothing if the file itself is rejected. `README.md` lists the new module.

**Choices I made myself** (marked *(decision)* in the spec; tell me if any should change)
- **First row claims an email:** the first row with an email claims it even if that row is rejected for another reason. Later rows with that email are errors, so nothing with that email is imported.
- **All problems per row:** a row reports every invalid field, not just the first one.
- **Extra cells:** a row with more non-empty cells than the header is an error (column `None`). Trailing empty cells are ignored.
- **`name` wins:** if the header has `name` as well as `first_name`/`last_name`, `name` is used and the other two get an "ignored column" warning.
- **Duplicate columns:** a header that repeats a known column, e.g. two `email` columns, rejects the file.
- **Broken quoting rejects the file:** an unclosed quote rejects the whole file. Otherwise the following rows would silently merge into one cell.
- **Very long cells:** a cell over 131,072 characters rejects the whole file. That cap belongs to Python's CSV reader and raising it would change it for the whole program, so I left it alone.

**Review:** a fresh session reviewed the change against the spec, as CLAUDE.md asks for parsers. I fixed both bugs it found and added tests for its other points, then confirmed the new tests fail against the old code. Its sandbox couldn't run scripts, so it worked from reading the code and the test suite.
- A `;`-separated file with quoted cells didn't get the "delimited by commas" hint.
- A row with extra cells skipped its field checks and didn't claim its email.

I wrote one set of tests after the fix instead of before, which is backwards from CLAUDE.md.

Nothing is committed yet. Running the tests created `__pycache__/` folders, and the repo has no `.gitignore` to hide them.
