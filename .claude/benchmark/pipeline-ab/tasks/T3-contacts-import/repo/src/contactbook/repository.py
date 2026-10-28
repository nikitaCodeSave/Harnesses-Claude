"""In-memory contact storage."""

from __future__ import annotations

from collections.abc import Iterable, Iterator

from .errors import ContactNotFoundError, DuplicateContactError
from .models import Contact
from .validation import normalize_tag


def _key(email: str) -> str:
    return email.strip().lower()


class InMemoryContactRepository:
    """Contacts keyed by email, compared case-insensitively.

    Keeps insertion order. Stores Contact objects as given, so callers are
    expected to pass contacts built with ``Contact.create``. Not thread-safe.
    """

    def __init__(self, contacts: Iterable[Contact] = ()) -> None:
        self._contacts: dict[str, Contact] = {}
        for contact in contacts:
            self.add(contact)

    def add(self, contact: Contact) -> None:
        """Store a new contact. Raises DuplicateContactError if the email is taken."""
        key = _key(contact.email)
        if key in self._contacts:
            raise DuplicateContactError(contact.email)
        self._contacts[key] = contact

    def update(self, contact: Contact) -> None:
        """Replace the stored contact with the same email.

        Raises ContactNotFoundError if there is none; use ``add`` for new contacts.
        """
        key = _key(contact.email)
        if key not in self._contacts:
            raise ContactNotFoundError(contact.email)
        self._contacts[key] = contact

    def get(self, email: str) -> Contact:
        """Return the contact with this email or raise ContactNotFoundError."""
        try:
            return self._contacts[_key(email)]
        except KeyError:
            raise ContactNotFoundError(email) from None

    def find(self, email: str) -> Contact | None:
        """Return the contact with this email, or None."""
        return self._contacts.get(_key(email))

    def remove(self, email: str) -> Contact:
        """Delete and return the contact with this email."""
        try:
            return self._contacts.pop(_key(email))
        except KeyError:
            raise ContactNotFoundError(email) from None

    def all(self) -> list[Contact]:
        """All contacts, in the order they were added."""
        return list(self._contacts.values())

    def with_tag(self, tag: str) -> list[Contact]:
        wanted = normalize_tag(tag)
        return [contact for contact in self._contacts.values() if wanted in contact.tags]

    def __len__(self) -> int:
        return len(self._contacts)

    def __contains__(self, email: object) -> bool:
        return isinstance(email, str) and _key(email) in self._contacts

    def __iter__(self) -> Iterator[Contact]:
        return iter(list(self._contacts.values()))
