"""Subscriptions."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import Enum

from billing.plans import Interval


class SubscriptionStatus(Enum):
    TRIALING = "trialing"
    ACTIVE = "active"
    CANCELED = "canceled"


@dataclass(frozen=True)
class Subscription:
    """A customer's subscription to one plan.

    ``period_start``/``period_end`` describe the current period, half-open.
    While ``TRIALING`` the current period is the free trial; the first paid
    period starts on ``period_end``.

    Instances are immutable: build a changed copy with
    ``dataclasses.replace`` and save it through the store.
    """

    id: str
    customer_id: str
    plan_code: str
    interval: Interval
    status: SubscriptionStatus
    period_start: date
    period_end: date
    canceled_on: date | None = None

    def __post_init__(self) -> None:
        if self.period_end <= self.period_start:
            raise ValueError(f"{self.id}: period_end must be after period_start")

    @property
    def is_canceled(self) -> bool:
        return self.status is SubscriptionStatus.CANCELED
