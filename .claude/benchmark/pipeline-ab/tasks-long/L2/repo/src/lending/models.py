"""Domain records. Plain dataclasses; only ``LendingService`` mutates them."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from enum import Enum


class MemberCategory(Enum):
    ADULT = "adult"
    CHILD = "child"


class Material(Enum):
    BOOK = "book"
    DVD = "dvd"


class CopyStatus(Enum):
    AVAILABLE = "available"
    ON_LOAN = "on_loan"
    WITHDRAWN = "withdrawn"


@dataclass
class Member:
    member_id: str
    name: str
    category: MemberCategory
    joined_on: date


@dataclass(frozen=True)
class Title:
    isbn: str
    name: str
    material: Material
    # What the library pays to replace a copy; money is always Decimal.
    replacement_cost: Decimal


@dataclass
class Copy:
    copy_id: str
    isbn: str
    status: CopyStatus = CopyStatus.AVAILABLE


@dataclass
class Loan:
    loan_id: str
    copy_id: str
    member_id: str
    borrowed_on: date
    due_on: date
    returned_on: date | None = None

    @property
    def is_open(self) -> bool:
        return self.returned_on is None

    def is_overdue(self, on: date) -> bool:
        return self.is_open and on > self.due_on
