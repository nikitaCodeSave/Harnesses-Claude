from contactbook.export import export_csv
from contactbook.models import Contact


def test_export_writes_header_and_one_row_per_contact():
    contacts = [
        Contact.create(name="Ann Lee", email="ann@example.com", phone="+15551234567"),
        Contact.create(name="Bob Stone", email="bob@example.com"),
    ]
    assert export_csv(contacts) == (
        "name,email,phone,tags\n"
        "Ann Lee,ann@example.com,+15551234567,\n"
        "Bob Stone,bob@example.com,,\n"
    )


def test_export_joins_sorted_tags_in_one_cell():
    contact = Contact.create(name="Ann Lee", email="ann@example.com", tags=["vip", "lead"])
    assert export_csv([contact]).splitlines()[1] == "Ann Lee,ann@example.com,,lead;vip"
