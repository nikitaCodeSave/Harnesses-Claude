### [build] operator

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

### [build] agent

I've read the code (validation, `Contact.create`, the repository, and `export_csv` with columns `name,email,phone,tags`, where tags are joined with `;`). There's no GLOSSARY.md, no ADRs and no specs dir yet. Before I write the spec I need some decisions from you. For each one I've put a proposed default, so you can just answer "defaults OK" or override by number.

**Existing contacts (same email already in the repo)**
1. **What does an update do?** Default: the row is the source of truth. Name is overwritten. A non-empty phone cell overwrites the phone. Tags are **replaced** by the row's tags. Alternatives: merge tags (union), or never touch existing contacts.
2. **Blank phone or tags cell on an update.** Default: blank means "no value", so the phone is cleared and the tags are emptied. This is consistent with the export, where blank means none. The alternative is "blank = leave unchanged", which is safer for half-filled sales sheets. **Note:** this choice matters for 1.
3. **A row identical to the stored contact.** Default: it doesn't appear in `updated` and gets no warning. Should it be in `updated` anyway?

**Bad rows and atomicity**
4. **Partial import or all-or-nothing?** Default: partial. Valid rows are applied, invalid rows go to `errors` and are skipped. The alternative is that any row error means nothing gets applied, while the report still lists everything.
5. **The same email appearing twice in the file.** Default: the first occurrence wins and later ones become an error ("duplicate of row N"). Alternative: the last one wins with a warning.
6. **One invalid tag in a row.** Default: the whole row is an error with `column="tags"`. Alternative: drop the bad tag and add a warning.
7. **Fully blank rows.** Default: skip them silently. Alternative: skip them with a warning.

**File level (`ImportFileError`)**
8. Default triggers for `ImportFileError`:
   - empty file
   - missing `name` or `email` header
   - bytes that can't be decoded
   - malformed CSV, such as an unterminated quote

   `phone` and `tags` columns are optional. The header is matched case-insensitively and with whitespace trimmed, and columns can come in any order. Unknown extra columns are ignored, with one warning per column (`row=1`, `column=<name>`).
