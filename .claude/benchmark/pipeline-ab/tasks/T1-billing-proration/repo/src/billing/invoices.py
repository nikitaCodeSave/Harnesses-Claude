"""Invoices and their line items."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from billing.errors import InvoiceError
from billing.money import ZERO, is_whole_cents, to_money


@dataclass(frozen=True)
class LineItem:
    description: str
    amount: Decimal

    def __post_init__(self) -> None:
        if not isinstance(self.amount, Decimal):
            raise InvoiceError(f"line {self.description!r}: amount must be a Decimal")
        if not is_whole_cents(self.amount):
            raise InvoiceError(f"line {self.description!r}: amount {self.amount} is not in whole cents")
        object.__setattr__(self, "amount", to_money(self.amount))


@dataclass(frozen=True)
class Invoice:
    id: str
    subscription_id: str
    customer_id: str
    issued_on: date
    lines: tuple[LineItem, ...]

    def __post_init__(self) -> None:
        if not self.lines:
            raise InvoiceError(f"invoice {self.id} has no lines")

    @property
    def total(self) -> Decimal:
        return to_money(sum((line.amount for line in self.lines), ZERO))
