"""Hidden regression oracle for T2: pre-existing behaviour the reservation feature could break.

Uses only the pre-existing public API; passes on the pristine repo.
"""

from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from inventory.clock import FixedClock
from inventory.errors import (
    InsufficientStock,
    InvalidOrder,
    InvalidOrderState,
    InvalidQuantity,
    OrderNotFound,
    UnknownSku,
)
from inventory.ledger import Ledger
from inventory.models import AdjustmentReason, OrderStatus, Product, Warehouse
from inventory.repository import InMemoryRepository
from inventory.service import InventoryService

START = datetime(2024, 3, 1, 9, 0, tzinfo=timezone.utc)


@pytest.fixture
def w():
    """WH1: A=10, B=5, C=0.  WH2: A=7."""
    repo = InMemoryRepository()
    repo.add_warehouse(Warehouse("WH1", "Main"))
    repo.add_warehouse(Warehouse("WH2", "Overflow"))
    for sku in ("A", "B", "C"):
        repo.add_product(Product(sku, f"Product {sku}"))
    ledger = Ledger()
    clock = FixedClock(START)
    svc = InventoryService(repo, ledger, clock)
    svc.receive("A", "WH1", 10)
    svc.receive("B", "WH1", 5)
    svc.receive("A", "WH2", 7)
    return SimpleNamespace(svc=svc, repo=repo, ledger=ledger, clock=clock)


# -- physical stock ---------------------------------------------------------


def test_receive_adds_to_on_hand(w):
    """Receiving stock increases on-hand by the received quantity."""
    w.svc.receive("A", "WH1", 4)
    assert w.svc.on_hand("A", "WH1") == 14


def test_receive_records_receipt_at_clock_time(w):
    """A receipt is a RECEIPT ledger entry stamped with the injected clock and carrying its ref."""
    w.clock.advance(minutes=5)
    entry = w.svc.receive("C", "WH1", 3, ref="PO-7")
    assert (entry.reason, entry.at, entry.ref, entry.delta) == (
        AdjustmentReason.RECEIPT, w.clock.now(), "PO-7", 3,
    )


def test_receive_rejects_non_positive_quantity(w):
    """Receiving zero units raises InvalidQuantity."""
    with pytest.raises(InvalidQuantity):
        w.svc.receive("A", "WH1", 0)


def test_writeoff_reduces_on_hand(w):
    """A negative adjustment reduces on-hand and is recorded as ADJUSTMENT with its note."""
    entry = w.svc.adjust("A", "WH1", -3, note="damaged")
    assert (w.svc.on_hand("A", "WH1"), entry.reason, entry.note) == (7, AdjustmentReason.ADJUSTMENT, "damaged")


def test_writeoff_cannot_take_on_hand_below_zero(w):
    """A write-off larger than on-hand raises InsufficientStock and records nothing."""
    before = len(w.ledger.entries())
    with pytest.raises(InsufficientStock):
        w.svc.adjust("B", "WH1", -6, note="lost")
    assert len(w.ledger.entries()) == before


def test_stock_is_independent_per_warehouse(w):
    """Stock in one warehouse does not affect another."""
    w.svc.place_order("WH2", {"A": 7})
    assert (w.svc.available("A", "WH1"), w.svc.available("A", "WH2")) == (10, 0)


# -- orders -----------------------------------------------------------------


def test_place_order_allocates_without_ledger_entry(w):
    """Placing an order lowers available, leaves on-hand alone and writes nothing to the ledger."""
    before = len(w.ledger.entries())
    w.svc.place_order("WH1", {"A": 4})
    assert (w.svc.available("A", "WH1"), w.svc.on_hand("A", "WH1"), len(w.ledger.entries())) == (6, 10, before)


def test_place_order_is_all_or_nothing(w):
    """If any line is short, place_order raises InsufficientStock and no order is created."""
    with pytest.raises(InsufficientStock):
        w.svc.place_order("WH1", {"A": 2, "B": 6})
    assert (w.repo.orders(), w.svc.available("A", "WH1")) == ([], 10)


def test_place_order_unknown_sku(w):
    """An order line for an unknown SKU raises UnknownSku."""
    with pytest.raises(UnknownSku):
        w.svc.place_order("WH1", {"NOPE": 1})


def test_place_order_rejects_empty_order(w):
    """An order with no lines raises InvalidOrder."""
    with pytest.raises(InvalidOrder):
        w.svc.place_order("WH1", {})


def test_placed_order_records_lines_and_time(w):
    """A placed order keeps its lines and is stamped with the clock time."""
    w.clock.advance(minutes=7)
    order = w.svc.place_order("WH1", {"A": 2, "B": 1})
    assert (order.status, {l.sku: l.quantity for l in order.lines}, order.placed_at) == (
        OrderStatus.PLACED, {"A": 2, "B": 1}, w.clock.now(),
    )


def test_order_ids_are_sequential(w):
    """Order ids are ORD-0001, ORD-0002, ... in placement order."""
    ids = [w.svc.place_order("WH1", {"A": 1}).order_id for _ in range(3)]
    assert ids == ["ORD-0001", "ORD-0002", "ORD-0003"]


def test_ship_order_writes_shipment_entries(w):
    """Shipping reduces on-hand via SHIPMENT ledger entries referencing the order."""
    order = w.svc.place_order("WH1", {"A": 3})
    w.svc.ship_order(order.order_id)
    last = w.ledger.entries(sku="A", warehouse="WH1")[-1]
    assert (w.svc.on_hand("A", "WH1"), last.reason, last.ref, last.delta) == (
        7, AdjustmentReason.SHIPMENT, order.order_id, -3,
    )


def test_ship_order_needs_physical_stock(w):
    """Shipping more than is physically on hand raises InsufficientStock and leaves the order PLACED."""
    order = w.svc.place_order("WH1", {"B": 5})
    w.svc.adjust("B", "WH1", -2, note="broken")
    with pytest.raises(InsufficientStock):
        w.svc.ship_order(order.order_id)
    assert w.repo.get_order(order.order_id).status == OrderStatus.PLACED


def test_cannot_ship_twice(w):
    """A shipped order cannot be shipped again."""
    order = w.svc.place_order("WH1", {"A": 1})
    w.svc.ship_order(order.order_id)
    with pytest.raises(InvalidOrderState):
        w.svc.ship_order(order.order_id)


def test_cancel_order_frees_allocation(w):
    """Cancelling a placed order makes its units available again."""
    order = w.svc.place_order("WH1", {"B": 5})
    w.svc.cancel_order(order.order_id)
    assert w.svc.available("B", "WH1") == 5


def test_cannot_cancel_shipped_order(w):
    """A shipped order cannot be cancelled."""
    order = w.svc.place_order("WH1", {"A": 1})
    w.svc.ship_order(order.order_id)
    with pytest.raises(InvalidOrderState):
        w.svc.cancel_order(order.order_id)


def test_writeoff_below_allocation_floors_available_at_zero(w):
    """Write-offs are not blocked by allocations; available never goes negative."""
    w.svc.place_order("WH1", {"A": 8})
    w.svc.adjust("A", "WH1", -5, note="flood")
    assert (w.svc.on_hand("A", "WH1"), w.svc.available("A", "WH1")) == (5, 0)


def test_unknown_order_id(w):
    """Operating on an unknown order raises OrderNotFound."""
    with pytest.raises(OrderNotFound):
        w.svc.cancel_order("ORD-9999")
