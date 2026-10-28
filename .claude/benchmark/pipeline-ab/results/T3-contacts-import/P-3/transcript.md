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

The repo has no `GLOSSARY.md` or ADRs yet. I read all of `src/contactbook/`, so the questions below are based on what the code actually does: `export_csv` writes `name,email,phone,tags` with tags joined by `;`, `Contact.create` treats a blank phone as "no phone", and the repo is keyed by lower-cased email. These are the questions I can ask now. The answers will shape round 2, which will cover what an "unchanged" row is and what else counts as a warning.

---

❓ **Q1** - **Is a "lead" just a Contact?**: Sales calls these rows "leads", but contactbook only has `Contact`. If "lead" means something of its own (a status, or a stage before becoming a customer), we'd need a new concept, or at least an automatic `lead` tag on imported rows. If it's only Sales' word for "someone in my spreadsheet", the import creates plain Contacts and the glossary records "lead" as a synonym to avoid.

➡️ Yes. A lead is just a Contact. Import adds no extra tag, and "lead" goes in the glossary under _Avoid_.

---

❓ **Q2** - **Partial import, and the file is checked before anything is written?**: The report can hold `created` and `errors` together, which points to a partial import: valid rows are applied and bad rows are skipped and reported. The other option is all-or-nothing, where a single bad row means nothing is imported. Either way, I'd parse and check the **whole file before touching the repo**. That gives one simple rule: if `ImportFileError` is raised, the repo is unchanged.

➡️ Yes. Partial import: valid rows are applied and invalid rows are skipped and listed in `errors`. The whole file is parsed and checked first, so `ImportFileError` always means nothing was written.

---

❓ **Q3** - **What does "update" do to a Contact that already exists?**: The `updated` list means a row whose email is already in the repo updates that contact. The question is what happens to each field:
- **(a) Replace**: the row becomes the contact. A blank phone cell clears the stored phone, and the tags cell replaces all existing tags.
- **(b) Merge**: the name is overwritten. A blank phone cell keeps the stored phone and a non-blank one replaces it. Tags are **added** to the existing ones (an import never removes a tag).

Exporting and re-importing changes nothing under either option. The real difference is a Sales sheet where the phone is blank because nobody knows it. Under (a), that wipes phone numbers we already have.

➡️ Yes to (b), merge: overwrite the name, blank phone keeps the existing one, tags are added together.

---

❓ **Q4** - **The same email twice in one file?**: Two rows normalise to the same email, for example `Ann@x.com` on row 5 and `ann@x.com` on row 40. Options: the last row wins, the first wins, the two rows are merged, or the later row is an error.

➡️ Yes. The first row is applied. Each later row with the same email is an **error** on the `email` column ("duplicate of row 5") and is skipped. Results never depend on the order rows are processed, and no email shows up in both `created` and `updated`.

---

❓ **Q5** - **What does `RowIssue.row` count?**: Sales will open the file in Excel to find the problem, so `row` should match Excel's row numbers. That means the header is row 1 and the first data row is row 2. It counts CSV records, not physical lines, so a quoted cell with a line break inside it doesn't shift the numbers. Issues about the header itself (for example an ignored column) use `row=1`.

➡️ Yes. Excel-style numbering: header = 1, first data row = 2, counted by record.

---

❓ **Q6** - **Encodings for `bytes` input?**: Excel's "CSV UTF-8" adds a BOM. Excel's plain "CSV" on Windows saves as cp1252. Options:
- **(a)** Strict UTF-8, BOM stripped. Anything else raises `ImportFileError("file is not UTF-8; in Excel use Save As → CSV UTF-8")`.
- **(b)** Try UTF-8, then fall back to cp1252. This is friendlier, but cp1252 almost never fails to decode, so a wrong guess silently produces garbled names.

A BOM at the start of `str` input gets stripped too.

➡️ Yes to (a): strict UTF-8 with the BOM stripped, otherwise `ImportFileError` with a hint on how to re-save.