9. **Encoding of `bytes`.** Default: UTF-8, with a UTF-8 BOM stripped (Excel's "CSV UTF-8" writes one). Should I also fall back to cp1252 or UTF-16? Those are what plain "Save as CSV" in Excel produces on Windows. The fallback is a guess, and a wrong guess can silently corrupt names.
10. **Delimiter.** Default: comma only, like the export. Excel in some locales (DE/FR/RU) saves with `;`. Sniffing for that clashes with `;` being the tag separator, so I'd rather not do it. OK?

**Report details**
11. **Row numbering.** Default: `row` is the 1-based line number as a spreadsheet shows it. The header is row 1 and the first data row is row 2. File-level issues use `row=1`.
12. **`column` on an issue.** Default: the field from `ValidationError.field`; `None` for whole-row issues.
13. **Order of `created`/`updated`.** Default: file order.
14. **Size limits.** Should there be a maximum number of rows or bytes? Default: none, since the HTTP layer would enforce that. Say if you want a cap in core.

**Smaller points**
- Should `import_contacts`, `ImportReport` and `ImportFileError` also be exported from `contactbook/__init__.py`? Default: yes.
- Some of these choices, mainly 1/2 (update semantics) and 4 (partial vs atomic), are hard to reverse once sales relies on them. I'd record them in `docs/adr/0001-csv-import-semantics.md`. I'd also start `GLOSSARY.md` with the terms *import report*, *row issue*, *update*, *file error*.

The scope looks like one session: one module, an error class, tests and a spec at `specs/csv-import.md`.

### [build] user

1. Not defaults. Name: file value replaces ours. Phone: replaced only if the cell has a value. Tags: merge (union) with the existing ones; an import never removes tags.
2. Override: blank = leave unchanged. A blank phone cell or a missing phone column must never wipe an existing phone. Blank tags never remove tags.
3. Don't mind, your call.
4. Partial import, default OK. A bad row isn't applied at all, not even partly to an existing contact.
5. First wins, later rows are errors on that later row. Default OK.
6. Whole row is an error with column tags. Default OK.
7. Skip silently. This includes rows with only spaces or just commas. Default OK.
8. Mostly OK, with changes. Empty file or missing name/email header means ImportFileError. Name can instead be given as first_name + last_name columns, which are joined with one space. That is what our address-book export script writes. Undecodable bytes mean ImportFileError, with a message telling them to re-save as "CSV UTF-8". For unknown columns I don't mind a warning or silence, just never an error. I don't mind about malformed CSV.
9. UTF-8 with BOM stripped, no fallback to other encodings. The BOM must also be handled when the input is already text starting with the BOM character.
10. Comma only, OK.
11. Row number is as Excel shows it: header is row 1, first contact is row 2, and blank lines count in the numbering. File-level issues: your call.
12. Column should be the lower-case name: name, email, phone or tags. A name problem in a first_name/last_name file is also name.
13. Don't mind.
14. Yes, a cap: at most 1000 contact rows per file, not counting blank rows. A bigger file is rejected whole with ImportFileError and nothing is imported. A header-only file is fine and gives an empty report.

Other rules for the spec:
- Email is the identity. Normalise it with the existing email helper (trim and lower-case). A missing or invalid email is an error on that row. Created and updated list the normalised emails.
- Name is required on every row, also on updates, and is validated with the existing name helper.
- An invalid phone must not cost us the contact. Import or update the rest of the row, leave the phone as it was, and add a warning (not an error) with column phone.
- Tags are split on ; and each is normalised with the tag helper. Empty pieces and repeats are ignored.

Exports from __init__, the ADR, the glossary and specs/csv-import.md are all fine.

### [build] agent

The CSV import is built and the full test suite passes:

```
$ python3 -m pytest -q
84 passed in 0.03s
```

`import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError` follow the interface you gave and are also exported from `contactbook`. Your rules are implemented as stated: updates never clear a phone or remove tags, imports are partial, the first applied row wins, it's UTF-8 only with the BOM stripped, and there's a 1000-row cap.

**Files:**
- `specs/csv-import.md`: the spec, with your interface copied word for word, acceptance criteria, non-goals and scope.
- `src/contactbook/importer.py`: the import itself.
- `src/contactbook/errors.py` gains `ImportFileError`; `__init__.py` gains the exports.
- `tests/test_importer.py`: 43 tests, one or more per acceptance criterion.
- `docs/adr/0001-csv-import-semantics.md` records the decisions that are hard to undo: import only adds data, partial import, invalid phone is a warning, first row wins, UTF-8 only, the 1000-row cap.
- `GLOSSARY.md` is new and has the import terms.
- `README.md` lists the new module.

**Choices I made where you left it to me:**
- A row that changes nothing is left out of `updated`.
- File-level warnings (unknown columns) use `row=1`.
- If both `name` and `first_name`/`last_name` columns exist, `name` is used and the other two get a warning.
- A row reports all of its errors at once. Phone and extra-value warnings also appear on rows that were rejected, so they can be fixed in one pass.
- Malformed CSV raises `ImportFileError` with the line number. A single bad quote rejects the whole file, because a lenient parser would silently swallow the rest of the file after an unclosed quote.

**Checking and review:**
- The tests failed before the implementation existed. I also broke the update rules on purpose (clear phone, replace tags) and 5 tests caught it.
- A fresh reviewer checked the code against the spec and found no bugs. It found one conflict between two spec rules: a repeated `first_name` next to a `name` column raised an error. I made that a warning, since you said unknown columns should never cause errors.
- `/code-review` led to four more fixes, each with a test written first:
  - A blank first row now gets a clear "row 1 must be the header" error.
  - CSV errors name the line.
  - Values under a blank header cell now warn instead of disappearing silently.
  - Small cleanups.

**Not done:**
- Nothing is committed. Say if you want a commit or a branch.
- The repo has no `.gitignore`, so `__pycache__/` folders show up as untracked. I left that alone.
