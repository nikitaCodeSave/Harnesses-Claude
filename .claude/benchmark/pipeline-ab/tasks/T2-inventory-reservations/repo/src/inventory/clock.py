"""Time source.

Nothing in this package reads the wall clock. Callers inject a ``Clock`` so
that every timestamp (ledger entries, order placement, ...) is reproducible.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Protocol


class Clock(Protocol):
    def now(self) -> datetime: ...


class FixedClock:
    """A clock that only moves when told to. Used by tests and simulations."""

    def __init__(self, start: datetime | None = None) -> None:
        start = start or datetime(2024, 1, 1, tzinfo=timezone.utc)
        if start.tzinfo is None:
            raise ValueError("FixedClock needs a timezone-aware datetime")
        self._now = start

    def now(self) -> datetime:
        return self._now

    def advance(self, delta: timedelta | None = None, **kwargs: float) -> datetime:
        """Move forward by ``delta`` or by ``timedelta(**kwargs)``."""
        step = delta if delta is not None else timedelta(**kwargs)
        if step < timedelta(0):
            raise ValueError("FixedClock cannot move backwards")
        self._now += step
        return self._now

    def set(self, when: datetime) -> None:
        if when < self._now:
            raise ValueError("FixedClock cannot move backwards")
        self._now = when
