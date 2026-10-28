"""The Contact entity."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field, replace

from .validation import (
    normalize_email,
    normalize_phone,
    normalize_tag,
    normalize_tags,
    validate_name,
)


@dataclass(frozen=True, slots=True)
class Contact:
    """A person we keep in touch with, identified by email.

    Instances are immutable: ``rename`` / ``with_*`` / ``without_tags`` return a
    new Contact. Build contacts from untrusted input with :meth:`create`, which
    validates and normalises every field; the plain constructor trusts its
    arguments and is meant for code that already holds normalised values.
    """

    name: str
    email: str
    phone: str | None = None
    tags: frozenset[str] = field(default_factory=frozenset)

    @classmethod
    def create(
        cls,
        name: str,
        email: str,
        phone: str | None = None,
        tags: Iterable[str] = (),
    ) -> Contact:
        """Validate and normalise raw values; a blank phone means "no phone"."""
        return cls(
            name=validate_name(name),
            email=normalize_email(email),
            phone=_optional_phone(phone),
            tags=normalize_tags(tags),
        )

    def rename(self, name: str) -> Contact:
        return replace(self, name=validate_name(name))

    def with_phone(self, phone: str | None) -> Contact:
        """Set the phone number; ``None`` or a blank string clears it."""
        return replace(self, phone=_optional_phone(phone))

    def with_tags(self, *tags: str) -> Contact:
        return replace(self, tags=self.tags | normalize_tags(tags))

    def without_tags(self, *tags: str) -> Contact:
        return replace(self, tags=self.tags - normalize_tags(tags))

    def has_tag(self, tag: str) -> bool:
        return normalize_tag(tag) in self.tags


def _optional_phone(raw: str | None) -> str | None:
    if raw is None or not raw.strip():
        return None
    return normalize_phone(raw)
