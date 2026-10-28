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

CSV import is in place with the interface you specified. All 43 tests pass, including 19 new ones in `tests/test_importer.py`. I haven't committed anything.

**What changed**
- `src/contactbook/importer.py`: `import_contacts`, `ImportReport` and `RowIssue`. It uses the column names and tag separator from `export.py`, and every value goes through `validation.py` before it's stored.
- `src/contactbook/errors.py`: `ImportFileError(ContactError)`. It's also exported from the package, like the other errors.
- `README.md`: the layout section now lists the new module.

**How it behaves**
- **Partial imports:** a bad row is listed in `errors` and skipped, and the other rows are still imported. Every problem in a row is reported, not just the first one, so people can fix their spreadsheet in one go.
- **Row numbers** match what a spreadsheet shows: the header is row 1. A cell containing a line break doesn't throw the numbering off.
- **The whole file fails** with `ImportFileError` when it's empty, isn't valid CSV, has no `name` or `email` column, or names a known column twice. Nothing is stored in that case: all rows are checked before any are written. The messages are meant to be shown to users, e.g. `the header row has no name or email column (expected name,email,phone,tags, found 'name;email;phone;tags')`.
- **Header:** column order, spacing and capital letters don't matter. `phone` and `tags` columns are optional. Unknown columns get a warning and their values are ignored.
- **Encoding:** bytes must be UTF-8. A byte order mark (BOM) and Windows line endings are fine. Other encodings are rejected with a hint to save the file as "CSV UTF-8", rather than guessing and storing garbled names.
- **Blank rows** (including spreadsheet padding like `,,,`) are skipped without comment.
- **Too many values:** a row with more filled cells than header columns is rejected. This is usually an unquoted comma inside a value, which shifts every later cell. If the shift doesn't push values past the last column, the row still shows up as field errors such as an invalid email.

**Decisions for you to check**
1. **Empty cells don't erase data.** On an existing contact, an empty phone or tags cell keeps the stored value, so a sparse leads sheet can't wipe phones or tags. The catch is that you can't clear a phone or all tags through an import.
2. **A filled tags cell replaces the stored tags rather than adding to them.** That lets you remove a tag by editing an export and importing it again. It also means importing a sheet tagged only `lead` would drop an existing `vip` tag. Adding to the existing tags is a one-line change if Sales would expect that.
3. **The same email twice in one file:** the first row is used and later ones are reported as errors ("duplicate of row N").
4. **Unchanged contacts aren't reported.** A row that matches an existing contact without changing anything appears in neither `created` nor `updated`. Re-importing your own export therefore gives an empty report. The fixed interface has no `unchanged` list; I can add one with a default value if the people reading the report need every row accounted for.

### [build] user

Decision 2 is wrong. Tags from the file should be added to the existing ones, and an import must never remove a tag. Please change it so a filled tags cell adds to the stored tags.

Your header description also doesn't match what I need. Our address-book export script writes `first_name` and `last_name` columns instead of `name`. A file with that pair should be accepted, and the contact's name is the two joined with one space. A name problem in such a file is still reported under column `name`.

I'm fine with decisions 1, 3 and 4.

### [build] agent

I made both changes. All 50 tests pass, and nothing is committed yet.

**Tags are now added, never removed.** Tags in a filled tags cell are added to the contact's existing tags. If every tag in the row is already stored, the contact counts as unchanged and doesn't appear in `updated`, which matches decision 4.

**`first_name` / `last_name` files are accepted.** When a file has both columns instead of `name`, the contact's name is the two values joined with one space. The usual name cleanup then trims and collapses extra spaces. Any name problem, such as a missing or too-long name, is reported under column `name`. Header names still ignore capitals and surrounding spaces, so `First_Name` works too.

There were a few cases you didn't specify, so I chose these; tell me if any are wrong:
- **Only one half filled in a row:** a row with just a first name (or just a last name) is imported with that part as the whole name. If both are empty, the row gets the usual "name is required" error. If leads must have both parts, I can make a missing part a row error instead.
- **Only one of the pair in the header** (e.g. `first_name` without `last_name`): the whole file is rejected with `ImportFileError` ("the header row has first_name but no last_name column"), since you described the pair as the format.
- **Both `name` and `first_name`/`last_name` in the header:** the file is rejected rather than guessing which to use. The message asks the user to keep one or the other. The alternative would be to use `name` and add a warning that the other two columns were ignored.

The changes are in `src/contactbook/importer.py` and `tests/test_importer.py`, plus one line in `README.md`.
