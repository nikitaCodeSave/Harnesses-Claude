### [grill] operator

/grill-with-docs Sales keeps leads in spreadsheets and wants to load a whole CSV file into contactbook
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

### [grill] agent

I've read the whole package (it's ~560 lines). Here are the facts I'm working from:

- Export writes the header `name,email,phone,tags`, uses `,` between columns and `\n` line endings, puts sorted tags in one cell joined by `;`, and leaves the cell empty when there's no phone (`export.py:11-33`).
- `Contact.create` checks and cleans every field, but it raises on the first bad field only. A blank phone means "no phone".
- The repo has no upsert. `add` raises `DuplicateContactError` and `update` raises `ContactNotFoundError`. Emails are compared case-insensitively.
- There's no `GLOSSARY.md` or `docs/adr/` yet. I'll create them when terms or decisions get settled.

Round 1. These questions don't depend on each other:

---

❓ **Q1** - **"Lead" is just a Contact**: Sales calls these rows "leads". Should an imported row simply become a **Contact**, with no new Lead concept? Today the domain has one entity, a person we keep in touch with, identified by email. The alternative is a Lead that gets converted into a Contact later, which would be a much bigger feature. If Sales wants to tell them apart, they can add a `lead` tag in the sheet.

➡️ Yes. Each row is a Contact, and the glossary will say "lead" is Sales jargon for a Contact, not a separate term.

---

❓ **Q2** - **Existing email = update, with the file as source of truth**: When a row's email already exists in the repo, it goes into `updated`. Should the row **replace** that contact's name, phone and tags with what's in the file? The alternative is a **merge**: tags are added, and a phone is filled in only if one is missing. With replace, export → edit in Excel → import gives you exactly what's in the sheet, and removing a tag in the sheet removes it from the contact. With merge, import can never remove anything.

➡️ Yes, replace. The row describes the whole contact.

---

❓ **Q3** - **Partial import**: If row 7 of 200 is invalid, should the other 199 still be imported, with row 7 skipped and listed in `errors`? The alternative is all-or-nothing: any row error means nothing changes. The report has `created` and `updated` next to `errors`, which suggests partial import.

➡️ Yes, partial. Valid rows are applied and invalid rows are skipped. "Error" means "this row was not imported". "Warning" means "imported, but look at this".

---

❓ **Q4** - **Same email twice in one file**: Suppose `ann@example.com` is on row 3 and again on row 9, maybe written differently (`Ann@Example.com `). Should the **first occurrence win**, with row 9 reported as an error ("duplicate of row 3") and not applied? The options are:
- (a) first wins, later ones are errors;
- (b) last wins, with a warning;
- (c) apply both in order.

Options (b) and (c) silently pick between two conflicting versions of the same person.

➡️ Yes, (a). An email appears in `created` or `updated` at most once.

---

❓ **Q5** - **What `RowIssue.row` counts**: Should `row` be the **spreadsheet row number**, so the header is row 1 and the first contact is row 2? That's what Sales sees in Excel. A cell with a line break inside quotes still counts as one row. Issues about the whole header, such as an unknown column, use `row=1`.

➡️ Yes. The header is row 1, and data rows are numbered the way Excel shows them.

---

❓ **Q6** - **Header rules**: Should columns be **matched by name**, ignoring case and surrounding spaces, in any order? Under this rule:
- `name` and `email` must be present, or `ImportFileError` is raised.
- `phone` and `tags` are optional.
- An unknown column such as `Company` is ignored, with one warning (`row=1`, `column="Company"`).
- A column name that appears twice raises `ImportFileError`.

➡️ Yes to all of the above.

---

❓ **Q7** - **Encoding of bytes input**: Should bytes be decoded as **UTF-8, with or without a BOM**? Excel's "CSV UTF-8" adds a BOM. If decoding fails, `ImportFileError` would tell the user to save as "CSV UTF-8". Plain "CSV" from Excel on Windows is cp1252. Falling back to cp1252 would never fail, but it can quietly garble names (`JosÃ©`). A leading BOM in `str` input would be stripped too.

➡️ Yes. UTF-8 only, the BOM is tolerated, and anything else raises `ImportFileError` with that hint.

---

❓ **Q8** - **Semicolon-separated files**: In German, French and similar locales, Excel saves "CSV" with `;` between columns. Our tags also use `;`. Such a file would parse as one column called `name;email;phone;tags`. Should we support **comma only**, and raise a specific `ImportFileError` ("columns look separated by ';', export as comma-separated") when the header looks like that? The alternative is to guess the delimiter, which is unreliable because `;` also appears inside tag cells.

