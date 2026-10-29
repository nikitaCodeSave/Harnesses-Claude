"""Circulation desk operations. The only place that changes lending state."""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from . import policy
from .clock import Clock
from .errors import (
    CopyNotAvailable,
    DuplicateCopy,
    DuplicateMember,
    DuplicateTitle,
    LoanLimitReached,
    NoOpenLoan,
)
from .models import (
    Copy,
    CopyStatus,
    Loan,
    Material,
    Member,
    MemberCategory,
    Title,
)
from .repository import InMemoryRepository


class LendingService:
    def __init__(self, repo: InMemoryRepository, clock: Clock) -> None:
        self._repo = repo
        self._clock = clock

    # members -----------------------------------------------------------

    def register_member(
        self,
        member_id: str,
        name: str,
        category: MemberCategory = MemberCategory.ADULT,
    ) -> Member:
        if self._repo.has_member(member_id):
            raise DuplicateMember(member_id)
        member = Member(member_id, name, category, joined_on=self._clock.today())
        self._repo.add_member(member)
        return member

    def get_member(self, member_id: str) -> Member:
        return self._repo.get_member(member_id)

    # catalogue ---------------------------------------------------------

    def add_title(
        self, isbn: str, name: str, material: Material, replacement_cost: Decimal
    ) -> Title:
        if self._repo.has_title(isbn):
            raise DuplicateTitle(isbn)
        title = Title(isbn, name, material, Decimal(replacement_cost))
        self._repo.add_title(title)
        return title

    def add_copy(self, copy_id: str, isbn: str) -> Copy:
        self._repo.get_title(isbn)  # raises TitleNotFound
        if self._repo.has_copy(copy_id):
            raise DuplicateCopy(copy_id)
        copy = Copy(copy_id, isbn)
        self._repo.add_copy(copy)
        return copy

    def get_copy(self, copy_id: str) -> Copy:
        return self._repo.get_copy(copy_id)

    def withdraw_copy(self, copy_id: str) -> Copy:
        """Take a copy out of circulation for good. Only shelved copies."""
        copy = self._repo.get_copy(copy_id)
        if copy.status is not CopyStatus.AVAILABLE:
            raise CopyNotAvailable(copy_id, copy.status.value)
        copy.status = CopyStatus.WITHDRAWN
        return copy

    def available_copies(self, isbn: str) -> list[Copy]:
        self._repo.get_title(isbn)
        return [
            c for c in self._repo.copies_of(isbn) if c.status is CopyStatus.AVAILABLE
        ]

    # loans -------------------------------------------------------------

    def checkout(self, member_id: str, copy_id: str) -> Loan:
        member = self._repo.get_member(member_id)
        copy = self._repo.get_copy(copy_id)
        if copy.status is not CopyStatus.AVAILABLE:
            raise CopyNotAvailable(copy_id, copy.status.value)
        limit = policy.loan_limit(member.category)
        if len(self.open_loans(member_id)) >= limit:
            raise LoanLimitReached(member_id, limit)

        title = self._repo.get_title(copy.isbn)
        today = self._clock.today()
        loan = Loan(
            loan_id=self._repo.next_id("L"),
            copy_id=copy_id,
            member_id=member_id,
            borrowed_on=today,
            due_on=policy.due_date(title.material, today),
        )
        copy.status = CopyStatus.ON_LOAN
        self._repo.add_loan(loan)
        return loan

    def return_copy(self, copy_id: str) -> Loan:
        copy = self._repo.get_copy(copy_id)
        loan = self._repo.open_loan_for_copy(copy_id)
        if loan is None:
            raise NoOpenLoan(copy_id)
        loan.returned_on = self._clock.today()
        copy.status = CopyStatus.AVAILABLE
        return loan

    def get_loan(self, loan_id: str) -> Loan:
        return self._repo.get_loan(loan_id)

    def open_loans(self, member_id: str) -> list[Loan]:
        self._repo.get_member(member_id)
        return [l for l in self._repo.loans_of(member_id) if l.is_open]

    def loan_history(self, member_id: str) -> list[Loan]:
        """Every loan the member ever had, oldest first."""
        self._repo.get_member(member_id)
        return sorted(self._repo.loans_of(member_id), key=lambda l: l.loan_id)

    def overdue_loans(self, as_of: date | None = None) -> list[Loan]:
        """Open loans past their due date on ``as_of`` (default: today)."""
        day = as_of or self._clock.today()
        return [l for l in self._repo.all_loans() if l.is_overdue(day)]
