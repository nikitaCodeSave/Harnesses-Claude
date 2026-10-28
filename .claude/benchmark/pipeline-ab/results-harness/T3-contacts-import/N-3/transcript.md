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

I've read the whole package. There's no `GLOSSARY.md`, `docs/adr/` or `specs/` yet, so nothing earlier constrains this. Your interface is fixed and I'll copy it into the spec word for word. The open questions are about behaviour. This is a parser that writes to the store, so I'd like your answers before I write `specs/csv-import.md`. Each question has my recommendation, so you can just answer "agree" or name the ones you'd change.

**What happens to existing contacts and to the file as a whole**

1. **Partial import or all-or-nothing?** If 3 of 200 rows are bad, are the other 197 imported?
   *Recommendation:* yes, import the good rows and list the bad ones in `errors`. The report's shape suggests this, and sales can fix the 3 rows and import again. That only works safely if importing the same file twice is harmless (see Q2).
2. **A row whose email already exists. What does "update" mean?**
   *Recommendation:* the row is the source of truth, the same as an edited export. Name, phone and tags are all replaced, so a blank phone cell clears the phone and the tags cell replaces the existing tags rather than adding to them. If the row matches what's already stored, it goes in neither `created` nor `updated`, which makes re-importing the same file a no-op. The other option is "fill in blanks only, merge tags". Tell me if sales expects that.
3. **The same email appears twice in one file** (after normalisation, e.g. `Ann@X.com` and `ann@x.com`)?
   *Recommendation:* the first occurrence wins. The later one is an error on its own row that points to the row it duplicates. I'd rather not have "last wins", because it hides conflicts.

**Errors and warnings**

4. **Which problems are row errors (row skipped) and which are warnings (row imported)?**
   *Recommendation:*
   - **Errors:** invalid or missing name or email, invalid phone, invalid tag. In each case the whole row is skipped and `column` names the field. I'd rather not quietly drop a bad tag and import the rest.
   - **Warnings:** unknown extra columns (one warning, `row` = header row, `column` = that header), and fully blank rows (skipped).
   - Is anything else you'd consider a warning?
5. **When does the whole file fail (`ImportFileError`, nothing imported)?**
   *Recommendation:*
   - empty file or no header
   - header missing `name` or `email`
   - a header column appears twice
   - bytes that aren't valid UTF-8
   - malformed CSV, e.g. an unclosed quote

   `phone` and `tags` columns are optional.

**What the file looks like**

6. **Encoding.** Excel's "CSV UTF-8" adds a BOM, and plain "CSV" on Windows saves as cp1252.
   *Recommendation:* accept UTF-8 with or without a BOM. Reject anything else with a clear `ImportFileError` ("save as CSV UTF-8"), and don't guess. Guessing cp1252 silently corrupts names.
7. **Delimiter.** Excel in German, French and similar locales saves with `;`, which is also our tag separator.
   *Recommendation:* comma only, as in our export. A file whose header doesn't split into known columns fails with a message that mentions the delimiter. Auto-detecting `;` is possible but makes the tags cell ambiguous. Do you need it?
8. **Header matching.** *Recommendation:* ignore case and surrounding whitespace (`Email ` matches `email`), and allow the columns in any order.
9. **Row numbers in `RowIssue.row`.** *Recommendation:* the spreadsheet row number, so the header is row 1 and the first data row is row 2, the number sales sees in Excel. A cell with an embedded newline still counts as one row. `column` is the canonical column name (`"email"`), or `None` for issues about the row as a whole.

**Scope**