➡️ Yes. Comma only, with a specific error for the semicolon case.

---

❓ **Q9** - **One issue per bad field**: If a row has a bad phone *and* a bad email, should it produce **two** `RowIssue`s, each with its own `column`? The alternative is one issue for the first problem, which is what `Contact.create` does on its own. Two issues means Sales fixes the row once instead of re-importing to find the next problem.

➡️ Yes. Each field is checked separately and there's one issue per bad column. `message` is `ValidationError.message`, without the field name.

---

❓ **Q10** - **Blank and ragged rows**:
- Rows where every cell is empty (Excel often leaves `,,,` at the end) are **skipped silently**.
- A row with **fewer** cells than the header treats the missing cells as empty.
- A row with **more** cells than the header is an error (`column=None`, "row has N cells, header has M") and isn't imported, because its cells are probably shifted.

Is that right?

➡️ Yes.

---

❓ **Q11** - **When the whole file fails**: Should `ImportFileError` cover these cases?
- the file is empty, or has no header;
- bad encoding (Q7) or the semicolon case (Q8);
- required columns are missing, or a column is duplicated (Q6);
- the CSV itself is broken, e.g. a quote that's never closed, using strict parsing.

A file with a header and no data rows would be fine and return an empty report. In all `ImportFileError` cases, **nothing** is written to the repo.

➡️ Yes.

---

❓ **Q12** - **Size limit**: Should there be **no row limit** for now? The repo is in memory and the HTTP layer can cap upload size. The alternative is a hard cap, such as 10,000 rows, that raises `ImportFileError`.

➡️ Yes, no limit in this module.

---

Round 2 will cover what an empty `phone` or `tags` cell means on an update, whether a row that matches the stored contact exactly counts as `updated`, and how to split the tags cell. Those answers depend on Q2 and Q3.

### [grill] user

