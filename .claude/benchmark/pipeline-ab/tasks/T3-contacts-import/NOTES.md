# T3 contacts import: product owner's private notes

Context: the sales team keeps leads in Excel and Google Sheets, and in Outlook / Google
Contacts address books. The CSV files are made by non-technical people, mostly saved
from Excel. They fix problems by opening the file in Excel, correcting the reported rows
and importing the file again.

## Rules

N1. **Columns / header.** The first line is the header. Column names are matched
    case-insensitively, ignoring spaces around them (`Email`, ` EMAIL ` are fine), and
    column order is free. Required columns: `email` and `name` (N2 gives the alternative
    to `name`). Optional columns: `phone`, `tags`. Any other column (company, notes, ...)
    is ignored. A missing required column, or a completely empty file, means the whole
    file is rejected with `ImportFileError` and nothing is imported.

N2. **Address-book exports.** Our address-book export script (what sales uses to pull
    contacts out of Outlook / Google Contacts) writes `first_name` and `last_name`
    columns instead of `name`. Accept them: that pair counts as the name column, and the
    contact's name is the first and last name joined with one space.

N3. **Size limit.** At most 1000 contact rows per file (the blank rows of N6 don't
    count). A bigger file is rejected as a whole with `ImportFileError` and nothing is
    imported: people should split it rather than end up with a half-loaded file. A file
    with only the header is fine: nothing happens, the report is empty.

N4. **Encoding.** Files are UTF-8. Excel's "CSV UTF-8" format puts a byte-order mark
    (BOM) at the very start, and that must just work: for bytes, and also for text input
    that still starts with the BOM character. Bytes that are not valid UTF-8 (old Excel
    saves in Windows-1251) → `ImportFileError` telling them to re-save as "CSV UTF-8".

N5. **Row numbers and columns in the report.** `row` is the spreadsheet row number the
    user sees in Excel: the header is row 1, the first contact is row 2, and every line
    of the file counts, blank lines included. `column` is the lower-case name of the
    column the problem is in: `name`, `email`, `phone` or `tags` (a name problem in a
    `first_name`/`last_name` file is `name` too).

N6. **Blank rows.** Empty lines, and rows where every cell is empty or only spaces
    (Excel leaves `,,,` lines at the bottom), are skipped silently: no error, no warning.

N7. **Partial import.** Not all-or-nothing, apart from the whole-file problems in
    N1/N3/N4: good rows go in, bad rows are reported in `errors` and skipped. A bad row
    is not applied at all, not even partly to an existing contact.

N8. **Email is the identity.** Normalise it with the existing email helper (trim +
    lower-case), so ` ANN@X.COM` is the same person as `ann@x.com`. A missing or invalid
    email is an error on that row. `created` / `updated` list the normalised emails.

N9. **Contact already exists** (same email): update it. That is not an error and never
    a second contact; it goes into `updated`. Name: the file's value replaces ours.
    Phone: replaced only when the cell has a value; an empty cell or a missing phone
    column never wipes a phone we already have. Tags: the file's tags are added to the
    existing ones; an import never removes tags.

N10. **Same email twice in one file.** The first row wins. Every later row with that
     email is an error on that later row and is not applied. It is almost always a
     copy-paste slip and I want people to see it.

N11. **Phone.** Optional; an empty cell is fine. Normalise it with the existing phone
     helper. A phone that fails validation must not cost us the contact: import or
     update the rest of the row, leave the phone as it was (none for a new contact) and
     add a *warning*, not an error, for that row with column `phone`.

N12. **Tags.** The `tags` cell holds several tags separated by `;` (as in our export).
     Normalise each with the existing tag helper; empty pieces and repeats are ignored.
     An invalid tag makes the row an error (column `tags`).

N13. **Name.** Required on every row, also when it updates an existing contact.
     Validate it with the existing name helper. Empty → error on that row (column
     `name`).

## Don't care (any sensible behaviour is acceptable)

- Wording of messages in errors, warnings and `ImportFileError`.
- Order of entries in `created`, `updated`, `errors`, `warnings`.
- Whether a row with several problems produces one error entry or several, and whether
  a row that is an error also gets a phone warning.
- Whether an existing contact whose data does not actually change is listed in `updated`.
- Unknown extra columns: ignore them silently or add a warning; just never an error.
- Rows with more or fewer cells than the header.
- Row numbering when a quoted cell spans several lines; delimiters other than comma;
  blank lines before the header.
- If an email first appears on a row that is itself an error, whether later rows with
  that email count as duplicates.
- Files that have both `name` and `first_name`/`last_name`, or only one of the pair.
- Header spellings other than the ones named here (`First Name`, `E-mail Address`, ...).
- Rows where only ignored columns have values; files with nothing but a BOM or blank
  lines (rejecting them as empty is fine too).
