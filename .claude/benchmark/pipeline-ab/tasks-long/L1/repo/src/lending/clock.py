"""Time source for the lending service.

Package code never calls ``date.today()`` directly: the service receives a
``Clock`` so tests can pin and move the current day.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Protocol


class Clock(Protocol):
    def today(self) -> date: ...


class SystemClock:
    """Production clock: the local calendar day."""

    def today(self) -> date:
        return date.today()


class FixedClock:
    """Test clock: a day that only changes when told to."""

    def __init__(self, today: date) -> None:
        self._today = today

    def today(self) -> date:
        return self._today

    def set(self, today: date) -> None:
        self._today = today

    def advance(self, days: int = 1) -> date:
        self._today = self._today + timedelta(days=days)
        return self._today
