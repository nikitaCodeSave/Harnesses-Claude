"""Application service: the only place that changes stock or order state."""

from __future__ import annotations

from collections.abc import Mapping

from .clock import Clock
from .errors import (
    InsufficientStock,
    InvalidOrder,
    InvalidOrderState,
    InvalidQuantity,
)
from .ledger import Ledger
from .models import Adjustment, AdjustmentReason, Order, OrderLine, OrderStatus
from .repository import InMemoryRepository


class InventoryService:
    """Stock bookkeeping per (SKU, warehouse).

    * on-hand   -- physical units, derived from the ledger;
    * allocated -- units promised to PLACED orders (not yet shipped);
    * available -- what can still be promised: on-hand minus allocated.
    """

    def __init__(self, repository: InMemoryRepository, ledger: Ledger, clock: Clock) -> None:
        self._repo = repository
        self._ledger = ledger
        self._clock = clock

    # -- queries ---------------------------------------------------------
    def on_hand(self, sku: str, warehouse: str) -> int:
        self._check_location(sku, warehouse)
        return self._ledger.balance(sku, warehouse)

    def allocated(self, sku: str, warehouse: str) -> int:
        self._check_location(sku, warehouse)
        return sum(
            order.quantity_of(sku)
            for order in self._repo.orders(warehouse=warehouse, status=OrderStatus.PLACED)
        )

    def available(self, sku: str, warehouse: str) -> int:
        """Units that can still be promised. Never negative."""
        return max(0, self.on_hand(sku, warehouse) - self.allocated(sku, warehouse))

    # -- physical movements ---------------------------------------------
    def receive(self, sku: str, warehouse: str, quantity: int, ref: str | None = None) -> Adjustment:
        self._check_location(sku, warehouse)
        _check_quantity(quantity)
        return self._ledger.record(
            sku, warehouse, quantity, AdjustmentReason.RECEIPT, self._clock.now(), ref=ref
        )

    def adjust(self, sku: str, warehouse: str, delta: int, note: str) -> Adjustment:
        """Stock-count correction or write-off. On-hand can never drop below zero."""
        self._check_location(sku, warehouse)
        if isinstance(delta, bool) or not isinstance(delta, int) or delta == 0:
            raise InvalidQuantity(delta, "must be a non-zero integer")
        current = self._ledger.balance(sku, warehouse)
        if current + delta < 0:
            raise InsufficientStock(sku, warehouse, -delta, current)
        return self._ledger.record(
            sku, warehouse, delta, AdjustmentReason.ADJUSTMENT, self._clock.now(), note=note
        )

    # -- orders ----------------------------------------------------------
    def place_order(self, warehouse: str, items: Mapping[str, int]) -> Order:
        """Allocate stock for a new order. All lines or nothing."""
        wanted = self._validate_items(warehouse, items)
        for sku, quantity in wanted.items():
            free = self.available(sku, warehouse)
            if quantity > free:
                raise InsufficientStock(sku, warehouse, quantity, free)
        order = Order(
            order_id=self._repo.next_order_id(),
            warehouse=warehouse,
            lines=tuple(OrderLine(sku, qty) for sku, qty in wanted.items()),
            status=OrderStatus.PLACED,
            placed_at=self._clock.now(),
        )
        self._repo.save_order(order)
        return order

    def ship_order(self, order_id: str) -> Order:
        order = self._repo.get_order(order_id)
        if order.status is not OrderStatus.PLACED:
            raise InvalidOrderState(order_id, order.status, "ship")
        for line in order.lines:
            physical = self._ledger.balance(line.sku, order.warehouse)
            if line.quantity > physical:
                raise InsufficientStock(line.sku, order.warehouse, line.quantity, physical)
        now = self._clock.now()
        for line in order.lines:
            self._ledger.record(
                line.sku, order.warehouse, -line.quantity, AdjustmentReason.SHIPMENT, now,
                ref=order.order_id,
            )
        order.status = OrderStatus.SHIPPED
        order.closed_at = now
        self._repo.save_order(order)
        return order

    def cancel_order(self, order_id: str) -> Order:
        order = self._repo.get_order(order_id)
        if order.status is not OrderStatus.PLACED:
            raise InvalidOrderState(order_id, order.status, "cancel")
        order.status = OrderStatus.CANCELLED
        order.closed_at = self._clock.now()
        self._repo.save_order(order)
        return order

    # -- helpers ---------------------------------------------------------
    def _check_location(self, sku: str, warehouse: str) -> None:
        self._repo.get_warehouse(warehouse)
        self._repo.get_product(sku)

    def _validate_items(self, warehouse: str, items: Mapping[str, int]) -> dict[str, int]:
        self._repo.get_warehouse(warehouse)
        if not items:
            raise InvalidOrder("an order needs at least one line")
        for sku, quantity in items.items():
            self._repo.get_product(sku)
            _check_quantity(quantity)
        return dict(items)


def _check_quantity(quantity: object) -> None:
    if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity <= 0:
        raise InvalidQuantity(quantity)