---

❓ **Q7** - **Comma delimiter only?**: Excel in many European locales saves "CSV" with `;` between columns. Our export already uses `;` **inside** the tags cell, so guessing the delimiter could mistake a tags cell for extra columns. Options: comma only, or detect `;`.

➡️ Yes, comma only. If the header turns out to be a single cell like `name;email;phone;tags`, raise `ImportFileError` saying the file looks semicolon-separated.

---

❓ **Q8** - **How strict is the header?**: "Same columns as our export." I suggest:
- A header row is required.
- Column names are matched ignoring case and surrounding spaces, in any order.
- `name` and `email` are required, otherwise `ImportFileError`. `phone` and `tags` may be missing (treated as blank).
- A header listed twice (e.g. two `email` columns) raises `ImportFileError`.
- Columns we don't know (`company`, `notes`, which Sales sheets will have) are **ignored**, with one warning each at `row=1, column=<header>`.

➡️ Yes, all five as listed.

---

❓ **Q9** - **What happens to a row with invalid values?**: For example, a row with a bad phone and a bad tag. `Contact.create` stops at the first problem. Options: report only the first problem, or check every field and report **all** of them, one `RowIssue` per field, with `column` set to the CSV column name. Either way the row is not imported. We do **not** import the contact without the bad field and add a warning instead: a half-imported contact is worse than a clear error.

➡️ Yes. Any invalid value makes the row an error and the row is not imported. Every bad field gets its own `RowIssue`, using the validator's message.

---

❓ **Q10** - **Separators in the tags cell?**: Export joins tags with `;`. People typing in a spreadsheet will write `vip, prospect`, which fails today because a comma isn't allowed in a tag. Tags can never contain `,` or `;`, so splitting on both loses nothing. Empty pieces (`vip;;prospect;`) are dropped.

➡️ Yes. Split tags on both `;` and `,`, trim each piece, and drop empty ones.

---

❓ **Q11** - **Blank rows and rows with too many or too few cells?**: Spreadsheets often end with blank rows, and hand-edited rows can be short or long.
- A row where every cell is blank is skipped silently and doesn't appear in the report.
- A short row: missing cells count as blank (so a missing `email` becomes the usual "email is required" error).
- A long row, with more cells than headers: the row is still imported, with a **warning** (`column=None`, "N extra cells ignored").

➡️ Yes, all three as listed.

---

❓ **Q12** - **Empty file or header only?**: A file with no bytes, or only whitespace, has no header, so `ImportFileError("file is empty")`. A header with no data rows is a valid file with nothing in it: return an empty report and raise no error.

➡️ Yes. Empty file → `ImportFileError`. Header only → empty `ImportReport`.

### [grill] user

Most of this is fine, but three answers need changes:

- **Q5:** Every line of the file counts toward the row number, blank lines included. The header is row 1, and a contact sitting after two blank lines gets the row number Excel shows. `column` is the lower-case column name: `name`, `email`, `phone` or `tags`.
- **Q8:** The address-book export writes `first_name` and `last_name` columns instead of `name`. Accept that pair as the name column, with the name being first and last joined by one space. Problems with it are reported under `name`. The other four points are fine.
- **Q9:** A bad phone must not cost us the contact. Import or update the rest of the row, leave the phone as it was (none for a new contact), and add a warning on `phone` instead of an error. An invalid tag or name is still an error and the row is skipped. A skipped row is not applied at all, not even partly to an existing contact.
- **Q10:** Split tags on `;` only. A comma in a tag is just an invalid tag, so that row is an error. Trimming, ignoring empty pieces and ignoring repeats are all fine.

I accept the rest as you proposed.

### [grill] agent

I applied all four of your changes: Q5, Q8, Q9 and Q10. I also created `GLOSSARY.md` with the terms settled so far: **Contact** (with "lead" listed under _Avoid_), **Export**, **Import**, **Import report**, **Row error** and **Row warning**. The definitions of row error and row warning follow your Q9 answer: a rejected row changes nothing, and a row with warnings is still imported.

