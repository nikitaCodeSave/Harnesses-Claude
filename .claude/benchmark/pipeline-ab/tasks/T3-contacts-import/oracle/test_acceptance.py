"""Hidden acceptance oracle for T3 (bulk CSV import of contacts).

Only the public interface fixed in BRIEF.md and pre-existing domain objects are
used. Each test checks one behaviour fixed by BRIEF.md or a NOTES.md item, cited
in its docstring. Nothing depends on a "Don't care" choice: report lists are
compared order-insensitively, messages are never inspected, and no row carries
more than one problem.
"""

from __future__ import annotations

import pytest

from contactbook.errors import ContactError, ImportFileError
from contactbook.importer import import_contacts
from contactbook.models import Contact
from contactbook.repository import InMemoryContactRepository

ANN = "ann@example.com"
BOB = "bob@example.com"
ANN_PHONE = "+15551234567"


def make_repo(*contacts: Contact) -> InMemoryContactRepository:
    repo = InMemoryContactRepository()
    for contact in contacts:
        repo.add(contact)
    return repo


def stored_ann() -> Contact:
    return Contact.create(name="Ann Lee", email=ANN, phone=ANN_PHONE, tags=["vip"])


def issue_rows(issues) -> list[int]:
    return sorted(issue.row for issue in issues)


def many_rows(count: int) -> str:
    return "name,email\n" + "".join(
        f"Person {i},person{i}@example.com\n" for i in range(count)
    )


# --- BRIEF: interface ------------------------------------------------------


def test_valid_rows_are_stored_in_repo():
    """BRIEF: import loads the CSV rows into the given repository."""
    repo = make_repo()
    import_contacts(repo, "name,email\nAnn Lee,ann@example.com\nBob Stone,bob@example.com\n")
    assert sorted(c.email for c in repo.all()) == [ANN, BOB]


def test_created_lists_normalised_emails():
    """BRIEF (created: normalised emails) + N8: created holds trimmed, lower-cased emails."""
    report = import_contacts(make_repo(), "name,email\nAnn Lee, Ann@Example.COM \n")
    assert report.created == [ANN]


def test_bytes_input_is_accepted():
    """BRIEF: data may be raw bytes as read from disk."""
    report = import_contacts(make_repo(), b"name,email\nAnn Lee,ann@example.com\n")
    assert report.created == [ANN]


def test_import_file_error_is_a_contact_error():
    """BRIEF: ImportFileError(ContactError) in contactbook.errors."""
    assert issubclass(ImportFileError, ContactError)


# --- N1: columns / header --------------------------------------------------


def test_header_matching_ignores_case_and_spaces():
    """N1: column names match case-insensitively, ignoring surrounding spaces."""
    repo = make_repo()
    import_contacts(repo, " Name , EMAIL \nAnn Lee,ann@example.com\n")
    assert repo.get(ANN).name == "Ann Lee"


def test_unknown_columns_ignored_and_order_free():
    """N1: any column order; extra columns are ignored, never an error."""
    repo = make_repo()
    report = import_contacts(repo, "company,email,name\nAcme,ann@example.com,Ann Lee\n")
    assert (report.errors, repo.get(ANN).name) == ([], "Ann Lee")


def test_missing_email_column_rejects_file():
    """N1: a missing required column rejects the whole file with ImportFileError."""
    with pytest.raises(ImportFileError):
        import_contacts(make_repo(), "name,phone\nAnn Lee,+15551234567\n")


def test_phone_and_tags_columns_are_optional():
    """N1: phone and tags columns may be absent."""
    repo = make_repo()
    import_contacts(repo, "name,email\nAnn Lee,ann@example.com\n")
    contact = repo.get(ANN)
    assert (contact.phone, set(contact.tags)) == (None, set())


def test_empty_file_is_rejected():
    """N1: a completely empty file is rejected with ImportFileError."""
    with pytest.raises(ImportFileError):
        import_contacts(make_repo(), "")


# --- N2: address-book exports ----------------------------------------------


def test_first_and_last_name_columns_make_the_name():
    """N2: first_name + last_name replace the name column, joined with one space."""
    repo = make_repo()
    import_contacts(repo, "first_name,last_name,email\nAnn,Lee,ann@example.com\n")
    assert repo.get(ANN).name == "Ann Lee"


# --- N3: size limit --------------------------------------------------------


def test_more_than_1000_rows_rejects_whole_file():
    """N3: more than 1000 contact rows -> ImportFileError and nothing imported."""
    repo = make_repo()
    with pytest.raises(ImportFileError):
        import_contacts(repo, many_rows(1001))
    assert len(repo) == 0


