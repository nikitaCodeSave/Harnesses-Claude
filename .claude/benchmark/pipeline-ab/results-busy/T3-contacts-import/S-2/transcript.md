### [spec+build] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [spec+build] agent

I've read the codebase: `Contact.create` handles validation, the repo is keyed by case-insensitive email, and the export writes `name,email,phone,tags` with `;`-joined tags. The 24 existing tests pass. Before I write the spec I need your decisions on the questions below. Each one has my recommendation, so you can just answer "agree" or change the ones you disagree with.

**1. Partial import or all-or-nothing?**
Suppose 3 rows out of 500 are bad. Do the other 497 get imported, with the 3 listed in `errors`? Or does any error mean nothing is written to the repo?
*Recommend:* import the good rows and report the bad ones. That's what having `created` and `errors` side by side in the report suggests. Is there a case where sales would want a dry run instead?

**2. What does an update do when the email already exists?**
- (a) Name: overwrite with the file's value?
- (b) Phone: if the file's phone cell is blank, does that clear the stored phone or keep it?
- (c) Tags: replace the stored tags with the file's tags, or add them to the existing ones?

*Recommend:* the file is the source of truth for the columns it contains. The name is overwritten, a blank phone clears the phone, and tags are replaced. That way, re-importing an edited export reproduces exactly what's in the file. The alternative is "blank means keep" plus adding tags, which is safer for sparse lead sheets but means you can never clear a phone or remove a tag through import.

**3. A row that matches an existing contact exactly (no changes).** Should it appear in `updated`, or nowhere?
*Recommend:* nowhere. `updated` should mean "something changed".

**4. The same email appears twice in one file** (e.g. `Ann@x.com` and `ann@x.com`).
*Recommend:* the first occurrence wins. Later ones become an error on that row, saying which row it duplicates. The alternative is "last one wins" with a warning.

**5. Header and columns**
- (a) Must `name` and `email` be present? If either is missing, raise `ImportFileError`.
- (b) Can `phone` and `tags` be left out? If so, treat them as blank.
- (c) Columns in any order, and header names matched case- and whitespace-insensitively (`Email `)?
- (d) Unknown extra columns (e.g. `company`) ignored with one warning (row = 1, column = that name)?
- (e) The same column name appearing twice → `ImportFileError`?

*Recommend:* yes to all five. One catch on (b): if phone/tags are missing, under the rule in Q2 an update would clear them. I'd instead say a missing column leaves that field untouched on update, and only a present-but-blank cell clears it. Agree?

**6. Encoding and format** (relevant when `data` is bytes)
- (a) UTF-8, with or without the BOM that Excel adds. Anything else (e.g. Windows-1252 from older Excel) → `ImportFileError`, or should I fall back to Windows-1252?
- (b) Delimiter: comma only, or also auto-detect `;`? European Excel saves "CSV" with semicolons.

*Recommend:* (a) accept UTF-8 with or without the BOM and reject anything else with a clear message. Silently guessing the encoding garbles names. (b) Comma only, matching our export. Tell me if sales is in a semicolon locale.

**7. Row numbering and what counts as an error vs. a warning**
- Row numbers match spreadsheet line numbers: the header is row 1, the first data row is row 2. For error and warning messages, should rows be numbered like the spreadsheet (as here), or by line in the raw file? The two differ when a cell contains a line break.
- **Errors** (row skipped): invalid or missing name, email or phone (`column` = that field), invalid tag, wrong number of cells (`column` = None), duplicate in file.
- **Warnings** (row still imported): blank lines skipped silently or with a warning? Empty tag segments like `vip;;lead` ignored with a warning?

*Recommend:* number rows like the spreadsheet, skip fully blank rows silently, and ignore empty tag segments without a warning.

**8. A file with no rows.** An empty file (no header) → `ImportFileError`. Header only → an empty report, not an error. Agree?

**9. Non-goals. Are these out of scope?**
- Deleting contacts that aren't in the file
- Size limits and streaming
- Formats other than CSV
- A CLI or HTTP endpoint (other packages handle that)
- Adding import to `ContactBook`

