"""Read-only reports for the front desk."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from .service import LendingService


@dataclass(frozen=True)
class OverdueLine:
    loan_id: str
    member_id: str
    copy_id: str
    due_on: date
    days_overdue: int  # calendar days since the due date


def overdue_report(service: LendingService, as_of: date) -> list[OverdueLine]:
    """Open loans past their due date on ``as_of``, longest overdue first.

    Ties keep loan order so the printout is stable between runs.
    """
    lines = [
        OverdueLine(
            loan_id=loan.loan_id,
            member_id=loan.member_id,
            copy_id=loan.copy_id,
            due_on=loan.due_on,
            days_overdue=(as_of - loan.due_on).days,
        )
        for loan in service.overdue_loans(as_of)
    ]
    lines.sort(key=lambda line: line.loan_id)
    lines.sort(key=lambda line: line.days_overdue, reverse=True)
    return lines
