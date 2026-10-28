import pytest

from contactbook.errors import ContactNotFoundError, DuplicateContactError
from contactbook.models import Contact
from contactbook.repository import InMemoryContactRepository


def ann(**overrides):
    fields = {"name": "Ann Lee", "email": "ann@example.com"}
    fields.update(overrides)
    return Contact.create(**fields)


def test_lookup_by_email_ignores_case():
    repo = InMemoryContactRepository([ann()])
    assert repo.get("ANN@example.com").name == "Ann Lee"


def test_adding_same_email_twice_fails():
    repo = InMemoryContactRepository([ann()])
    with pytest.raises(DuplicateContactError):
        repo.add(ann(name="Ann Smith"))


def test_update_of_unknown_contact_fails():
    with pytest.raises(ContactNotFoundError):
        InMemoryContactRepository().update(ann())


def test_with_tag_filters_contacts():
    repo = InMemoryContactRepository(
        [ann(tags=["vip"]), Contact.create(name="Bob", email="bob@example.com")]
    )
    assert [c.email for c in repo.with_tag("VIP")] == ["ann@example.com"]
