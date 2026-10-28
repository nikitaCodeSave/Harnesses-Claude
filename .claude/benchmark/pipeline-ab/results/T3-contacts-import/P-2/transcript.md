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

I've read the whole package (`models`, `validation`, `repository`, `service`, `export`, `errors`). There's no `GLOSSARY.md` or `docs/adr/` yet. I'll create them only when a term or decision is settled.

Some facts that shape the questions below:
- The export writes `name,email,phone,tags`, comma-delimited, with a header row. Tags are joined with `;` inside one cell, and a missing phone is written as an empty cell.
- `Contact.create` stops at the first invalid field, and name and email are required. The repository has separate `add` (fails if the email already exists) and `update` (fails if it doesn't) methods, with emails compared case-insensitively.
- `ImportReport.updated` exists, so importing a contact that's already in the repo is expected to update it rather than fail.

## Round 1

❓ **Q1** - **"Lead" vs "Contact"**: Sales calls these rows "leads", but the code only knows `Contact`. Is a lead just a Contact, with no new concept, no status, and nothing that marks it as imported? If sales wants to tell them apart, they can put a `lead` tag in the tags column. Otherwise, a lead could become its own concept, for example something that gets "converted" into a contact later.

➡️ Yes. Each imported row becomes a plain **Contact**. The glossary will treat "lead" as a sales word for a contact, not a separate term.

---

❓ **Q2** - **What an update does to an existing contact**: Ann exists with phone `+15551234567` and tags `{vip}`. The file has the row `Ann Lee,ann@example.com,,lead`. After the import, what does Ann look like?

- (a) **Replace**: the row is the contact's full new state. Phone is cleared and tags become `{lead}`. This round-trips exactly with the export.
- (b) **Merge**: non-blank cells overwrite, blank cells leave the stored value alone, and tags are added, never removed. Phone stays and tags become `{vip, lead}`.

➡️ (b) Merge. These files come from sales spreadsheets, not our own export, and with (a) a half-filled sheet would quietly erase phones and tags we already have. Clearing a phone or removing a tag stays a deliberate one-at-a-time action.

---

❓ **Q3** - **Partial import vs all-or-nothing**: If 3 rows out of 500 are invalid, do the 497 good rows still get saved, with the 3 reported as errors? The alternative is to save nothing whenever any row has an error.

➡️ Yes, partial. Invalid rows are skipped and reported, and valid rows are saved. Sales fixes the 3 rows and re-imports, and because updates merge (Q2), importing the same file again is harmless. `ImportFileError` (nothing saved) is only for problems with the file as a whole.

---

❓ **Q4** - **Same email twice in one file**: Rows 7 and 42 are both `ann@example.com`, maybe with different capitalisation. Is row 7 imported and row 42 reported as an error ("duplicate of row 7"), with row 42 not applied?

- The alternatives are "last row wins" or "merge both rows in order".

➡️ Yes. The first row wins and later duplicates are errors that name the earlier row. A duplicate inside one sheet is almost always a copy-paste mistake, and silently picking one hides it.

---

❓ **Q5** - **Header and columns**: Does the first row have to be a header, with columns matched **by name**? Matching would ignore case and surrounding spaces, so `Email` matches `email`, and column order wouldn't matter. In detail:

- If the `name` or `email` column is missing, that's an `ImportFileError`.
- `phone` and `tags` columns are optional. If one is missing, the file is treated as if that column were blank in every row.
- Unknown columns (e.g. `Company`, `Notes`) are ignored, with one warning per column on row 1.
- If the same column name appears twice, that's an `ImportFileError`.
- An empty file (no header) is an `ImportFileError`. A file with only a header imports nothing and reports nothing.

➡️ Yes, all of the above. Spreadsheets get columns added and reordered all the time, but a file without name or email can't be imported at all.

---

❓ **Q6** - **Encoding and delimiter**: Excel's plain "CSV" save uses Windows-1252 on Windows, "CSV UTF-8" adds a BOM, and some European locales save with `;` as the delimiter. Should the import work like this?

- Bytes are decoded as UTF-8, with any BOM stripped. If they aren't valid UTF-8, raise `ImportFileError` with a hint to save as "CSV UTF-8". There is no guessing at Windows-1252.
- A BOM at the start of a `str` input is stripped too.
- The delimiter is always a comma, never auto-detected, because `;` already separates tags inside a cell. If the header turns out to be a single column containing `;`, raise `ImportFileError` saying the file looks semicolon-separated.

➡️ Yes. A Windows-1252 fallback would usually "work" but can store garbled names like `JosÃ©` without anyone noticing. A clear rejection is better.

---

❓ **Q7** - **What `RowIssue.row` counts**: Should it be the spreadsheet row number, with the header as row 1 and the first data row as row 2? It would count CSV records, not text lines, so a quoted cell containing a line break doesn't shift the numbers. That way it matches what sales sees in Excel.

➡️ Yes.

---

❓ **Q8** - **Errors per invalid row**: If a row has a bad email *and* a bad phone, should the report have one `RowIssue` per bad cell, each with its `column` set? The alternative is stopping at the first bad cell, the way `Contact.create` does.

➡️ Yes, one issue per bad cell. Sales can then fix the whole row in one go. A row is still saved fully or not at all: any error means the whole row is skipped, including when just one of its tags is invalid.

---

Answer by number. A bare "yes" accepts my recommendation. Your answers decide the next round: how blank and identical updates are handled, which cases count as warnings, and how to treat blank and ragged rows.

### [grill] user

1. Yes, a lead is just a plain Contact.
2. Yes, merge. To be precise: the name from the file replaces ours, a phone is replaced only when the cell has a value, and tags are only added.
3. Yes, partial import.
4. Yes, the first row wins and later duplicates are errors on the later row.
5. Mostly yes, with one addition. The name can also come from `first_name` and `last_name` columns instead of `name`. Our address-book export from Outlook and Google Contacts writes those two columns. Accept the pair as the name column, and the name is first and last joined with one space. Errors for it still use the column `name`. The duplicate-column rejection is fine with me, and so is warning about unknown columns.
6. Yes.
7. Yes, with one point: blank lines count in the numbering. Row 1 is the header and every line after it counts, so a contact after a blank line keeps the number Excel shows. Blank rows themselves are skipped silently, with no error or warning. Rows with only spaces or `,,,` are skipped the same way.
8. Yes, one issue per bad cell, with one correction. A bad phone is not an error. The contact is still imported or updated with the rest of the row, the phone is left as it was (none for a new contact), and the row gets a warning with column `phone`. Only a bad email, name or tag makes the row an error and skips it.

### [grill] agent

All of Round 1 is settled. I created `GLOSSARY.md` with **Contact** ("lead" is listed as a word to avoid), **Import**, **Row**, **Row error**, **Row warning** and **File error**. It defines only the words, not implementation details.

## Round 2

❓ **Q9** - **`name` together with `first_name`/`last_name`**: What if a header has `name` *and* `first_name`/`last_name`? Or only `first_name` with no `last_name` and no `name`? Is each of these an `ImportFileError`? The first case would be rejected like a duplicate column ("name given twice"). The second would be rejected as "name column missing".

➡️ Yes, both are file errors. It isn't clear which name sales meant, and the mistake shows up on every row anyway.

---

❓ **Q10** - **Exact header names for the pair**: You said the Outlook and Google Contacts export writes `first_name`/`last_name`. Outlook's own CSV export and Google's actually write `First Name`/`Last Name`, and their email column is `E-mail Address` / `E-mail 1 - Value`. If those files were imported directly, the email column wouldn't match either. Is the file you mean an internal address-book export that already uses our snake_case names? If so, should matching stay exact (trimmed and case-insensitive), so `First Name` counts as an unknown column?

➡️ Yes, match exactly. Supporting real Outlook/Google files would need an alias table for email and phone too, which is a separate feature.

---

❓ **Q11** - **Half-filled names**: With the pair, should `first_name=""` and `last_name="Lee"` give the name `Lee`? That means joining only the non-blank parts. If both are blank, the row gets a row error with column `name` ("is required").

➡️ Yes. Otherwise a lone surname would end up stored as `" Lee"`.

---

❓ **Q12** - **Blank name on an update**: Ann exists and the row is `,ann@example.com,+1555…,`. You said the file's name replaces ours. Is a blank name a row error ("name is required") even though Ann already has a name? The other option would be to keep her stored name.

➡️ Yes, it's a row error. Every row needs a name, the same as adding a contact by hand. That keeps it simple: the name is always replaced, never merged.

---

❓ **Q13** - **Updates that change nothing**: Re-importing yesterday's file matches 500 existing contacts and changes none of them. Should all 500 still appear in `updated`? Under that rule, every row that's applied goes into exactly one of `created` or `updated`. The alternative is to list only contacts that actually changed. Unchanged rows would then show up nowhere in the report, because the interface has no third list.

➡️ Yes, list them all. "Updated" then means "an existing contact was matched and the row was applied". Every row that wasn't skipped can be found in the report.

---

❓ **Q14** - **Which row claims a duplicated email**: Row 7 is `,ann@example.com,,` (blank name, so a row error), and row 42 is a valid row for `ann@example.com`. Is row 42 still an error ("duplicate of row 7")? Under this rule, the first row whose email is *valid* claims it, whether or not that row is skipped for another reason. A row whose email is itself invalid claims nothing.

➡️ Yes. Then the result doesn't depend on which other cells happen to be broken. When sales fixes row 7 and re-imports, row 42 is still caught as a copy-paste duplicate.

---

❓ **Q15** - **Bad phone on a row that's skipped anyway**: Row 9 has a bad email *and* a bad phone. Is the phone problem still reported as a warning (column `phone`) next to the email error, so sales can fix both in one go? The alternative is to report only the email error.

➡️ Yes. A phone problem always goes to `warnings`, whatever happens to the rest of the row.

---

❓ **Q16** - **Ragged rows**: Should a row with *fewer* cells than the header be treated as if the missing cells were blank, with no warning? Some tools leave off trailing empty cells. And should a row with *more* cells than the header be imported with the extra cells ignored, plus a warning with `column=None`?

➡️ Yes to both.

---

❓ **Q17** - **Tag separators**: The export joins tags with `;`, but sales will type `vip, lead` by hand. A comma can't appear in a valid tag, so should both `;` and `,` split tags, ignoring empty pieces (`vip;;lead;` is fine)? If only `;` splits, then `vip, lead` is one invalid tag and the whole row becomes a row error.

➡️ Yes, split on both. It can't be ambiguous, and it saves pointless row errors.

---

❓ **Q18** - **Normalising values without telling anyone**: `Key Account` is stored as the tag `key-account`, `Ann@Example.COM` as `ann@example.com`, and `"Ann   Lee"` as `Ann Lee`. Should all of these happen without a warning? That's how adding a contact by hand already works.

➡️ Yes. A warning every time we tidy capitalisation or spacing would bury the warnings that matter.

---

❓ **Q19** - **Report order and public names**: Should `created` and `updated` follow the file order, and `errors` and `warnings` be sorted by row and then by column order in the header? And should `import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError` be exported from `contactbook/__init__.py`, with no new method on `ContactBook`?

➡️ Yes to both.

---

❓ **Q20** - **ADR for merge-on-import**: This one decision meets all three criteria for an ADR. An import is *not* the inverse of an export: a blank phone doesn't clear the stored phone, and missing tags aren't removed. Someone will eventually "fix" that so the export round-trips. Should I record it as `docs/adr/0001-import-merges-into-existing-contacts.md`?

➡️ Yes. The other decisions are either obvious or easy to change, so they don't need ADRs.

### [grill] user

Answers by number:

9. I don't mind. Take your recommendation.
10. Yes, match exactly. I don't mind how other header spellings are handled.
11. Yes, join only the non-blank parts. Both blank is a row error on `name`.
12. Yes, a blank name is a row error, including when the row updates an existing contact.
13. I don't mind. List them all, as you suggest.
14. I don't mind. Take your recommendation.
15. I don't mind. Take your recommendation.
16. I don't mind. Take your recommendation.
17. No, I disagree. Tags are separated by `;` only, as in our export. Don't split on commas. A tag that isn't valid makes the row an error, as I said before.
18. Yes, no warnings for tidying.
19. I don't mind the ordering. The four names in `contactbook/__init__.py` are fine, and so is leaving `ContactBook` alone.
20. Yes, go ahead with the ADR.

### [grill] agent

I wrote the ADR at `docs/adr/0001-import-merges-into-existing-contacts.md`. I've noted your Q17 answer: tags are separated by `;` only, and an invalid tag makes the row an error.

Three small questions are left. Two follow from Q17 and Q5, and the third is the one thing I haven't asked about at all.

## Round 3

❓ **Q21** - **Empty pieces in a tags cell**: Now that only `;` separates tags, what should happen with a cell like `vip;lead;` (trailing `;`), `vip;;lead`, or `vip; lead`? Should pieces be trimmed and empty pieces ignored, giving `{vip, lead}` in all three cases? Without that, each empty piece would count as an invalid empty tag and make the row an error. Our export never writes empty pieces, but people often type a trailing `;`.

➡️ Yes, trim the pieces and ignore empty ones. An empty piece isn't a tag that's wrong; it just isn't a tag.

---

❓ **Q22** - **Header cells with no name**: Spreadsheets sometimes save a header like `name,email,phone,tags,,`. Should a header cell that's blank count as an unknown column, so the data under it is ignored with a warning on row 1 (e.g. "column 5 has no name and was ignored")? Or should blank header cells be ignored silently?

➡️ Yes, give a warning. Ignoring them silently could throw away data someone typed under a column with no heading.

---

❓ **Q23** - **Size limit**: Should there be no limit on the number of rows or the file size? The caller passes the whole file in memory anyway, and the HTTP layer can limit upload size.

➡️ Yes, no limit inside contactbook.

---

Once these are answered I think every branch has been covered. Then I'll write up the full spec, and if you'd like I can put it in `.scratch/csv-import/spec.md`. I won't start building until you've confirmed we agree on everything.

### [grill] user

Q21: yes, trim the pieces and ignore empty ones. Repeated tags are ignored too.

Q22: I don't mind. Warning or silent, either is fine, as long as it's never an error.

Q23: no, there is a limit. A file may have at most 1000 contact rows. Blank rows don't count towards the 1000. A bigger file is rejected as a whole with `ImportFileError` and nothing is imported, so people split it instead of ending up with a half-loaded file. A file with only the header is fine: nothing happens and the report is empty.

I'll start on the spec myself in the next step, so don't write it now.

### [grill] agent

I think every part of the design is now covered. Here is the complete picture so you can confirm we agree. I haven't written the spec and won't until you say so.

**Shared understanding**

- **Terms:** a lead is just a **Contact**. An **Import** loads a spreadsheet, where each **Row** creates or updates a contact. The report has **Row errors** (row skipped), **Row warnings** (row still imported), and a **File error** (`ImportFileError`, nothing imported). These are all in `GLOSSARY.md`.
- **File level:**
  - Bytes are decoded as UTF-8 and a BOM is stripped; anything else is rejected with a hint to save as "CSV UTF-8". A BOM on `str` input is stripped too.
  - The delimiter is always a comma. If the header looks semicolon-separated, the file is rejected.
  - **File errors:** an empty file; a missing name column (neither `name` nor both `first_name` and `last_name`); a missing `email` column; a duplicate column, which includes `name` together with the pair; and **more than 1000 non-blank data rows** (exactly 1000 is allowed).
  - A file with only a header is fine and gives an empty report.
- **Columns:**
  - Matched by name, trimmed and case-insensitive, in any order. `phone` and `tags` are optional.
  - With `first_name`/`last_name`, the name is the non-blank parts joined with one space, and any issue with it is reported on column `name`.
  - Unknown columns get a warning on row 1. Header cells with no name are never an error (I'll give a warning).
- **Rows:**
  - Numbered as in the spreadsheet: the header is row 1, and blank lines still count. Blank, whitespace-only and `,,,` rows are skipped silently.
  - Short rows are padded with blanks. Long rows are imported with the extra cells ignored and a warning with `column=None`.
- **Errors (row skipped), one per bad cell:** a blank or invalid name, a blank or invalid email, or any invalid tag.
  - Tags are split on `;` only, then trimmed. Empty pieces and repeated tags are ignored.
  - If the same email appears again, the first row with that valid email claims it. Every later row with it is an error ("duplicate of row N"), even when the first row was skipped.
- **Bad phone:** always a warning, never an error. A new contact is created without a phone, and an existing contact keeps its phone. This applies even when the row is skipped for other reasons.
- **Merge (ADR-0001):**
  - The file's name always replaces the stored one. The phone is replaced only when the cell has a valid value. Tags are only added.
  - Every applied row goes into `created` or `updated` (normalised emails), even when nothing changed. Tidying values (capitalisation, spacing) never produces a warning.
- **API:** the interface you specified. `import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError` are exported from `contactbook/__init__.py`, and `ContactBook` is unchanged.

**One thing to confirm about the limit:** I'm reading "contact rows" as *every non-blank row after the header*, including rows that would end up as errors or duplicates. That way the check happens before any row is validated, and the result doesn't depend on how many rows are broken. Is that right?

If so, we have a shared understanding and you can start the spec. The files from this session are `GLOSSARY.md` and `docs/adr/0001-import-merges-into-existing-contacts.md`. Nothing has been committed yet.

### [grill] user

Yes, that reading of the limit is right. Every non-blank row after the header counts toward the 1000, including rows that turn out to be errors or duplicates. Blank rows don't count. The rest of your summary matches what I want.

### [grill] agent

Confirmed: every non-blank row after the header counts toward the 1000, including rows that end up as errors or duplicates, and blank rows don't count. That settles the last question, so nothing in the design is left open.

From this session there are two new files. Neither is committed:
- `GLOSSARY.md`: defines **Contact** ("lead" is listed as a word to avoid), **Import**, **Row**, **Row error**, **Row warning** and **File error**.
- `docs/adr/0001-import-merges-into-existing-contacts.md`: records that an import merges into existing contacts and is deliberately not the reverse of the export.

The rest of the decisions are in my summary above and haven't been written down anywhere else yet, so you can copy them into your spec. I haven't touched any code.

### [to-spec] operator

/to-spec

### [to-spec] agent

Before I write the spec, I'd like to check the testing approach with you.

**Proposed test seam: just one, `import_contacts(repo, data)`.**

- **Setup:** each test builds an `InMemoryContactRepository`, using `Contact.create` for any contacts that should already exist. It then calls `import_contacts` with the CSV content written as a `str` literal, or as `bytes` for the encoding and BOM cases.
- **Checks:** tests look at the returned `ImportReport`: `created`/`updated`, and each `RowIssue` with its row, column and message. They also check what's stored afterwards, through the repository's public methods (`get`, `find`, `all`, `len`).
- **File errors:** tests assert that `ImportFileError` is raised *and* that the repository hasn't changed.
- **Round trip:** at least one test feeds `export_csv` output straight into `import_contacts`, which proves the import accepts our own export format.
- **No other seams:** the private parsing, decoding and merge helpers aren't tested directly, and there are no changes to `ContactBook`, the repository or the validators to make testing easier.
- **Prior art:** `tests/test_export.py` and `tests/test_service.py`, which are plain pytest functions with inline literal data, plus a new `tests/test_importer.py`.

Is that the seam you'd expect? Once you confirm, I'll write the spec and publish it to `.scratch/csv-import/spec.md` with the `ready-for-agent` label.

### [to-spec] user

Yes, that seam is fine. Go ahead and write the spec. I don't mind how you structure the tests. Just keep the tests off the exact wording of messages, since I don't care about that.

### [to-spec] agent

I've written the spec to `.scratch/csv-import/spec.md` and marked it `Status: ready-for-agent`. It uses the terms from the glossary and follows ADR-0001.

It has the template sections:
- **User stories:** 51 of them, mostly from the sales side, with a few for the HTTP/CLI developer.
- **Implementation decisions:** your fixed interface, the file-level checks, row numbering, how each cell is read, the merge rules, and the order of the report.
- **Testing decisions:** the single `import_contacts` seam. Tests check the report, the issue rows and columns, and what's in the repository afterwards, never the wording of messages.
- **Out of scope:** what this import deliberately doesn't do.

We didn't spell out a few edge cases during the grilling, so I made these calls in the spec. Change any of them if you see it differently:

- **Header-only file:** you said "the report is empty". I wrote that it's empty *apart from header warnings*, so a header-only file that has a `Company` column still gets the unknown-column warning on row 1. If you meant completely empty, that's a one-line change.
- **`name` with only one of the pair:** a header with `name` plus just `first_name` (or just `last_name`) is a File error, the same as `name` with both.
- **Blank header cells:** these get a warning with `column=None`. You said either a warning or silence was fine.
- **Several bad tags in one cell:** this gives one issue on `tags`, not one issue per bad tag, because it's still one bad cell.
- **Blank first line:** the first row is always the header, even when it's blank. A blank first line therefore fails as "no email or name column", which is a File error.
- **Order of issues within a row:** issues follow the header's column order, and issues with no column (like extra cells) come last.

Nothing is committed: the spec, `GLOSSARY.md` and the ADR are all just new files in the working tree.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here's how I'd split the spec into tickets. I checked whether any existing code should be reworked first, and none needs to be: the validators and the repository's `find`/`add`/`update` already cover what the importer needs. Every ticket goes all the way through: interface, behaviour, and tests at the single `import_contacts` seam.

1. **Import new contacts from a file in our export format** (the first end-to-end slice)
   - **Blocked by:** none
   - **Delivers:**
     - `import_contacts`, `ImportReport`, `RowIssue` and `ImportFileError`, exported from the package root.
     - A `str` file with valid rows creates contacts, and `created` lists them in file order.
     - Columns are matched by header name, ignoring case and spaces, in any order. `phone` and `tags` are optional.
     - Tags are split on `;`, with spaces trimmed and empty pieces and repeats dropped.
     - An empty file is a File error, and a header-only file gives an empty report.
     - The round-trip test: `export_csv` output imports as is.
2. **Merge rows into existing contacts** (ADR-0001)
   - **Blocked by:** 1
   - **Delivers:** a row whose email already exists updates that contact. The name is replaced, a non-blank phone replaces the stored one, and tags are only added. The email goes into `updated` even when nothing changed.
3. **Row errors, partial import and row numbering**
   - **Blocked by:** 1
   - **Delivers:**
     - A blank or invalid name, a blank or invalid email, or an invalid tag gives one issue per bad cell, and the row is skipped while good rows still import.
     - Row numbers match the spreadsheet: the header is row 1, blank lines count, and a multi-line cell is one row.
     - Blank, whitespace-only and `,,,` rows are skipped silently.
     - Short rows are padded with blanks; long rows import with a warning.
     - Issues are ordered by row, then by column.
4. **Header checks: File errors and column warnings**
   - **Blocked by:** 1
   - **Delivers:**
     - A File error, with the repository untouched, for a missing `email` column, a missing `name` column, or a duplicate column.
     - A warning on row 1 for each unknown column and each header cell with no name.
5. **Bytes input, BOM, encoding and delimiter**
   - **Blocked by:** 1
   - **Delivers:**
     - `bytes` input decoded as UTF-8, with a BOM stripped for both `bytes` and `str`.
     - Non-UTF-8 bytes are a File error with the "CSV UTF-8" hint.
     - A semicolon-separated file is a File error.
6. **Invalid phone is a warning, not an error**
   - **Blocked by:** 2, 3
   - **Delivers:**
     - An invalid phone gives a warning on `phone`. A new contact is created without a phone, and an existing contact keeps its phone.
     - The warning is reported even on rows that are skipped for other errors.
7. **Duplicate emails within one file**
   - **Blocked by:** 3
   - **Delivers:**
     - The first row with a valid email claims it, even if that row is skipped.
     - Later rows with the same email get an error on `email` that points to the earlier row.
8. **`first_name`/`last_name` instead of `name`**
   - **Blocked by:** 3, 4
   - **Delivers:**
     - The pair counts as the name column, and the name is the non-blank parts joined with one space.
     - Both parts blank is an error on `name`.
     - `name` together with either part, or only one part without `name`, is a File error.
9. **Limit of 1000 contact rows**
   - **Blocked by:** 3
   - **Delivers:**
     - More than 1000 non-blank rows, counting invalid and duplicate rows, is a File error and nothing is imported. Exactly 1000 is allowed, and blank rows don't count.

After ticket 1, tickets 2, 3, 4 and 5 can be worked on in parallel.

Questions:
- **Granularity:** ticket 3 is the largest. It could be split so that row numbering, blank rows and short/long rows become their own ticket. 4 and 9 are small and could be merged. Is that about right, or should I split or merge anything?
- **Blocking edges:** ticket 8 depends on 4 only because of the header conflict rules. Do the blocking edges look right?

Once you approve, I'll write one file per ticket to `.scratch/csv-import/issues/01-…md` to `09-…md`, all marked `ready-for-agent`.

### [to-tickets] user

The split looks fine to me, and I don't mind the granularity or the blocking edges. Keep the tickets as you have them and write them.

### [to-tickets] agent

I've written the 9 tickets to `.scratch/csv-import/issues/`, numbered `01`–`09` with blockers first. Each one is marked `ready-for-agent`, has a "Blocked by" line and a checklist of acceptance criteria, and requires tests at the `import_contacts` seam only, with no checks on message wording.

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Import new contacts from a file in our export format | — |
| 02 | Merge rows into existing contacts | 01 |
| 03 | Row errors, partial import and row numbering | 01 |
| 04 | Header checks: File errors and column warnings | 01 |
| 05 | Bytes input, BOM, encoding and delimiter | 01 |
| 06 | Invalid phone is a warning, not an error | 02, 03 |
| 07 | Duplicate emails within one file | 03 |
| 08 | `first_name`/`last_name` instead of `name` | 03, 04 |
| 09 | Limit of 1000 contact rows | 03 |

Only 01 can start right away. Once it's done, 02–05 can be worked on in parallel.

There's one small exception to "tests stay off messages": ticket 07 lets a test check that the duplicate error's message *contains the earlier row number*. "Points to the earlier row" is part of the behaviour, and the message is the only place that number shows up. If you'd rather tests ignore messages entirely, I'll remove that line.

The spec, the tickets, `GLOSSARY.md` and the ADR are new files in the working tree, and none of them are committed.

### [to-tickets] user

Please remove that line. I don't care about message wording, so a test shouldn't depend on it. Tests should only check that the later row is an error on `email`. Otherwise the tickets are fine.

### [to-tickets] agent

I removed that line from ticket 07. I also reworded the third-occurrence check: it said the error "points to the first row", which could also only be tested through the message. It now says only that the row is a Row error on `email`, and the test line ends with "never message wording", like the other tickets.

The ticket's description still says the duplicate error points back to the earlier row, because the spec asks for that in the message. No test checks it.

All nine tickets are in `.scratch/csv-import/issues/`, along with the spec, `GLOSSARY.md` and the ADR. None of them are committed.

### [implement-spec] operator

/implement-spec .scratch/csv-import/spec.md

### [implement-spec] agent

The whole CSV import spec is built on the integration branch `csv-import` (tip `53982c0`), with all 9 tickets merged. All 83 tests pass on the merged branch; there were 24 before this work.

**What was added:**
- `src/contactbook/importer.py`, which holds `import_contacts`, `ImportReport` and `RowIssue`.
- `ImportFileError` in `errors.py`.
- All four names are exported from the package root.
- 59 new tests in `tests/test_importer.py`. Every area in the spec's testing list has at least one test, including feeding `export_csv` output straight back into the import.

**Code review:** one real bug turned up and is fixed. Some files the `csv` module can't parse raised a raw `csv.Error` instead of `ImportFileError`, for example old Mac Excel files with bare `\r` line endings, or a cell over 131072 characters. They now raise a File error and leave the repository unchanged, with two tests covering it. I also applied the readability fixes the review suggested; behaviour is unchanged.

One small duplication was left in on purpose. The importer's phone helper repeats `models._optional_phone`, and removing it would mean importing a private function or changing `models`, which the spec says stays as it is.

**Decision for you:** an *unknown* column that appears twice (e.g. `Notes,notes`) gives two header warnings and the file still imports. Only recognised columns (`Email`, ` email `) are rejected as duplicates. The spec just says "the same column appearing twice", so it could be read either way. I kept this reading because rejecting would block importing a working sheet as it is (story 26), and nothing is ambiguous when the column is ignored anyway. If you want it to cover every column, it's a one-line change. I added this question to the spec's Comments.

**Tracker and cleanup:**
- The spec and all 9 tickets are marked `resolved`, with a Comments note pointing to `csv-import`.
- There's no git remote, so no PR was opened.
- All implementer worktrees and their branches are removed.
- I deleted a `uv.lock` and the `__pycache__` folders that subagents had created.
- An empty `.claude/` folder is left in the repo root; I wasn't granted permission to remove it.
- `csv-import` isn't merged into `main` yet.