Your changes open up some new questions:

---

❓ **Q13** - **Row numbers when a quoted cell spans several lines**: You said "every line counts" and also "the number Excel shows". These usually agree, but not always. A quoted cell with a line break inside it (a two-line address in `notes`, say) takes 2 lines of the file but is **one** row in Excel. Everything after it would be off by one under a pure line count. Options:
- **(a)** Count rows the way Excel does. Every row counts, blank ones included, and a multi-line cell is one row.
- **(b)** Count raw file lines, using the line where the row starts.

➡️ Yes to (a). Count rows as Excel does, blank rows included, multi-line cells counted once. This is the number Sales will look for.

---

❓ **Q14** - **Blank lines before the header**: If the file starts with blank lines, is the first non-blank row the header? Its number would then be the real position (for example 3), not 1. Or is a file whose first row isn't the header an `ImportFileError`?

➡️ Yes. The first non-blank row is the header, and all numbers stay the Excel row numbers, including the header's.

---

❓ **Q15** - **`column` for the "unknown column" warning**: You said `column` is always one of `name`/`email`/`phone`/`tags`. That leaves the warning for an ignored `company` column. I'd use `column=None`, with the header text as written in the message: `ignored unknown column "Company"`. The extra-cells warning also uses `column=None`.

➡️ Yes. `column=None` for unknown-column and extra-cells warnings. `column` is only ever one of the four names or `None`.

---

❓ **Q16** - **Combining `first_name` and `last_name`**: There are some edge cases:
- **Both `name` and `first_name`/`last_name` present** → `ImportFileError` ("name given twice"), the same as a duplicated header.
- **Only one of `first_name`/`last_name`** in the header → treated as a missing `name` column, so `ImportFileError`.
- **One cell blank** in a row (`first_name="Cher"`, `last_name=""`) → the name is `Cher`. Each part is trimmed and blank parts are left out, so there's no stray space.
- **Both blank** → row error on `name`, "is required".

Separately, "the address-book export" is a different file from our own Export, presumably from some outside address-book tool. I'll describe it in the docs as "a CSV with `first_name` and `last_name` instead of `name`" and won't add a glossary term for it. Is that right?

➡️ Yes to all four rules. And yes, no glossary term for the address-book export.

---

❓ **Q17** - **A bad phone in a row that's rejected anyway**: Take row 7 with a bad phone and a bad tag. The row is skipped, so nothing in it is imported. Is the phone problem then reported as a **row error**, next to the tag error? Or does it stay a **warning**?

➡️ Yes, report it as an error. A skipped row has only errors. Warnings only describe rows that were actually imported, which matches the glossary definitions, and Sales sees everything to fix on that row in one list.

---

❓ **Q18** - **Which problems reject a row**: Here's the full list, to confirm nothing is missing. A row is **rejected** if any of these are true: the email is missing or invalid, the name is missing or invalid, any tag is invalid (including one with a comma), or the email repeats an earlier row's. A bad phone is **the only** problem that still lets the row be imported (with a warning).

➡️ Yes, that's the full list.

---

❓ **Q19** - **Blank name when updating an existing contact**: With merge (Q3), a blank phone keeps the stored phone. Should a blank name keep the stored name too? Or is it "name is required" and the row is rejected, the same as for a new contact?

➡️ Yes, reject the row. A blank name is a row error even when updating. "Blank keeps the existing value" applies only to phone.

---

❓ **Q20** - **A repeated email whose first row was rejected**: Row 5 `ann@x.com` has a bad tag and is rejected. Row 40 `ann@x.com` is valid. Options:
- **(a)** Row 40 is still a duplicate error. The duplicate check looks at the file, not at what got imported, so both rows are lost until someone fixes the file.
- **(b)** Row 40 is imported, because row 5 never was.

