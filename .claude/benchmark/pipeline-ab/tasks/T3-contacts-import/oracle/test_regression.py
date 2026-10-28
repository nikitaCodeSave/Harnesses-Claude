"""Hidden regression oracle for T3: pre-existing behaviour the import feature
could plausibly break (shared validators, Contact helpers, repository
uniqueness, CSV export). Every test passes on the pristine repo.
"""

from __future__ import annotations

import pytest

from contactbook.errors import (
    ContactError,
    ContactNotFoundError,
    DuplicateContactError,
    ValidationError,
)
from contactbook.export import export_csv
from contactbook.models import Contact
from contactbook.repository import InMemoryContactRepository
from contactbook.service import ContactBook
from contactbook.validation import (
    normalize_email,
    normalize_phone,
    normalize_tag,
    validate_name,
)


def ann(**overrides) -> Contact:
    fields = {"name": "Ann Lee", "email": "ann@example.com"}
    fields.update(overrides)
    return Contact.create(**fields)


def test_normalize_email_trims_and_lowercases():
    """Existing validator: email canonical form."""
    assert normalize_email("  Ann.Lee@Example.COM ") == "ann.lee@example.com"


def test_normalize_email_rejects_garbage_with_field_email():
    """Existing validator: invalid email raises ValidationError(field='email')."""
    with pytest.raises(ValidationError) as excinfo:
        normalize_email("ann(at)example.com")
    assert excinfo.value.field == "email"


def test_normalize_phone_strips_formatting():
    """Existing validator: phone formatting removed, leading + kept."""
    assert normalize_phone("+1 (555) 123-4567") == "+15551234567"


def test_normalize_phone_raises_on_letters():
    """Existing validator: invalid phone raises (does not return a sentinel)."""
    with pytest.raises(ValidationError) as excinfo:
        normalize_phone("call after 6pm")
    assert excinfo.value.field == "phone"


def test_normalize_phone_rejects_too_few_digits():
    """Existing validator: fewer than 7 digits is invalid."""
    with pytest.raises(ValidationError):
        normalize_phone("12345")


def test_normalize_tag_hyphenates_words():
    """Existing validator: tag canonical form."""
    assert normalize_tag(" Key Account ") == "key-account"


def test_normalize_tag_rejects_punctuation():
    """Existing validator: invalid tag raises ValidationError(field='tags')."""
    with pytest.raises(ValidationError) as excinfo:
        normalize_tag("c++")
    assert excinfo.value.field == "tags"


def test_validate_name_collapses_whitespace():
    """Existing validator: name whitespace collapsed."""
    assert validate_name("  Ann   Lee ") == "Ann Lee"


def test_validation_error_is_a_contact_error_with_message():
    """Existing errors: ValidationError keeps field/message and derives from ContactError."""
    error = ValidationError("name", "is required")
    assert (isinstance(error, ContactError), error.field, error.message) == (
        True,
        "name",
        "is required",
    )


def test_contact_create_rejects_invalid_phone():
    """Existing model: Contact.create still validates the phone strictly."""
    with pytest.raises(ValidationError):
        ann(phone="call after 6pm")


def test_contact_create_blank_phone_is_none():
    """Existing model: blank phone means no phone."""
    assert ann(phone="   ").phone is None


def test_with_phone_none_clears_phone():
    """Existing model: with_phone(None) clears the phone."""
    assert ann(phone="+15551234567").with_phone(None).phone is None


def test_repository_add_rejects_duplicate_email_any_case():
    """Existing repository: add never upserts; same email in any case is a duplicate."""
    repo = InMemoryContactRepository([ann()])
    with pytest.raises(DuplicateContactError):
        repo.add(ann(name="Ann Smith", email="ANN@example.com"))


def test_repository_update_requires_existing_contact():
    """Existing repository: update never inserts."""
    with pytest.raises(ContactNotFoundError):
        InMemoryContactRepository().update(ann())


def test_repository_get_unknown_raises():
    """Existing repository: get of unknown email raises ContactNotFoundError."""
    with pytest.raises(ContactNotFoundError):
        InMemoryContactRepository().get("nobody@example.com")


def test_service_add_rejects_existing_email():
    """Existing service: ContactBook.add does not merge into an existing contact."""
    book = ContactBook()
    book.add("Ann Lee", "ann@example.com")
    with pytest.raises(DuplicateContactError):
        book.add("Ann Smith", "ann@example.com")


def test_export_format_is_unchanged():
    """Existing export: header, column order and ';'-joined sorted tags."""
    contact = ann(phone="+15551234567", tags=["vip", "lead"])
    assert export_csv([contact]) == (
        "name,email,phone,tags\nAnn Lee,ann@example.com,+15551234567,lead;vip\n"
    )
