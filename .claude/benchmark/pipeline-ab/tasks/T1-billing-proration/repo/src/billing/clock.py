"""Clock abstraction.

Billing code never asks the system for the current date: the service is
given a ``Clock`` so that every date decision is reproducible in tests and
in replays of production incidents.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Protocol


class Clock(Protocol):
    def today(self) -> date: ...


class FixedClock:
    """A clock that only moves when told to."""

    def __init__(self, today: date) -> None:
        self._today = today

    def today(self) -> date:
        return self._today

    def move_to(self, day: date) -> None:
        if day < self._today:
            raise ValueError(f"clock cannot go backwards ({self._today} -> {day})")
        self._today = day

    def advance(self, days: int) -> None:
        self.move_to(self._today + timedelta(days=days))