Is anything missing?

### [spec+build] user

1. Agree: good rows go in, bad rows are reported and skipped. A bad row isn't applied at all, not even partly to an existing contact. No dry run needed.

2. I disagree with your recommendation.
(a) Yes, the file's name replaces ours.
(b) A blank phone cell never clears a stored phone. The phone is replaced only when the cell has a value.
(c) Tags from the file are added to the existing ones. An import never removes tags.
A missing phone or tags column leaves those fields untouched.

3. I don't mind. Use your recommendation.

4. Agree: the first row wins. Every later row with that email is an error on that later row and isn't applied.

5. (a) Yes. The alternative to name is a first_name + last_name pair, which our address-book export uses. Treat that pair as the name column and join the two with one space.
(b) Yes.
(c) Yes.
(d) Ignore extra columns. A warning is fine, but never an error.
(e) I don't mind. Use your recommendation.

6. (a) Agree on UTF-8 with or without a BOM. This must also work for text input that still starts with the BOM character. Bytes that aren't valid UTF-8 give ImportFileError telling them to re-save as "CSV UTF-8". Don't fall back to Windows-1252.
(b) Comma only.

7. Row numbers are the spreadsheet row numbers. The header is row 1, the first contact is row 2, and every line of the file counts, blank lines included. I don't mind how a quoted multi-line cell is numbered.
Blank rows are skipped silently. This covers empty lines and rows where every cell is empty or only spaces, like Excel's ,,, lines.
The column value is the lower-case name: name, email, phone or tags. A name problem in a first_name/last_name file is name too.
Email: use the existing email helper to trim and lower-case it. A missing or invalid email is an error.
Name: required on every row, including updates. An empty name is an error. Validate it with the existing name helper.
Phone: an invalid phone is not an error. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning with column phone.
Tags: split the tags cell on ;. Empty pieces and repeats are ignored silently. An invalid tag makes the row an error.
I don't mind what happens to rows with more or fewer cells than the header.

8. Agree: an empty file is ImportFileError, and a header-only file gives an empty report. A missing required column is also ImportFileError, and nothing is imported.

9. Size limits are in scope. A file has at most 1000 contact rows, not counting blank rows. A bigger file is rejected as a whole with ImportFileError and nothing is imported. Streaming is not needed. The other non-goals are fine.

### [spec+build] agent

The CSV import is built and the full test suite passes. The spec is in `SPEC.md`, the importer is in `src/contactbook/importer.py`, and the new tests are in `tests/test_importer.py`.

```
$ python3 -m pytest -q
........................................................................ [ 85%]
............                                                             [100%]
84 passed in 0.03s
```

That is the 24 existing tests plus 60 new ones. Each new test names the spec criteria it covers (1–36), and every criterion has at least one test. To check the tests actually catch mistakes, I temporarily removed the handling for text that starts with the BOM character; the test for that failed, and it passed again once I restored it.

**Other changes:**
- `ImportFileError` is added to `errors.py`, as you specified, and is also exported from `contactbook/__init__.py`.
- I added one line for `importer.py` to the README's file list.

**Decisions I made on points you hadn't settled.** They are listed in the spec's "Decisions" section and are easy to change:
- **`name` and `first_name`/`last_name` both present:** `name` wins and the pair is ignored like any extra column.
- **Rows with the wrong number of cells:** missing cells count as blank and extra cells are ignored.
- **Several problems in one row:** each bad field gets its own error. The invalid-phone warning only appears when the row is actually imported.
- **Duplicate emails in one file:** the first row with an email claims it even if that row was rejected for another reason, so all later rows with that email are errors. This is the literal reading of "first row wins".
- **Bad quoting rejects the whole file** (added to criterion 9). An unclosed quote would otherwise quietly swallow the rest of the file into one cell. The catch is that hand-typed quoting like `"Ann" Lee,…` without proper escaping also fails the whole file. Files saved by Excel quote correctly, so they aren't affected.

Nothing is committed yet. Running the tests also left untracked `__pycache__/` folders, because the repo has no `.gitignore`.