Mostly agreed. Corrections:
- Q2: not a full replace. Name: the file's value replaces ours. Phone: replaced only when the cell has a value; an empty cell or a missing phone column never wipes an existing phone. Tags: the file's tags are added to the existing ones; an import never removes tags.
- Q5: every line of the file counts toward the row number, blank lines included (header = row 1, first contact = row 2). Blank rows (empty lines, or all cells empty/only spaces) are skipped silently with no error.
- Q12: there is a limit. At most 1000 contact rows per file (blank rows don't count). A bigger file is rejected as a whole with ImportFileError and nothing is imported; I want people to split files rather than half-load them. A header-only file is fine and gives an empty report.
- Q6: also accept first_name + last_name columns as the name column (that's what our address-book export script writes); the name is first and last joined with one space.

Q1, Q3, Q4 (later duplicate = error on that later row, not applied), Q7, Q8, Q9, Q10, Q11 are fine. I don't mind about duplicate header columns or the unknown-column warning. Go ahead with round 2.

### [grill] agent

I've created `GLOSSARY.md`. It records Contact (with "lead" listed under *Avoid*), Import, Row, Blank row, Created/Updated contact, Row error, Row warning, File error and Import report.

Settled so far:
- Updates merge rather than replace:
  - name: the file's value replaces ours;
  - phone: replaced only when the cell has a value;
  - tags: the file's tags are added, never removed.
- Partial import, and a later duplicate of an email is a row error.
- Rows are counted by line, and blank rows are skipped silently.
- The limit is 1000 contact rows, and a bigger file is a file error with nothing imported.
- `first_name` + `last_name` columns are accepted in place of `name`.
- UTF-8 only, comma delimiter only.

Round 2:

---

❓ **Q13** - **Quoted line breaks and row numbers**: A cell can contain a line break inside quotes, such as a multi-line note. Then one row takes up lines 5–6 of the file. Since every line counts, should that row be reported as **row 5** (the line it starts on), and the next row as row 7?

➡️ Yes. A row's number is the line it starts on.

---

❓ **Q14** - **What counts toward the 1000 limit**: Should every **non-blank data row** count, including rows that turn out to be invalid or duplicates? Exactly 1000 is accepted and 1001 is a file error. The whole file is checked before anything is written, so a file that's too big leaves the repo untouched.

➡️ Yes. The limit counts non-blank rows whatever their content. 1000 is fine and 1001 is rejected.

---

❓ **Q15** - **Name column combinations**: Suppose the header has `first_name` without `last_name`, or the reverse. Should that count as "no name column" and be a **file error**? The other option is to accept a single half. And if the header has **both** `name` and `first_name`/`last_name`, should that also be a file error ("use either name or first_name + last_name")? The alternative is to silently prefer one, when the two could disagree on every row.

➡️ Yes to both: both halves are required, and a mix of the two styles is a file error.

---

❓ **Q16** - **Half-empty first/last cells**: Should `first_name="Cher"` with an empty `last_name` give the name `Cher`, with no trailing space? And if both cells are empty, should that be a row error, the same as an empty `name`?

➡️ Yes. The two cells are trimmed, the non-empty parts are joined with one space, and if both are empty the result is "name is required".

---

❓ **Q17** - **What `RowIssue.column` holds**: Should `column` be the **Contact field** the problem is about (`"name"`, `"email"`, `"phone"`, `"tags"`), matching `ValidationError.field`? That also covers a name built from `first_name`/`last_name`, and a header written as `E-Mail`/`Email` in any case. `None` would mean the whole row, as for ragged rows. The column-level warnings you're indifferent about would carry the header text as written.

➡️ Yes. `column` is the Contact field name, or `None` for problems with the whole row.

---

❓ **Q18** - **Empty name on an existing contact**: The name always comes from the file. If a row's email matches an existing contact but the name cell is empty, should that be a **row error** that applies nothing to that contact, phone and tags included? The alternative is to keep the old name and merge the rest. Rows would then validate differently depending on what's already in the book.

➡️ Yes. Name is required on every row, and an error means nothing from that row is applied.

---

❓ **Q19** - **Reading the tags cell**: Should the cell be split on `;`, with each piece trimmed and empty pieces (`vip;;lead`, a trailing `;`) dropped silently? An invalid tag such as `c++` would be a **row error** (`column="tags"`) and the row wouldn't be imported. The alternative is to drop just that tag and record a warning.

➡️ Yes. Split on `;` and ignore empty pieces. An invalid tag is a row error.

---

❓ **Q20** - **Rows that change nothing**: Merging means a row can match an existing contact and change nothing. For example, the name is the same, the phone cell is empty, and the tags are already present. Should that email be **left out of `updated`**, so `updated` only lists contacts that actually changed? The alternative is to list every matched email in `updated`.

➡️ Yes. `updated` lists only contacts that really changed. Unchanged rows appear in neither list and produce no warning.

---

❓ **Q21** - **Duplicates of an invalid earlier row**: Row 3 has `ann@example.com` with a bad phone (a row error), and row 9 has `ann@example.com` and is valid. Should row 9 still be a duplicate row error ("same email as row 3")? The rule would be "the first row with this email claims it, valid or not". The alternative is that row 9 is imported because row 3 never was. Sales would then fix row 3, re-import, and get a different result.

➡️ Yes. The first row with an email claims it, whether or not that row was valid. If row 3's email is itself unreadable, it claims nothing.

---

❓ **Q22** - **Order of `created`/`updated`**: Should each list be in **file order**?

➡️ Yes.

---

❓ **Q23** - **Record the merge rule as an ADR?** "An import never removes a phone or tags" will surprise someone who expects export → edit → import to round-trip. It's also hard to change once Sales relies on it, and we rejected the replace option for a reason. Should I write `docs/adr/0001-import-merges-never-removes.md`? It would be one paragraph: why import adds and never removes.

➡️ Yes, and it should include the reason in your words: why removal is off the table for imports.

### [grill] user

All fine; I don't mind the details on Q13, Q15, Q20, Q21, Q22. Q14, Q16, Q17, Q18, Q19 match what I want. Q23: OK to write the ADR, but I have no deeper reason to give you than the rule itself: an import adds tags and never removes them, and never wipes a phone we already have. State it that way. Nothing more from me.

### [grill] agent

I wrote the ADR at `docs/adr/0001-import-merges-never-removes.md`. It states the rule as you gave it, plus the one consequence that follows from it: deleting a tag or phone in the spreadsheet has no effect on import. I didn't add a reason, since you said there isn't one beyond the rule.

Every question has an answer now. Where you didn't mind (Q13, Q15, Q20, Q21, Q22, duplicate header columns, the unknown-column warning), I've used my recommendation. Here's the full design; please confirm it before I start.

**File level** (any of these raises `ImportFileError` and nothing is written)
- An empty file, or a file with no header.
- Bytes input that isn't valid UTF-8; the message suggests saving as "CSV UTF-8". A BOM is accepted, in bytes or str.
- Columns separated by `;`, detected from the header, with its own message.
- A broken CSV, such as a quote that's never closed.
- No `email` column.
- No name column. Name comes from either `name` or `first_name` + `last_name`. Having just one of `first_name`/`last_name` is an error, and so is mixing `name` with them.
- A duplicate column.
- More than 1000 non-blank data rows. Invalid and duplicate rows count too; exactly 1000 is fine.
- A file with only a header returns an empty report.

**Header**
- Columns are matched by name, ignoring case and surrounding spaces, in any order.
- `phone` and `tags` are optional.
- An unknown column is ignored, with one warning (`row=1`, `column` = the header text as written).
- I'm assuming the header has to be line 1. If line 1 is blank, that counts as "no header" and raises a file error. Tell me if you'd rather leading blank lines were skipped.

**Rows**
- `row` is the line number in the file, with the header as row 1. Blank lines count toward the numbering. A row whose cell spans several lines takes the number of the line it starts on.
- Blank rows (no cells, or only empty or whitespace cells) are skipped silently.
- Missing trailing cells are treated as empty.
- A row with more cells than the header is a row error (`column=None`).
- Each field is checked separately, so a row gets one `RowIssue` per bad field. `column` is the Contact field (`name`/`email`/`phone`/`tags`) and `message` is the validator's message.
- A row with any error is not applied at all.
- Name: either the `name` cell, or `first_name` and `last_name` trimmed and joined with one space, skipping an empty half. An empty result is the error "name is required", including for existing contacts.
- Tags: the cell is split on `;`, and empty pieces are dropped. An invalid tag is a row error.
- Duplicates: the first row with a given email claims it, even if that row has an error. A later row with the same email is a row error (`column="email"`) and isn't applied.

**Applying**
- A new email creates a contact, and its email goes into `created`.
- An existing email is merged into that contact, per ADR-0001:
  - name: the file's value replaces ours;
  - phone: replaced only when the cell is non-empty;
  - tags: the file's tags are added.

  The email goes into `updated` only if the contact actually changed. A row that changes nothing appears in neither list and produces no warning.
- `created` and `updated` hold normalised emails, in file order.

**Code**
- New module `src/contactbook/importer.py` with `import_contacts`, `ImportReport` and `RowIssue`.
- `ImportFileError(ContactError)` added to `errors.py`.
- New tests in `tests/test_importer.py`.

Is this right? Once you confirm, I can write it up as `.scratch/csv-import/spec.md` or go straight to building it.

### [grill] user

Almost right, one correction: an invalid phone must NOT be a row error. The rest of the row is still imported/updated, the phone stays as it was (none for a new contact), and the row gets a *warning* with column="phone". Only name, email and tags problems make a row an error that isn't applied. Please state that explicitly in the design. Blank first line: I don't mind. Don't write the spec or start building; I'll run those steps myself next.

### [grill] agent

I've made the phone correction and updated ADR-0001 to match. It now says the phone is replaced only when the file gives a *valid* one, so an empty or invalid cell never wipes a stored phone. A blank first line stays a file error ("no header"). I haven't written the spec or any code.

**What counts as a row error and what as a warning**

Only **name, email and tags** problems are **row errors**. The row is not applied at all, and the issue goes into `errors`. That covers:
- an empty or too-long name;
- a missing or invalid email;
- an invalid tag;
- a duplicate of an earlier row's email;
- a row with more cells than the header.

An invalid **phone** is never a row error. It's a **warning** (`column="phone"`), and the rest of the row is still applied:
- **New contact:** created with no phone, and its email goes into `created`.
- **Existing contact:** name and tags are merged as usual and the stored phone stays as it was. The email goes into `updated` only if the name or tags actually changed.

**One case your correction opens up**

❓ **Q24** - **Bad phone on a row that fails anyway**: Say a row has an invalid email *and* an invalid phone, so it's a row error and nothing is applied. Should the phone problem still be reported as a **warning** (`column="phone"`) next to the email error, so Sales sees everything to fix in one pass? The alternatives are to report it as a second error, or to leave it out.

➡️ Yes. A phone problem is always a warning, whatever happens to the rest of the row.

Apart from Q24, the design is everything I listed last round plus this error/warning split.

### [to-spec] operator

/to-spec

### [to-spec] agent

I've written the spec to `.scratch/csv-import/spec.md` and marked it `ready-for-agent`.

**Testing seam:** there is one, `import_contacts(repo, data)`, the interface you specified. Tests call it with a real `InMemoryContactRepository` and check the returned report, the repository contents, or the raised `ImportFileError`. Internal parsing helpers aren't tested directly, and no other new seams are needed. The skill asks me to check seams with you before writing; I went ahead because this one is your own interface. Tell me if you expected a different one.

**Your phone correction** is spelled out in its own "Errors versus warnings" decision:
- Only name, email, tags, duplicate-email and too-many-cells problems are row errors, and they stop the row from being applied.
- An invalid phone is always a warning with `column="phone"`. The row is still imported, with no phone for a new contact or the stored phone kept for an existing one.

**Decision for you:** you never answered Q24, so I used my recommendation. If a row is rejected for another reason, a bad phone on it is still reported as a warning, so Sales sees everything to fix at once. The spec flags this under Further Notes. The alternatives are to report it as a second error or to leave it out.

**Other files touched:**
- **`GLOSSARY.md`:** I redefined "Row warning" to fit the phone rule. It's now something worth a look that doesn't by itself keep the row from being imported.
- **ADR-0001:** this now says the phone is replaced only when the file gives a *valid* one.

I haven't written any code.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here's my proposed breakdown of `.scratch/csv-import/spec.md` into tickets. I haven't published anything yet. The code needs no prefactoring, because each field already has its own validator.

---

**01 — Import new contacts from a well-formed file (tracer bullet)**
- **Blocked by:** None
- **What it delivers:** a correct file creates contacts and the import report lists them.
  - `import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError` exist, with `ImportFileError` exported from the package.
  - Input can be str or UTF-8 bytes, with or without a BOM.
  - Header columns are matched ignoring case and spaces, in any order, and `phone`/`tags` are optional.
  - Tags are split on `;`.
  - `created` holds normalised emails in file order.
  - A file with only a header gives an empty report.
  - These are file errors: an empty file, no header (including a blank first line), and a missing email or name column.
  - Round trip: output from the existing export imports into an empty repository and recreates the same contacts.

**02 — Row errors, phone warnings and row numbering**
- **Blocked by:** 01
- **What it delivers:** bad rows are reported and skipped, and the rest of the file still imports.
  - Each field is checked separately, so a row gets one issue per bad field, with `column` set to the Contact field.
  - Name, email and tag problems are row errors.
  - An invalid phone is a warning: the contact is created without a phone, and the warning also appears on rows rejected for other reasons.
  - Row numbers count every line, including blank ones, and a row with a quoted line break takes the number of its first line.
  - Blank rows are skipped silently.
  - Short rows treat missing cells as empty, and a row with too many cells is a row error.

**03 — Merge into existing contacts (ADR-0001)**
- **Blocked by:** 01, 02
- **What it delivers:** re-importing updates contacts that already exist.
  - The name is replaced.
  - The phone is replaced only by a valid non-empty value. An empty cell, an invalid cell or a missing column keeps the stored phone.
  - Tags are added to the existing ones.
  - `updated` lists only contacts that actually changed. A row that changes nothing appears in neither list.
- It's blocked by 02 only because one acceptance criterion needs 02's phone warning: an invalid phone on an existing contact keeps the stored phone. Without that criterion, 03 would depend on 01 alone.

**04 — Duplicate emails within one file**
- **Blocked by:** 02
- **What it delivers:** a later row with an email that's already been used is a row error naming the earlier row, and that later row isn't applied.
  - Emails are compared after normalisation.
  - The first row with an email claims it, even if that row is invalid.
  - A row whose email is unreadable claims nothing.

**05 — Clear file errors for wrongly saved files**
- **Blocked by:** 01
- **What it delivers:** a file saved the wrong way is rejected with a message that says how to fix it.
  - Bytes that aren't UTF-8 get the hint to save as "CSV UTF-8".
  - A semicolon-separated file gets the hint to export as comma-separated.
  - A broken CSV, such as an unterminated quote, is rejected.
  - A column named twice is rejected.
  - An unknown column produces a warning on row 1.
  - In every case the repository is unchanged.

**06 — 1000-row limit**
- **Blocked by:** 02
- **What it delivers:** a file with more than 1000 non-blank data rows is rejected before anything is written.
  - Exactly 1000 rows are accepted.
  - Blank rows don't count. Invalid and duplicate rows do.
- It's blocked by 02 because "blank rows don't count" uses 02's blank-row detection.

**07 — first_name + last_name columns**
- **Blocked by:** 02
- **What it delivers:** files from the address-book export script work.
  - The two cells are trimmed and joined with one space, leaving out an empty half.
  - If both are empty, that's the row error "name is required".
  - It's a file error if the header has only one of the pair, or mixes `name` with either.
- It's blocked by 02 because the "both empty" case is a row error.

---

Once 02 is done, tickets 03, 04, 06 and 07 can run in parallel, and 05 can run as soon as 01 is done. All of them edit the same importer module, so running them in parallel means merge conflicts but no logical dependencies. If you plan to run them one after another, top to bottom works.

Questions:
1. **Granularity:** is this the right size? I could merge 05 and 06 into a single "file errors" ticket, or fold 04 into 02.
2. **Blocking edges:** does 03 depending on 02 only for the invalid-phone case seem right? The other option is to move that criterion into 02, so that 03 depends only on 01.
3. **Merge or split:** should any other tickets be merged or split?

### [to-tickets] user

The breakdown matches what I want and nothing contradicts what I told you. I don't mind the granularity or the blocking edges, so go with your recommendation on all three questions. Publish the tickets as proposed.

### [to-tickets] agent

I've published the seven tickets in `.scratch/csv-import/issues/`, one file each, all marked `ready-for-agent`. They're as proposed, with your yes on my recommendations: no merges or splits, and 03 stays blocked by 01 and 02.

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Import new contacts from a well-formed file (tracer bullet) | None |
| 02 | Row errors, phone warnings and row numbering | 01 |
| 03 | Merge into existing contacts (ADR-0001) | 01, 02 |
| 04 | Duplicate emails within one file | 02 |
| 05 | Clear file errors for wrongly saved files | 01 |
| 06 | 1000-row limit | 02 |
| 07 | first_name + last_name columns | 02 |

01 is the only ticket that can start now. Once 01 is done, 02 and 05 can start; once 02 is done, so can 03, 04, 06 and 07. They all edit the same importer module, so tickets running side by side will hit merge conflicts.

Two small additions to the tickets:
- **07:** problems with a name built from `first_name`/`last_name` are reported with `column="name"`. That follows from the spec's rule that `column` is the Contact field.
- **04:** an email appears in `created` or `updated` at most once. This was in the spec but not in the breakdown summary.

The spec and ticket files, the glossary and the ADR are all written but uncommitted, and there's no code yet.

### [implement-spec] operator

/implement-spec .scratch/csv-import/spec.md

### [implement-spec] agent

The CSV import spec is fully implemented on the integration branch `csv-import` (tip `c790731`), and all 89 tests pass. All seven tickets are marked `Status: resolved` in `.scratch/csv-import/issues/`, each with a comment pointing at the branch. I didn't open a PR because the tracker is local files and you didn't ask for one. All the implementer worktrees and their merged branches are removed, so only `main` and `csv-import` remain.

**What's on the branch:**
- **Code:** `import_contacts`, `ImportReport` and `RowIssue` in the new `src/contactbook/importer.py`.
- **Error:** `ImportFileError` in `errors.py`, exported from the package.
- **Tests:** 65 importer tests in `tests/test_importer.py`.
- **Small refactor:** the code review found a duplicated phone helper. The implementer moved it out of `models.py` into `validation.py` as `normalize_optional_phone`, so `models.py` changed slightly too.

**Fixed after the code review:**
- **Too many cells:** a row with more cells than the header is still rejected, but now also reports its other bad fields, including a phone warning. It also claims its email, so a later row with the same email is flagged as a duplicate.
- **Blank header cells:** these are now ignored. Previously, two trailing blank cells, which Excel often writes, rejected the whole file as having a column named twice.
- **Header that is only spaces:** a first line containing only blank or whitespace cells is now a "no header" file error.
- **Tidying:** the review's style findings were applied, such as reusing the export's column list, seeding test contacts with `Contact.create`, and adding `importer.py` to the README.

**Decisions for you:**
1. **The spec contradicts itself.** An unchanged contact should produce "no warning", but a phone problem is "always a row warning". At the moment the phone warning wins: an identical row with a bad phone is in neither list but still gets a phone warning. I left this as is.
2. **I decided two things the spec doesn't cover:** blank header cells are ignored without a warning, and a row with too many cells still claims its email even though its cells may be shifted. Either is easy to change if you'd rather go the other way.

`.scratch/`, `GLOSSARY.md` and `docs/adr/` are still untracked and not on the branch. There's also no `.gitignore`, so `__pycache__/` folders show up in `git status`.
