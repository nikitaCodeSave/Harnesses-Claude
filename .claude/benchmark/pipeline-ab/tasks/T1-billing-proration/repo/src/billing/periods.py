"""Calendar arithmetic for billing periods.

Periods are half-open: ``[start, end)``. ``end`` is the first day of the
next period and the day the renewal is billed.
"""

from __future__ import annotations

import calendar
from datetime import date

from billing.plans import Interval


def add_months(day: date, months: int) -> date:
    """Shift ``day`` by whole months, clamping to the end of a shorter month.

    Jan 31 + 1 month is Feb 28 (Feb 29 in a leap year); Feb 29 + 12 months
    is Feb 28.
    """
    index = day.month - 1 + months
    year, month = day.year + index // 12, index % 12 + 1
    last_day = calendar.monthrange(year, month)[1]
    return date(year, month, min(day.day, last_day))


def period_end(start: date, interval: Interval) -> date:
    """End (exclusive) of the period of ``interval`` that begins on ``start``."""
    return add_months(start, interval.months)
