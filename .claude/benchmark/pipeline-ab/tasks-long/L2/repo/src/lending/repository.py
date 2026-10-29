"""In-memory persistence. The service talks only to this interface."""

from __future__ import annotations

from .errors import CopyNotFound, LoanNotFound, MemberNotFound, TitleNotFound
from .models import Copy, Loan, Member, Title


class InMemoryRepository:
    def __init__(self) -> None:
        self._members: dict[str, Member] = {}
        self._titles: dict[str, Title] = {}
        self._copies: dict[str, Copy] = {}
        self._loans: dict[str, Loan] = {}
        self._sequences: dict[str, int] = {}

    # identifiers -------------------------------------------------------

    def next_id(self, prefix: str) -> str:
        """Sequential ids per prefix: L0001, L0002, ..."""
        n = self._sequences.get(prefix, 0) + 1
        self._sequences[prefix] = n
        return f"{prefix}{n:04d}"

    # members -----------------------------------------------------------

    def add_member(self, member: Member) -> None:
        self._members[member.member_id] = member

    def has_member(self, member_id: str) -> bool:
        return member_id in self._members

    def get_member(self, member_id: str) -> Member:
        try:
            return self._members[member_id]
        except KeyError:
            raise MemberNotFound(member_id) from None

    # catalogue ---------------------------------------------------------

    def add_title(self, title: Title) -> None:
        self._titles[title.isbn] = title

    def has_title(self, isbn: str) -> bool:
        return isbn in self._titles

    def get_title(self, isbn: str) -> Title:
        try:
            return self._titles[isbn]
        except KeyError:
            raise TitleNotFound(isbn) from None

    def add_copy(self, copy: Copy) -> None:
        self._copies[copy.copy_id] = copy

    def has_copy(self, copy_id: str) -> bool:
        return copy_id in self._copies

    def get_copy(self, copy_id: str) -> Copy:
        try:
            return self._copies[copy_id]
        except KeyError:
            raise CopyNotFound(copy_id) from None

    def copies_of(self, isbn: str) -> list[Copy]:
        return [c for c in self._copies.values() if c.isbn == isbn]

    # loans -------------------------------------------------------------

    def add_loan(self, loan: Loan) -> None:
        self._loans[loan.loan_id] = loan

    def get_loan(self, loan_id: str) -> Loan:
        try:
            return self._loans[loan_id]
        except KeyError:
            raise LoanNotFound(loan_id) from None

    def open_loan_for_copy(self, copy_id: str) -> Loan | None:
        for loan in self._loans.values():
            if loan.copy_id == copy_id and loan.is_open:
                return loan
        return None

    def loans_of(self, member_id: str) -> list[Loan]:
        return [l for l in self._loans.values() if l.member_id == member_id]

    def all_loans(self) -> list[Loan]:
        return list(self._loans.values())