(a) is predictable: whether a row counts as a duplicate never depends on errors elsewhere. (b) saves the contact, but fixing row 5 later would change which row wins.

➡️ Yes to (a). Duplicates are judged by email across the whole file, even if the first row was rejected.

---

❓ **Q21** - **A row that changes nothing**: The email already exists, and after merging, the contact is exactly what's stored. This covers re-importing an Export, or a row whose only difference was a bad phone. Does the email go in `updated`? Or in neither list?

➡️ Yes, neither list. `updated` means the contact actually changed, so re-importing an Export gives an empty report. No warning either.

### [grill] user

I accept all of these as you proposed (Q13 to Q21). None of them contradicts what I need, and on Q15, Q17, Q20 and Q21 I don't mind either way.

### [grill] agent

That covers every question we've worked through. Here is the full picture to confirm before anything gets built. One small question is still open; I've put it at the end.

**What import does**
- A lead is a Contact; "lead" is listed under _Avoid_ in `GLOSSARY.md`.
- Partial import. The whole file is read and checked before the repo is touched, so `ImportFileError` always means nothing was written.
- **Existing email → merge:** the name is overwritten. A blank phone keeps the stored phone and a valid one replaces it. Tags are added to the existing ones and never removed.
- `updated` lists only contacts that actually changed. A row that changes nothing appears in neither list, so re-importing an Export gives an empty report.

**What reads as a valid file** (otherwise `ImportFileError`)
- Strict UTF-8. A BOM is stripped from both bytes and str input. Otherwise the error says to re-save as "CSV UTF-8".
- Comma-separated only. A single-cell `name;email;…` header gets a "looks semicolon-separated" error.
- The first non-blank row is the header. Column names ignore case and surrounding spaces, and order doesn't matter.
- The header needs `email`, plus either `name` or both `first_name` and `last_name`. `phone` and `tags` are optional.
- Duplicate headers, or `name` alongside `first_name`/`last_name`, are an error.
- An empty file is an error. A header with no rows returns an empty report.

**Rows**
- `row` is the Excel row number. Blank rows count; a multi-line quoted cell counts once.
- `column` is always `name`, `email`, `phone`, `tags` or `None`.
- **Row errors** (row skipped, nothing applied):
  - email missing or invalid
  - name missing or invalid, including when updating
  - any invalid tag (a comma in a tag counts as invalid)
  - an email already used by an earlier row, even if that row was itself rejected
- Every problem in a rejected row is reported as an error, the phone included.
- **Row warnings** (row still imported):
  - an invalid phone: it's ignored and the existing phone kept, or none for a new contact
  - extra cells in a row (`column=None`)
  - an unknown header column, reported on row 1 with `column=None`
- Blank rows are skipped silently. Short rows count missing cells as blank.
- Tags are split on `;` only; each piece is trimmed, and empty pieces and repeats are dropped.
- With `first_name`/`last_name`, the name is the non-blank parts joined by one space. Problems are reported on `name`.

**Last question:**

❓ **Q22** - **No limit on file size or row count?**: Everything is held in memory, so a huge file could use a lot of memory. Options: no limit, or `ImportFileError` above some row count (e.g. 10,000).

➡️ Yes, no limit for now. The caller (the HTTP layer) controls how large an upload can be.

I'm not proposing any ADRs, because none of these decisions would be costly to reverse. The bad-phone-is-a-warning rule and the merge rules will be written down in the spec instead. Once you confirm Q22 and agree this summary is right, I'll write it up as `.scratch/csv-import/spec.md` and start building, test-first.

### [grill] user

Q22 is wrong. There is a limit: at most 1000 contact rows per file, and blank rows don't count towards it. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported, because I want people to split it rather than end up with a half-loaded file. A file with only the header is still fine and gives an empty report.

The rest of the summary matches what I want.

Please don't write the spec or start building yet. This stage is the interview only. I'll start the spec step myself.

