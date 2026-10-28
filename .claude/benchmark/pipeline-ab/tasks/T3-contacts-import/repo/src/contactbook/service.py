"""Use cases on top of a contact repository.

Methods accept raw user input; validation happens in Contact / validation.py.
"""

from __future__ import annotations

from collections.abc import Iterable

from .models import Contact
from .repository import InMemoryContactRepository


class ContactBook:
    def __init__(self, repo: InMemoryContactRepository | None = None) -> None:
        self.repo = repo if repo is not None else InMemoryContactRepository()

    def add(
        self,
        name: str,
        email: str,
        phone: str | None = None,
        tags: Iterable[str] = (),
    ) -> Contact:
        """Create a contact. Raises DuplicateContactError if the email is taken."""
        contact = Contact.create(name=name, email=email, phone=phone, tags=tags)
        self.repo.add(contact)
        return contact

    def rename(self, email: str, name: str) -> Contact:
        return self._save(self.repo.get(email).rename(name))

    def set_phone(self, email: str, phone: str | None) -> Contact:
        return self._save(self.repo.get(email).with_phone(phone))

    def tag(self, email: str, *tags: str) -> Contact:
        return self._save(self.repo.get(email).with_tags(*tags))

    def untag(self, email: str, *tags: str) -> Contact:
        return self._save(self.repo.get(email).without_tags(*tags))

    def remove(self, email: str) -> Contact:
        return self.repo.remove(email)

    def search(self, text: str) -> list[Contact]:
        """Case-insensitive substring search over names and emails."""
        needle = text.strip().casefold()
        if not needle:
            return []
        return [
            contact
            for contact in self.repo.all()
            if needle in contact.name.casefold() or needle in contact.email
        ]

    def _save(self, contact: Contact) -> Contact:
        self.repo.update(contact)
        return contact