def test_exactly_1000_rows_are_imported():
    """N3: 1000 contact rows is within the limit."""
    report = import_contacts(make_repo(), many_rows(1000))
    assert len(report.created) == 1000


def test_header_only_file_gives_empty_report():
    """N3: a file with only the header is fine and the report is empty."""
    report = import_contacts(make_repo(), "name,email,phone,tags\n")
    assert (report.created, report.updated, report.errors) == ([], [], [])


# --- N4: encoding ----------------------------------------------------------


def test_utf8_bom_file_bytes_are_imported(tmp_path):
    """N4: Excel 'CSV UTF-8' files start with a BOM; bytes input must just work."""
    path = tmp_path / "contacts.csv"
    path.write_text("name,email\nAnn Lee,ann@example.com\n", encoding="utf-8-sig")
    repo = make_repo()
    import_contacts(repo, path.read_bytes())
    assert repo.get(ANN).name == "Ann Lee"


def test_bom_at_start_of_text_input_is_ignored():
    """N4: text input that still starts with the BOM character must just work."""
    repo = make_repo()
    import_contacts(repo, "\ufeffname,email\nAnn Lee,ann@example.com\n")
    assert repo.get(ANN).name == "Ann Lee"


def test_non_utf8_bytes_reject_file(tmp_path):
    """N4: bytes that are not valid UTF-8 (Windows-1251) -> ImportFileError."""
    path = tmp_path / "contacts.csv"
    path.write_text("name,email\nИван Петров,ivan@example.com\n", encoding="cp1251")
    with pytest.raises(ImportFileError):
        import_contacts(make_repo(), path.read_bytes())


# --- N5: row numbers -------------------------------------------------------


def test_first_contact_is_row_2():
    """N5: the header is row 1, so the first contact row is row 2."""
    report = import_contacts(make_repo(), "name,email\nAnn Lee,not-an-email\n")
    assert issue_rows(report.errors) == [2]


def test_blank_lines_count_in_row_numbers():
    """N5: every line counts toward row numbers, blank lines included."""
    report = import_contacts(
        make_repo(), "name,email\nAnn Lee,ann@example.com\n\nBob Stone,not-an-email\n"
    )
    assert issue_rows(report.errors) == [4]


# --- N6: blank rows --------------------------------------------------------


def test_blank_and_empty_cell_rows_are_skipped_silently():
    """N6: empty lines and rows of empty/space-only cells give no error and no warning."""
    data = (
        "name,email,phone\n"
        "Ann Lee,ann@example.com,\n"
        ",,\n"
        "\n"
        " , , \n"
        "Bob Stone,bob@example.com,\n"
    )
    report = import_contacts(make_repo(), data)
    assert (report.errors, report.warnings) == ([], [])


# --- N7: partial import ----------------------------------------------------


def test_valid_rows_are_imported_despite_a_bad_row():
    """N7: not all-or-nothing; good rows go in when another row is bad."""
    data = "name,email\nAnn Lee,ann@example.com\nBob Stone,not-an-email\nCid Moss,cid@example.com\n"
    report = import_contacts(make_repo(), data)
    assert sorted(report.created) == [ANN, "cid@example.com"]


def test_bad_row_is_not_partly_applied_to_existing_contact():
    """N7 + N13: a row that is an error leaves the existing contact untouched."""
    repo = make_repo(stored_ann())
    import_contacts(repo, "name,email,tags\n,ann@example.com,partner\n")
    assert repo.get(ANN) == stored_ann()


# --- N8: email identity ----------------------------------------------------


def test_invalid_email_is_a_row_error():
    """N8 + N5: an invalid email is an error on that row, column 'email'."""
    report = import_contacts(make_repo(), "name,email\nAnn Lee,ann(at)example.com\n")
    assert [(e.row, e.column) for e in report.errors] == [(2, "email")]


def test_email_matches_existing_contact_case_insensitively():
    """N8: ' ANN@Example.COM ' is the same person as ann@example.com."""
    repo = make_repo(stored_ann())
    import_contacts(repo, "name,email\nAnn Smith, ANN@Example.COM \n")
    assert [c.name for c in repo.all()] == ["Ann Smith"]


# --- N9: existing contacts -------------------------------------------------


def test_existing_email_is_updated_not_created_or_error():
    """N9: an existing email goes into updated; not an error, not a second contact."""
    repo = make_repo(stored_ann())
    report = import_contacts(repo, "name,email\nAnn Smith,ann@example.com\n")
    assert (report.created, report.updated, report.errors) == ([], [ANN], [])