### [grill] agent

Got it. Q22 is now: at most 1,000 contact rows per file, blank rows not counted. A larger file raises `ImportFileError` and nothing is imported. A file with only a header is still valid and returns an empty report. This fits the rule we already have, that `ImportFileError` means the repo is unchanged. I won't write the spec or build anything.

One detail of the limit is still open:

❓ **Q23** - **Rejected rows count towards the 1,000**: Take a file with 1,001 non-blank data rows, 5 of which would be row errors (bad email, a repeated email, and so on). I'd count every non-blank data row, whether or not it would be rejected. The limit is then a property of the file alone, and checking it doesn't depend on running the row checks first. The other option is to count only rows that would actually be imported.

➡️ Yes. Every non-blank data row counts. 1,000 is accepted and 1,001 raises `ImportFileError`.

If you agree, every question is settled and the interview is done. `GLOSSARY.md` is the only file I've changed; it's at the repo root and ready for your spec step.

### [to-spec] operator

/to-spec

### [to-spec] agent

Before I write the spec, I need you to confirm how the import will be tested, and to answer Q23, which is still open.

**Testing through one entry point:** every test calls `import_contacts(repo, data)` with a real `InMemoryContactRepository` and a CSV given as either `str` or `bytes`. Each test then checks the returned `ImportReport`, the contacts in the repo (looked up with `repo.find` / `repo.all()`), or that `ImportFileError` was raised and the repo is unchanged. That is the interface other code calls anyway, so it's the highest level we can test at.

There are no new test hooks and no separate tests for the internal steps (decoding, reading the header, checking each row). Those are tested only through what `import_contacts` returns. The tests follow the style of `tests/test_export.py` and `tests/test_service.py`: plain pytest functions with small CSVs written inline and exact assertions. One test exports some contacts and imports the result (re-importing an Export gives an empty report). Others use real UTF-8 with a BOM and cp1252 bytes to cover decoding.

**Q23 is still unanswered**: do rejected rows count toward the 1,000-row limit? Unless you say otherwise, the spec will use my recommendation: every non-blank data row counts, so 1,000 is accepted and 1,001 raises `ImportFileError`.

Once you confirm both, I'll write `.scratch/csv-import/spec.md` with `Status: ready-for-agent`.

### [to-spec] user

Both confirmed. The testing approach is fine: going through `import_contacts` with inline CSVs, as `str` and `bytes`. On Q23, I already agreed: every non-blank data row counts toward the limit, so 1000 is accepted and 1001 raises `ImportFileError`. Go ahead and write the spec.

### [to-spec] agent

The spec is written at `.scratch/csv-import/spec.md` with `Status: ready-for-agent`. It covers every decision from the interview, including the 1,000-row limit and its blank-row rule. It also has 56 user stories, the testing approach you confirmed (everything goes through `import_contacts`) and an out-of-scope list. The only other file I've changed is `GLOSSARY.md`. Nothing is built yet.

We never discussed the following points, so I filled them in myself. Each is a single line in the spec, so any of them is easy to change:
- **Wrong input type:** passing something that is neither `str` nor `bytes` to `import_contacts` raises a plain `TypeError`, not `ImportFileError`. This follows the rule in the errors module that programming mistakes aren't wrapped.
- **Broken CSV:** a file the CSV parser can't read at all, such as an unclosed quote, raises `ImportFileError`.
- **Several bad tags in one row:** they produce a single row error on `tags`, which names only the first bad tag. Reporting each bad tag separately would also be reasonable.
- **Duplicate check:** rows whose email is missing or invalid are left out of it.
- **Where the new error lives:** `ImportFileError` can be imported from the package itself, next to the other errors, and the README's file list gets a line for the importer module.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here's my proposed breakdown into tickets. Each one adds a behaviour you can see through `import_contacts` and ships with its own tests. I don't think any refactoring needs to happen first: the existing validators, `Contact` and the repository already provide what's needed.

