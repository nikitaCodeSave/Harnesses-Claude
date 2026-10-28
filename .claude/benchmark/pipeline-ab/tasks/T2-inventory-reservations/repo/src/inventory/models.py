"""Domain records."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum


@dataclass(frozen=True)
class Product:
    sku: str
    name: str
    unit: str = "each"


@dataclass(frozen=True)
class Warehouse:
    code: str
    name: str


class OrderStatus(Enum):
    PLACED = "placed"
    SHIPPED = "shipped"
    CANCELLED = "cancelled"


@dataclass(frozen=True)
class OrderLine:
    sku: str
    quantity: int


@dataclass
class Order:
    """A customer order fulfilled from a single warehouse.

    A PLACED order allocates its quantities (they are no longer available to
    other orders) but physical stock only leaves on shipment.
    """

    order_id: str
    warehouse: str
    lines: tuple[OrderLine, ...]
    status: OrderStatus
    placed_at: datetime
    closed_at: datetime | None = None

    def quantity_of(self, sku: str) -> int:
        return sum(line.quantity for line in self.lines if line.sku == sku)


class AdjustmentReason(Enum):
    RECEIPT = "receipt"
    ADJUSTMENT = "adjustment"
    SHIPMENT = "shipment"


@dataclass(frozen=True)
class Adjustment:
    """One physical stock movement. Positive delta = stock in."""

    entry_id: str
    sku: str
    warehouse: str
    delta: int
    reason: AdjustmentReason
    at: datetime
    ref: str | None = None
    note: str | None = None
