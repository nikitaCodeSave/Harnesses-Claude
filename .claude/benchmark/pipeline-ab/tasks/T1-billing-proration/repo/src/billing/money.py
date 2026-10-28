"""Money helpers.

Every amount in this package is a ``Decimal`` quantized to whole cents.
Floats are rejected outright: a float price is almost always a bug that
surfaces months later as a one-cent discrepancy on someone's invoice.
"""

from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal

CENT = Decimal("0.01")
ZERO = Decimal("0.00")


def to_money(value: Decimal | int | str) -> Decimal:
    """Return ``value`` as a Decimal rounded to cents (half up)."""
    if isinstance(value, (float, bool)):
        raise TypeError(f"money amounts must be Decimal, int or str, got {type(value).__name__}")
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def is_whole_cents(value: Decimal) -> bool:
    """True when ``value`` carries no precision below one cent."""
    return value == value.quantize(CENT, rounding=ROUND_HALF_UP)