1. **Import a clean file into an empty contactbook**
   - **Blocked by:** none.
   - **Delivers:**
     - The basic pieces exist: `import_contacts` with text input, `ImportReport`, `RowIssue`, and `ImportFileError`, which can be imported from the package and is listed in the README.
     - A valid file with the exact Export header creates Contacts, and `created` lists their emails in file order.
     - An empty file and a file missing the `name` or `email` column raise `ImportFileError`, and the repo stays unchanged. A header-only file returns an empty report.
2. **Merge rows into existing Contacts**
   - **Blocked by:** 1.
   - **Delivers:**
     - An email that already exists updates that Contact: the name is overwritten, a blank phone keeps the stored one, a filled-in phone replaces it, and tags are added.
     - The email goes in `updated` only if something actually changed, so exporting and re-importing gives an empty report.
3. **Reject invalid rows with row errors**
   - **Blocked by:** 1.
   - **Delivers:**
     - A missing or invalid email, name or tag rejects the row. Every bad field gets its own error with the right column, and valid rows are still imported.
     - A rejected row changes nothing.
     - Tags are split on `;` only, then trimmed, with empty pieces and repeats dropped. A comma in a tag counts as an invalid tag.
4. **A bad phone is a warning, not a lost Contact**
   - **Blocked by:** 2, 3.
   - **Delivers:**
     - A row that's valid apart from its phone is still imported, with a warning on `phone`. A new Contact gets no phone and an existing one keeps its stored phone.
     - In a row that is rejected anyway, the bad phone is reported as an error.
5. **Duplicate emails within a file**
   - **Blocked by:** 3.
   - **Delivers:**
     - Later rows with the same email as an earlier row are errors on `email` that name the first row.
     - This applies even when the first row was rejected. Rows with an invalid email are ignored by the duplicate check.
6. **Excel row numbers, blank rows, and short or long rows**
   - **Blocked by:** 3.
   - **Delivers:**
     - Row numbers match Excel: blank rows count, multi-line cells count once, and blank lines before the header are allowed.
     - Blank rows, including rows of only commas, are skipped without any report entry.
     - Short rows fill missing cells with blanks. Long rows are imported with a warning that has no column.
7. **Flexible headers and the first_name/last_name pair**
   - **Blocked by:** 3.
   - **Delivers:**
     - Headers are matched ignoring case, spaces and order. `phone` and `tags` are optional.
     - Unknown columns are ignored with a warning. A repeated column, or `name` together with `first_name`/`last_name`, raises `ImportFileError`.
     - `first_name` + `last_name` are joined into the name, and problems with them are reported under `name`.
8. **Bytes input and rejecting unreadable files**
   - **Blocked by:** 1.
   - **Delivers:**
     - UTF-8 bytes work, and a BOM is stripped from both bytes and text input.
     - A file that isn't UTF-8 (e.g. cp1252) is rejected with a hint to re-save it as "CSV UTF-8". So is a file that looks semicolon-separated, and a structurally broken CSV.
     - Every one of these rejections leaves the repo unchanged.
9. **The 1000-row limit**
   - **Blocked by:** 6.
   - **Delivers:**
     - Every non-blank data row counts toward the limit, including rejected ones; blank rows don't.
     - 1000 rows are accepted, 1001 are rejected as a whole, and a header-only file is still fine.

Three things I'd like your view on:
- **Size of the tickets:** the whole feature is one module of a few hundred lines, so these tickets are small. If you'd prefer fewer, I'd merge 4 into 2+3, 5 into 3, and 9 into 6, which leaves 6 tickets.
- **Blocking edges:** 9 depends on 6 only because the limit has to tell blank rows apart from the rest. If it makes sense for 9 to do that itself, it could depend on 1 instead.
- **Working in parallel:** 2, 3 and 8 can all start once 1 is done, and 5, 6 and 7 once 3 is done. They all change the same function, though, so if several agents work at once they'll keep getting merge conflicts. It may be simpler to do them one at a time in number order.

