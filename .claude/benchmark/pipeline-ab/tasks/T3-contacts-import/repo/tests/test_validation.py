import pytest

from contactbook.errors import ValidationError
from contactbook.validation import (
    normalize_email,
    normalize_phone,
    normalize_tag,
    normalize_tags,
    validate_name,
)


def test_email_is_trimmed_and_lowercased():
    assert normalize_email("  Ann.Lee@Example.COM ") == "ann.lee@example.com"


def test_email_without_domain_suffix_is_rejected():
    with pytest.raises(ValidationError) as excinfo:
        normalize_email("ann@example")
    assert excinfo.value.field == "email"


def test_phone_formatting_is_removed():
    assert normalize_phone("+1 (555) 123-4567") == "+15551234567"


def test_phone_without_plus_stays_without_plus():
    assert normalize_phone("030 1234 5678") == "03012345678"


@pytest.mark.parametrize("raw", ["12345", "+1 555 CALL NOW"])
def test_bad_phone_is_rejected(raw):
    with pytest.raises(ValidationError) as excinfo:
        normalize_phone(raw)
    assert excinfo.value.field == "phone"


def test_tag_is_lowercased_and_hyphenated():
    assert normalize_tag(" Key Account ") == "key-account"


def test_tag_with_punctuation_is_rejected():
    with pytest.raises(ValidationError):
        normalize_tag("c++")


def test_normalize_tags_refuses_a_bare_string():
    with pytest.raises(TypeError):
        normalize_tags("vip")


def test_name_whitespace_is_collapsed():
    assert validate_name("  Ann   Lee ") == "Ann Lee"


def test_blank_name_is_rejected():
    with pytest.raises(ValidationError) as excinfo:
        validate_name("   ")
    assert excinfo.value.field == "name"