def test_file_name_replaces_existing_name():
    """N9: the file's name replaces the stored name."""
    repo = make_repo(stored_ann())
    import_contacts(repo, "name,email\nAnn Smith,ann@example.com\n")
    assert repo.get(ANN).name == "Ann Smith"


def test_empty_phone_cell_keeps_existing_phone():
    """N9: an empty phone cell never wipes a stored phone."""
    repo = make_repo(stored_ann())
    import_contacts(repo, "name,email,phone\nAnn Lee,ann@example.com,\n")
    assert repo.get(ANN).phone == ANN_PHONE


def test_phone_cell_replaces_existing_phone():
    """N9 + N11: a non-empty valid phone replaces the stored one (normalised)."""
    repo = make_repo(stored_ann())
    import_contacts(repo, "name,email,phone\nAnn Lee,ann@example.com,+1 555 765 4321\n")
    assert repo.get(ANN).phone == "+15557654321"


def test_file_tags_are_added_to_existing_tags():
    """N9: tags from the file are added; an import never removes tags."""
    repo = make_repo(stored_ann())
    import_contacts(repo, "name,email,tags\nAnn Lee,ann@example.com,partner\n")
    assert set(repo.get(ANN).tags) == {"vip", "partner"}


# --- N10: duplicates within the file ---------------------------------------


def test_repeated_email_later_row_is_error():
    """N10 + N5: a later row repeating an email is an error on that later row."""
    report = import_contacts(
        make_repo(), "name,email\nAnn Lee,ann@example.com\nAnn Smith,ann@example.com\n"
    )
    assert issue_rows(report.errors) == [3]


def test_repeated_email_first_row_wins():
    """N10: the first row with an email wins; later rows are not applied."""
    repo = make_repo()
    import_contacts(repo, "name,email\nAnn Lee,ann@example.com\nAnn Smith,ann@example.com\n")
    assert repo.get(ANN).name == "Ann Lee"


def test_repeated_email_detection_ignores_case():
    """N10 + N8: duplicates are detected on the normalised email."""
    report = import_contacts(
        make_repo(), "name,email\nAnn Lee,ann@example.com\nAnn Smith,ANN@Example.com\n"
    )
    assert issue_rows(report.errors) == [3]


# --- N11: phone ------------------------------------------------------------


def test_invalid_phone_still_imports_new_contact_without_phone():
    """N11: an invalid phone does not cost the contact; it is created without a phone."""
    repo = make_repo()
    import_contacts(repo, "name,email,phone\nAnn Lee,ann@example.com,call after 6pm\n")
    assert repo.get(ANN).phone is None


def test_invalid_phone_is_a_warning_not_an_error():
    """N11 + N5: an invalid phone gives a warning for that row, column 'phone'."""
    report = import_contacts(
        make_repo(), "name,email,phone\nAnn Lee,ann@example.com,call after 6pm\n"
    )
    assert ([(w.row, w.column) for w in report.warnings], report.errors) == ([(2, "phone")], [])


def test_invalid_phone_on_existing_contact_keeps_phone_and_applies_rest():
    """N11 + N9: for an existing contact the rest of the row applies, the phone stays."""
    repo = make_repo(stored_ann())
    import_contacts(repo, "name,email,phone\nAnn Smith,ann@example.com,call after 6pm\n")
    contact = repo.get(ANN)
    assert (contact.name, contact.phone) == ("Ann Smith", ANN_PHONE)


def test_phone_is_normalised():
    """N11: phone is normalised with the existing phone helper."""
    repo = make_repo()
    import_contacts(repo, "name,email,phone\nAnn Lee,ann@example.com,+1 (555) 123-4567\n")
    assert repo.get(ANN).phone == ANN_PHONE


# --- N12: tags -------------------------------------------------------------


def test_tags_cell_is_split_on_semicolon_and_normalised():
    """N12: ';'-separated tags, normalised; empty pieces and repeats ignored."""
    repo = make_repo()
    import_contacts(repo, "name,email,tags\nAnn Lee,ann@example.com,VIP; Key Account;;vip\n")
    assert set(repo.get(ANN).tags) == {"vip", "key-account"}


def test_invalid_tag_is_a_row_error():
    """N12 + N5: an invalid tag makes the row an error, column 'tags'."""
    report = import_contacts(make_repo(), "name,email,tags\nAnn Lee,ann@example.com,c++\n")
    assert [(e.row, e.column) for e in report.errors] == [(2, "tags")]


# --- N13: name -------------------------------------------------------------


def test_empty_name_is_a_row_error():
    """N13 + N5: an empty name is an error on that row, column 'name'."""
    report = import_contacts(make_repo(), "name,email\n,ann@example.com\n")
    assert [(e.row, e.column) for e in report.errors] == [(2, "name")]