### [to-tickets] user

The breakdown matches what I want, and I don't see anything in it that contradicts my rules. I don't mind the ticket count, the blocking edges or the order of work, so go with your recommendation. One at a time in number order sounds sensible.

### [to-tickets] agent

I wrote the nine tickets to `.scratch/csv-import/issues/`, one file each, numbered 01–09. They're in dependency order, so number order is also the order to work them one at a time. Each is marked `Status: ready-for-agent`, lists the tickets it waits on, has acceptance criteria and points back to the matching section of `spec.md`.

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Import a clean file into an empty contactbook | — |
| 02 | Merge rows into existing Contacts | 01 |
| 03 | Reject invalid rows with row errors | 01 |
| 04 | A bad phone is a warning, not a lost Contact | 02, 03 |
| 05 | Duplicate emails within a file | 03 |
| 06 | Excel row numbers, blank rows, short/long rows | 03 |
| 07 | Flexible headers and the first_name/last_name pair | 03 |
| 08 | Bytes input and rejecting unreadable files | 01 |
| 09 | The 1000-row limit | 06 |

Two things the tickets leave to later steps on purpose:
- **01 accepts only text input.** Passing bytes is handled in 08.
- **03 numbers rows the simple way:** header is row 1, the first data row is row 2. Counting blank rows and multi-line cells so the numbers match Excel is handled in 06.

That way each ticket can be finished and checked on its own. No code has been written yet.

### [implement-spec] operator

/implement-spec .scratch/csv-import/spec.md

### [implement-spec] agent

CSV Import is built on the `csv-import` branch (tip `85880f7`), and all 91 tests pass. All nine tickets and the spec are marked `Status: resolved`, each with a comment saying where it was merged. Nothing has been pushed and no PR was opened, since this tracker closes work in the markdown files.

**What's there:** `import_contacts(repo, data)`, `ImportReport` and `RowIssue` are in the new `src/contactbook/importer.py`. `ImportFileError` derives from `ContactError` and can be imported from the package root, and the README layout lists the importer. The tests are in nine `tests/test_import*.py` files, one per area.

**Code review, two axes:**
- **Coding standards:** there were no violations of the repo's documented rules, only judgement calls. One agent fixed them all:
  - reused the tag separator and column names from `export.py`;
  - updated stale docstrings and renamed a few unclear helpers;
  - made the merge into an existing Contact use Contact's own methods;
  - cleaned up the tests (a duplicated test, helpers that had drifted apart, mixed imports, combined asserts) and added one test for a row of only commas before the header.
- **Spec:** nothing is missing and nothing extra was added. Four behaviours follow the spec as written but may not be what you want, so I left them unchanged for you to decide:
  1. **Blank extra cells:** a trailing-comma row like `Ann,a@x.com,,` still gets a "2 extra cells ignored" warning, though nothing was dropped.
  2. **Empty header cell:** a header such as `name,,email` warns `ignored unknown column ""`.
  3. **Semicolon file missed:** `name;email;"phone, mobile"` doesn't trigger the semicolon-separated message. The comma inside the quotes splits the header into two cells, so you get "missing required column" instead.
  4. **Bad phone on an unchanged Contact:** a row whose only difference from the stored Contact is a bad phone produces no update but still gets the phone warning. The spec says a row that changes nothing "produces no warning", while ticket 04 says the warning is still reported. I read the spec's line as meaning the unchanged row adds no warning of its own.

**Cleanup:** all agent worktrees are removed and their branches deleted; every one was fully merged. Only `main` and `csv-import` remain.

**History:** the first ticket's commit (`97810c8`) accidentally added `__pycache__` files. They aren't in the final tree, but they are still in the branch history. If you want a clean history, squash-merge `csv-import` into `main`, or add a `.gitignore` for `__pycache__` to stop it happening again.
