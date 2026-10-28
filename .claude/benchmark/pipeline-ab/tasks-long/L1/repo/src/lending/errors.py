"""Domain errors. Every failure the service reports is a ``LendingError``."""


class LendingError(Exception):
    """Base class for all lending domain errors."""


class MemberNotFound(LendingError):
    def __init__(self, member_id: str) -> None:
        super().__init__(f"no member {member_id!r}")
        self.member_id = member_id


class DuplicateMember(LendingError):
    def __init__(self, member_id: str) -> None:
        super().__init__(f"member {member_id!r} already registered")
        self.member_id = member_id


class TitleNotFound(LendingError):
    def __init__(self, isbn: str) -> None:
        super().__init__(f"no title with ISBN {isbn!r}")
        self.isbn = isbn


class DuplicateTitle(LendingError):
    def __init__(self, isbn: str) -> None:
        super().__init__(f"title {isbn!r} already in the catalogue")
        self.isbn = isbn


class CopyNotFound(LendingError):
    def __init__(self, copy_id: str) -> None:
        super().__init__(f"no copy {copy_id!r}")
        self.copy_id = copy_id


class DuplicateCopy(LendingError):
    def __init__(self, copy_id: str) -> None:
        super().__init__(f"copy {copy_id!r} already exists")
        self.copy_id = copy_id


class CopyNotAvailable(LendingError):
    """The copy exists but cannot be lent or changed in its current state."""

    def __init__(self, copy_id: str, status: str) -> None:
        super().__init__(f"copy {copy_id!r} is {status}")
        self.copy_id = copy_id
        self.status = status


class LoanLimitReached(LendingError):
    def __init__(self, member_id: str, limit: int) -> None:
        super().__init__(f"member {member_id!r} already has {limit} loans")
        self.member_id = member_id
        self.limit = limit


class LoanNotFound(LendingError):
    def __init__(self, loan_id: str) -> None:
        super().__init__(f"no loan {loan_id!r}")
        self.loan_id = loan_id


class NoOpenLoan(LendingError):
    """A copy was handed back that is not out on loan."""

    def __init__(self, copy_id: str) -> None:
        super().__init__(f"copy {copy_id!r} is not on loan")
        self.copy_id = copy_id