10. **Limits.** Should there be a maximum file size or row count? *Recommendation:* none in this package, because the HTTP layer that receives uploads is the right place to enforce one.
11. **Non-goals I'd write down:**
    - no dry-run/preview mode
    - nothing ever gets deleted (contacts missing from the file stay)
    - no `ContactBook` method; `import_contacts` is the only entry point
    - no CSV-injection handling (that's an export concern)

    Should any of these be in scope?

Once you answer, I'll write the spec and an ADR for the update semantics in Q2, because the HTTP layer and later work will rely on them. I'll add the glossary terms, then build the importer with tests in this session. It fits one session.

### [build] user

1. Agree: partial import, good rows in, bad rows in errors and skipped. A bad row is not applied at all, not even partly to an existing contact.

2. Change this. An existing contact is updated, never duplicated, and it goes into `updated`. Name: the file's value replaces ours. Phone: replaced only when the cell has a value; an empty cell or a missing phone column must not wipe an existing phone. Tags: the file's tags are added to the existing ones; an import never removes tags. Whether an unchanged contact is listed in `updated` I don't mind.

3. Agree: first row wins, later rows with that email are errors on their own row and are not applied.

4. Change this. A bad phone is NOT a row error. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning for that row with column `phone`. Invalid or missing name, invalid or missing email, and invalid tag are row errors. Name is required on every row, also when updating an existing contact. Blank rows (empty lines, or cells all empty or spaces, like Excel's `,,,` lines) are skipped silently, with no warning. Unknown extra columns are ignored; I don't mind if you warn, just never an error.

5. Whole-file rejection: empty file, missing `email` or `name` column, invalid UTF-8. Also a file with more than 1000 contact rows (blank rows don't count). Reject it as a whole with nothing imported, so people split it rather than get a half-loaded file. A header-only file is fine and gives an empty report. Duplicate header columns and malformed CSV: I don't mind, do what you think is sensible.

   One addition: our address-book export script writes `first_name` and `last_name` columns instead of `name`. Accept that pair as the name column. The name is first and last joined with one space. A name problem in such a file has column `name`.

6. Agree on rejecting non-UTF-8 with a "re-save as CSV UTF-8" message. The BOM must work for bytes, and also for text input that still starts with the BOM character.

7. Comma only is fine.

8. Agree: case-insensitive, ignore spaces around the names, any column order.

9. Row numbers: header is row 1, first contact is row 2, and every line of the file counts, blank lines included. `column` is the lower-case column name: `name`, `email`, `phone` or `tags`. Multi-line quoted cells: I don't mind.

10. Change this. There is a limit of 1000 rows, see 5.

11. Non-goals are fine.

### [build] agent

The CSV import is built to your interface and rules, and the full test suite passes:

```
$ python3 -m pytest -q
79 passed in 0.03s
exit=0
```

Tests I broke the importer on purpose to confirm they catch mistakes.

**Files**
- `src/contactbook/importer.py`: `import_contacts`, `ImportReport` and `RowIssue`.
- `src/contactbook/errors.py`: `ImportFileError(ContactError)`, also exported from the package.
- `tests/test_importer.py`: 46 new tests.
- `specs/csv-import.md`: the spec, with your interface copied exactly.
- `docs/adr/0001-csv-import-merge-rules.md`: the update rules, partial import per row, and the 1000-row limit.
- `GLOSSARY.md`: new, with the import terms.

**Rules I chose where you said "I don't mind"** (each is marked "My call" in the spec):
- **Malformed CSV rejects the whole file**, for example a quote that is never closed. The message gives the line number. Python's CSV reader in its default mode silently swallows every row after an unclosed quote, so I switched it to strict mode.
- **A single cell over 131,072 characters rejects the whole file.** That's Python's built-in CSV limit, and raising it would change a setting for the whole process.
- **A column name repeated in the header rejects the file**, for example `email,Email`.
- **A row with more cells than the header is an error**, even if the extra cells are empty. The usual cause is an unquoted comma in a name. Without this rule, `Lee, Ann` could silently save a contact named "Lee".
- **A repeated email is an error even when the first row with that email was itself rejected.** The result then never depends on whether an earlier row was valid.
- **A row with errors reports all of them and gets no phone warning.**
- **A multi-line cell is reported at the line where its row starts.**
- **Unknown named columns get one warning each.** Unnamed header columns, like Excel's trailing `,,`, are ignored silently.
- **If a file has `name` as well as `first_name`/`last_name`, `name` is used** and the other two are ignored with a warning.

**Review**
- A fresh agent reviewed the change against the spec in two rounds. Round 1 found that the oversized-cell limit contradicted the spec, plus three test gaps; all are fixed. Round 2 found nothing.
- `/code-review` found the shifted-row case above, which I fixed with a failing test first. It also flagged the BOM written as an invisible raw character (now the `\ufeff` escape) and noisy warnings for unnamed columns (now silent).
- I declined five other `/code-review` suggestions. The main one is to drop strict mode, which I kept because the alternative loses rows silently. The others were moving the update rules into a shared helper, accepting `bytearray` input, and two small cleanups.

**Not done**
- Nothing is committed, since you didn't ask.
- The repo has no `.gitignore`, so `__pycache__/` folders show up as untracked files.
