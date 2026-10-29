"""Circulation policy: loan periods, limits and opening days.

Kept apart from the service so the numbers live in one place.
"""

from __future__ import annotations

from datetime import date, timedelta

from .models import Material, MemberCategory

LOAN_DAYS: dict[Material, int] = {
    Material.BOOK: 21,
    Material.DVD: 7,
}

LOAN_LIMITS: dict[MemberCategory, int] = {
    MemberCategory.ADULT: 8,
    MemberCategory.CHILD: 4,
}

# date.weekday(): Monday is 0, Sunday is 6. The library is closed on Sundays.
CLOSED_WEEKDAYS: frozenset[int] = frozenset({6})


def is_open_day(day: date) -> bool:
    return day.weekday() not in CLOSED_WEEKDAYS


def next_open_day(day: date) -> date:
    """``day`` itself if the library is open then, else the next open day."""
    while not is_open_day(day):
        day += timedelta(days=1)
    return day


def due_date(material: Material, borrowed_on: date) -> date:
    """Loan period counted in calendar days, never ending on a closed day."""
    return next_open_day(borrowed_on + timedelta(days=LOAN_DAYS[material]))


def loan_limit(category: MemberCategory) -> int:
    return LOAN_LIMITS[category]
