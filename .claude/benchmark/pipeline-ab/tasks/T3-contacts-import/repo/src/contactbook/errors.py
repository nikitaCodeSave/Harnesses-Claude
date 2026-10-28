"""Domain errors.

Everything contactbook raises on purpose derives from ContactError, so callers
(the HTTP layer, CLI tools) can catch one class and turn it into a user-facing
message. Programming errors (TypeError and friends) are not wrapped.
"""


class ContactError(Exception):
    """Base class for all contactbook domain errors."""


class ValidationError(ContactError):
    """A value was rejected by a validator.

    ``field`` is the Contact attribute the value was meant for
    (``name``, ``email``, ``phone`` or ``tags``); ``message`` is a short,
    human-readable reason without the field name.
    """

    def __init__(self, field: str, message: str) -> None:
        super().__init__(f"{field}: {message}")
        self.field = field
        self.message = message


class DuplicateContactError(ContactError):
    """A contact with this email already exists."""

    def __init__(self, email: str) -> None:
        super().__init__(f"contact already exists: {email}")
        self.email = email


class ContactNotFoundError(ContactError):
    """No contact with this email."""

    def __init__(self, email: str) -> None:
        super().__init__(f"no contact with email {email}")
        self.email = email
