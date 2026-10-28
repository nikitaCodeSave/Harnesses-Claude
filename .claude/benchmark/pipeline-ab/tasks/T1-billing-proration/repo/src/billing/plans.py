"""Plans and billing intervals."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from enum import Enum

from billing.errors import InvalidPlan
from billing.money import is_whole_cents, to_money


class Interval(Enum):
    MONTHLY = "monthly"
    ANNUAL = "annual"

    @property
    def months(self) -> int:
        return 1 if self is Interval.MONTHLY else 12


@dataclass(frozen=True)
class Plan:
    """A sellable plan with a list price per billing interval.

    Retired plans (``active=False``) cannot be sold to anyone new, but
    customers already on them keep being billed at the plan's price.
    """

    code: str
    name: str
    monthly_price: Decimal
    annual_price: Decimal
    active: bool = True

    def __post_init__(self) -> None:
        if not self.code or not self.code.strip():
            raise InvalidPlan("plan code is required")
        for field_name in ("monthly_price", "annual_price"):
            value = getattr(self, field_name)
            if not isinstance(value, Decimal):
                raise InvalidPlan(f"{self.code}: {field_name} must be a Decimal")
            if value < 0:
                raise InvalidPlan(f"{self.code}: {field_name} must not be negative")
            if not is_whole_cents(value):
                raise InvalidPlan(f"{self.code}: {field_name} has sub-cent precision")
            object.__setattr__(self, field_name, to_money(value))

    def price_for(self, interval: Interval) -> Decimal:
        """List price for one full period of ``interval``."""
        return self.monthly_price if interval is Interval.MONTHLY else self.annual_price
