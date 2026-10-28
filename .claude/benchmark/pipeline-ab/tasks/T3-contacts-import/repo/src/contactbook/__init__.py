"""contactbook: contacts core (entity, validation, repository, export)."""

from .errors import (
    ContactError,
    ContactNotFoundError,
    DuplicateContactError,
    ValidationError,
)
from .models import Contact
from .repository import InMemoryContactRepository
from .service import ContactBook

__version__ = "0.4.0"

__all__ = [
    "Contact",
    "ContactBook",
    "ContactError",
    "ContactNotFoundError",
    "DuplicateContactError",
    "InMemoryContactRepository",
    "ValidationError",
]
