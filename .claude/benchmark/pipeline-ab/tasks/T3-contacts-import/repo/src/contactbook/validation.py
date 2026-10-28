"""Field validators.

Each helper takes raw input (typed by a person, so expect stray spaces and odd
capitalisation) and returns the canonical value that the rest of the package
stores and compares on, or raises ValidationError. Never store a value that has
not been through one of these.
"""

from __future__ import annotations

import re
from collections.abc import Iterable

from .errors import ValidationError

MAX_NAME_LENGTH = 100
MAX_EMAIL_LENGTH = 254
MAX_TAG_LENGTH = 32
MIN_PHONE_DIGITS = 7
MAX_PHONE_DIGITS = 15

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[a-z]{2,}$")
_PHONE_FORMATTING_RE = re.compile(r"[\s().-]")
_DIGITS_RE = re.compile(r"^[0-9]+$")
_TAG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_WHITESPACE_RE = re.compile(r"\s+")


def normalize_email(raw: str | None) -> str:
    """Return the canonical form of an email address: trimmed and lower-cased.

    >>> normalize_email("  Ann.Lee@Example.COM ")
    'ann.lee@example.com'
    """
    value = (raw or "").strip().lower()
    if not value:
        raise ValidationError("email", "is required")
    if len(value) > MAX_EMAIL_LENGTH:
        raise ValidationError("email", f"is longer than {MAX_EMAIL_LENGTH} characters")
    if not _EMAIL_RE.match(value):
        raise ValidationError("email", f"is not a valid address: {raw!r}")
    return value


def normalize_phone(raw: str | None) -> str:
    """Return a phone number with the formatting removed.

    A leading ``+`` is kept; spaces, dots, dashes and parentheses are dropped.
    What remains must be 7-15 digits.

    >>> normalize_phone("+1 (555) 123-4567")
    '+15551234567'
    """
    value = (raw or "").strip()
    if not value:
        raise ValidationError("phone", "is empty")
    has_plus = value.startswith("+")
    digits = _PHONE_FORMATTING_RE.sub("", value[1:] if has_plus else value)
    if not _DIGITS_RE.match(digits):
        raise ValidationError("phone", f"is not a phone number: {raw!r}")
    if not MIN_PHONE_DIGITS <= len(digits) <= MAX_PHONE_DIGITS:
        raise ValidationError(
            "phone", f"must have {MIN_PHONE_DIGITS}-{MAX_PHONE_DIGITS} digits"
        )
    return f"+{digits}" if has_plus else digits


def normalize_tag(raw: str | None) -> str:
    """Return the canonical tag: lower-case, words joined with ``-``.

    >>> normalize_tag(" Key Account ")
    'key-account'
    """
    value = _WHITESPACE_RE.sub("-", (raw or "").strip().lower())
    if not value:
        raise ValidationError("tags", "tag is empty")
    if len(value) > MAX_TAG_LENGTH or not _TAG_RE.match(value):
        raise ValidationError("tags", f"invalid tag: {raw!r}")
    return value


def normalize_tags(raw_tags: Iterable[str]) -> frozenset[str]:
    """Normalise several tags at once; duplicates collapse."""
    if isinstance(raw_tags, str):
        raise TypeError("normalize_tags expects a collection of tags, not a string")
    return frozenset(normalize_tag(tag) for tag in raw_tags)


def validate_name(raw: str | None) -> str:
    """Return a display name with outer whitespace trimmed and inner runs collapsed.

    >>> validate_name("  Ann   Lee ")
    'Ann Lee'
    """
    value = _WHITESPACE_RE.sub(" ", (raw or "").strip())
    if not value:
        raise ValidationError("name", "is required")
    if len(value) > MAX_NAME_LENGTH:
        raise ValidationError("name", f"is longer than {MAX_NAME_LENGTH} characters")
    return value
