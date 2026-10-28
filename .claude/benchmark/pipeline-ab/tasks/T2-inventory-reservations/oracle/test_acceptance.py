"""Hidden acceptance oracle for T2 — stock reservations with expiry.

Calls only the interface fixed in BRIEF.md plus pre-existing domain objects.
New names (ReservationStatus, the new errors) are looked up lazily so that a
missing name fails only the tests that need it, not the whole module.
Every docstring cites the BRIEF line or NOTES item it checks.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

import inventory.errors as errors
import inventory.models as models
from inventory.clock import FixedClock
from inventory.ledger import Ledger
from inventory.models import OrderStatus, Product, Warehouse
from inventory.repository import InMemoryRepository
from inventory.service import InventoryService

START = datetime(2024, 3, 1, 9, 0, tzinfo=timezone.utc)
TTL = timedelta(minutes=20)
ONE_SECOND = timedelta(seconds=1)


def status(name: str):
    return models.ReservationStatus[name]


def err(name: str) -> type[BaseException]:
    return getattr(errors, name)


def lines(order) -> dict[str, int]:
    return {line.sku: line.quantity for line in order.lines}


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


def reserve(w, items, key="k1", warehouse="WH1"):
    return w.svc.reserve(warehouse, items, idempotency_key=key)


def get(w, reservation):
    return w.svc.get_reservation(reservation.reservation_id)


def confirm(w, reservation):
    return w.svc.confirm_reservation(reservation.reservation_id)


def release(w, reservation):
    return w.svc.release_reservation(reservation.reservation_id)


# -- basics -----------------------------------------------------------------


def test_reserve_returns_active_reservation_holding_requested_units(w):
    """BRIEF reserve()/Reservation: an ACTIVE reservation for the warehouse, holding what was asked, no order yet."""
    r = reserve(w, {"A": 3, "B": 2})
    assert (r.status, r.warehouse, dict(r.items), r.order_id) == (
        status("ACTIVE"), "WH1", {"A": 3, "B": 2}, None,
    )


def test_available_subtracts_placed_orders_and_holds(w):
    """N1 (+ BRIEF available() takes holds into account): available = on-hand - allocated - held."""
    w.svc.place_order("WH1", {"A": 4})
    reserve(w, {"A": 3})
    assert w.svc.available("A", "WH1") == 3


def test_hold_lifecycle_never_touches_ledger_or_on_hand(w):
    """N2: reserve, release and confirm write no ledger entries and leave on-hand unchanged."""
    before = len(w.ledger.entries())
    release(w, reserve(w, {"A": 3}, key="k1"))
    confirm(w, reserve(w, {"A": 2}, key="k2"))
    assert (w.svc.on_hand("A", "WH1"), len(w.ledger.entries())) == (10, before)


def test_unknown_reservation_id_raises_not_found(w):
    """N11: get_reservation with an unknown id raises ReservationNotFound."""
    with pytest.raises(err("ReservationNotFound")):
        w.svc.get_reservation("no-such-reservation")


# -- partial holds (N3) -----------------------------------------------------


def test_short_line_holds_everything_available(w):
    """N3: a line asking for more than is available holds all that is available."""
    r = reserve(w, {"A": 12, "B": 2})
    assert dict(r.items) == {"A": 10, "B": 2}


def test_line_with_nothing_available_is_left_out(w):
    """N3: a line with nothing available is omitted from items; the other lines are still held."""
    r = reserve(w, {"A": 2, "C": 1})
    assert dict(r.items) == {"A": 2}


def test_later_reservation_gets_only_the_remainder(w):
    """N3 + N1: a later reservation holds only what earlier holds left available."""
    reserve(w, {"B": 4}, key="k1")
    r = reserve(w, {"B": 3}, key="k2")
    assert dict(r.items) == {"B": 1}


def test_nothing_available_raises_insufficient_stock(w):
    """N3: when no line can hold anything, reserve raises the existing InsufficientStock."""
    w.svc.place_order("WH1", {"B": 5})
    with pytest.raises(err("InsufficientStock")):
        reserve(w, {"B": 1, "C": 1})


# -- input validation (N4) --------------------------------------------------


def test_unknown_sku_rejects_the_whole_request(w):
    """N4: an unknown SKU raises UnknownSku and nothing is held, not even the valid line."""
    with pytest.raises(err("UnknownSku")):
        reserve(w, {"A": 2, "NOPE": 1})
    assert w.svc.available("A", "WH1") == 10


def test_non_positive_quantity_rejects_the_whole_request(w):
    """N4: a zero quantity raises InvalidQuantity and nothing is held."""
    with pytest.raises(err("InvalidQuantity")):
        reserve(w, {"A": 2, "B": 0})
    assert w.svc.available("A", "WH1") == 10


# -- expiry (N5) ------------------------------------------------------------


def test_expires_twenty_minutes_after_creation(w):
    """N5: expires_at = creation time + 20 minutes."""
    w.clock.advance(minutes=3)
    r = reserve(w, {"A": 1})
    assert r.expires_at == START + timedelta(minutes=23)


def test_still_active_and_held_one_second_before_expiry(w):
    """N5: one second before expires_at the reservation is ACTIVE and its units are still held."""
    r = reserve(w, {"A": 4})
    w.clock.advance(TTL - ONE_SECOND)
    assert (get(w, r).status, w.svc.available("A", "WH1")) == (status("ACTIVE"), 6)


def test_expired_exactly_at_expires_at(w):
    """N5: from expires_at on (inclusive) get_reservation reports EXPIRED."""
    r = reserve(w, {"A": 4})
    w.clock.advance(TTL)
    assert get(w, r).status == status("EXPIRED")


def test_expired_hold_frees_stock_without_a_sweep(w):
    """N5 + BRIEF (no background job): after the TTL the units are available again with no other call."""
    reserve(w, {"A": 4})
    w.clock.advance(TTL)
    assert w.svc.available("A", "WH1") == 10


def test_confirmed_reservation_never_expires(w):
    """N5: only ACTIVE reservations expire; a CONFIRMED one stays CONFIRMED after the TTL."""
    r = reserve(w, {"A": 4})
    confirm(w, r)
    w.clock.advance(hours=1)
    assert get(w, r).status == status("CONFIRMED")


# -- confirm (N6, N7) -------------------------------------------------------


def test_confirm_places_ordinary_order_for_held_units(w):
    """N6: confirm places a normal PLACED order (stored like any order) in the same warehouse for the held units."""
    r = reserve(w, {"A": 3, "B": 2})
    order = w.repo.get_order(confirm(w, r).order_id)
    assert (order.status, order.warehouse, lines(order)) == (OrderStatus.PLACED, "WH1", {"A": 3, "B": 2})


def test_confirm_marks_reservation_confirmed_with_order_id(w):
    """N6 + BRIEF order_id: after confirm the reservation is CONFIRMED and carries the order's id."""
    r = reserve(w, {"A": 3})
    order = confirm(w, r)
    got = get(w, r)
    assert (got.status, got.order_id) == (status("CONFIRMED"), order.order_id)


def test_confirm_does_not_change_available(w):
    """N6: the hold becomes the order's allocation, so available is the same before and after confirm."""
    r = reserve(w, {"A": 3})
    confirm(w, r)
    assert w.svc.available("A", "WH1") == 7


def test_confirm_partial_reservation_orders_only_held_units(w):
    """N3 + N6: confirming a partially filled reservation orders exactly the units that were held."""
    r = reserve(w, {"A": 12, "C": 1})
    assert lines(confirm(w, r)) == {"A": 10}


def test_confirm_one_second_before_expiry_succeeds(w):
    """N5 + N6: a reservation can still be confirmed one second before expires_at."""
    r = reserve(w, {"A": 2})
    w.clock.advance(TTL - ONE_SECOND)
    assert confirm(w, r).status == OrderStatus.PLACED


def test_confirm_at_expiry_raises_reservation_expired(w):
    """N7: confirming a reservation that has just lapsed raises ReservationExpired."""
    r = reserve(w, {"A": 2})
    w.clock.advance(TTL)
    with pytest.raises(err("ReservationExpired")):
        confirm(w, r)


def test_repeated_confirm_returns_the_same_order(w):
    """N6: confirming an already-CONFIRMED reservation returns the same order."""
    r = reserve(w, {"A": 3})
    first = confirm(w, r)
    assert confirm(w, r).order_id == first.order_id


def test_repeated_confirm_creates_no_second_order(w):
    """N6: a repeated confirm creates nothing: one order, its units allocated once."""
    r = reserve(w, {"A": 3})
    confirm(w, r)
    confirm(w, r)
    assert (len(w.repo.orders()), w.svc.available("A", "WH1")) == (1, 7)


def test_repeated_confirm_after_ttl_returns_the_same_order(w):
    """N6: a confirm retry arriving after the 20 minutes still returns the same order."""
    r = reserve(w, {"A": 3})
    w.clock.advance(minutes=1)
    first = confirm(w, r)
    w.clock.advance(minutes=30)
    assert confirm(w, r).order_id == first.order_id


def test_confirm_released_raises_invalid_state(w):
    """N7: confirming a RELEASED reservation raises InvalidReservationState."""
    r = reserve(w, {"A": 3})
    release(w, r)
    with pytest.raises(err("InvalidReservationState")):
        confirm(w, r)


# -- release (BRIEF, N7) ----------------------------------------------------


def test_release_marks_released_and_frees_stock(w):
    """BRIEF release_reservation + N1: the reservation is RELEASED and its units are available again."""
    r = reserve(w, {"A": 4})
    out = release(w, r)
    assert (out.status, w.svc.available("A", "WH1")) == (status("RELEASED"), 10)


def test_release_twice_is_a_no_op(w):
    """N7: releasing an already-RELEASED reservation returns it, still RELEASED, without error."""
    r = reserve(w, {"A": 4})
    release(w, r)
    assert release(w, r).status == status("RELEASED")


def test_release_of_expired_reservation_keeps_it_expired(w):
    """N7: releasing an EXPIRED reservation is a no-op without error; it stays EXPIRED."""
    r = reserve(w, {"A": 4})
    w.clock.advance(TTL)
    release(w, r)
    assert get(w, r).status == status("EXPIRED")


def test_release_confirmed_raises_invalid_state(w):
    """N7: releasing a CONFIRMED reservation raises InvalidReservationState."""
    r = reserve(w, {"A": 4})
    confirm(w, r)
    with pytest.raises(err("InvalidReservationState")):
        release(w, r)


# -- idempotency (N8) -------------------------------------------------------


def test_same_key_same_request_returns_existing_reservation(w):
    """N8: repeating reserve with the same key and request returns the same reservation; units held once."""
    first = reserve(w, {"A": 3})
    again = reserve(w, {"A": 3})
    assert (again.reservation_id, w.svc.available("A", "WH1")) == (first.reservation_id, 7)


def test_same_key_different_items_conflicts(w):
    """N8: the same key with different items raises IdempotencyConflict."""
    reserve(w, {"A": 3})
    with pytest.raises(err("IdempotencyConflict")):
        reserve(w, {"A": 4})


def test_same_key_different_warehouse_conflicts(w):
    """N8: keys are global, so the same key and items in another warehouse raise IdempotencyConflict."""
    reserve(w, {"A": 3}, warehouse="WH1")
    with pytest.raises(err("IdempotencyConflict")):
        reserve(w, {"A": 3}, warehouse="WH2")


def test_replay_of_partially_filled_request_is_not_a_conflict(w):
    """N8 + N3: a replay is compared on the requested items, not on what ended up held."""
    first = reserve(w, {"A": 12})
    assert reserve(w, {"A": 12}).reservation_id == first.reservation_id


def test_replay_after_release_returns_released_reservation(w):
    """N8: a replay after release returns that RELEASED reservation and holds nothing new."""
    first = reserve(w, {"A": 3})
    release(w, first)
    again = reserve(w, {"A": 3})
    assert (again.reservation_id, again.status, w.svc.available("A", "WH1")) == (
        first.reservation_id, status("RELEASED"), 10,
    )


def test_replay_does_not_extend_expiry(w):
    """N8: a replay does not move expires_at."""
    deadline = reserve(w, {"A": 3}).expires_at  # a value, so in-place mutation can't hide a change
    w.clock.advance(minutes=10)
    assert reserve(w, {"A": 3}).expires_at == deadline


def test_failed_reserve_leaves_its_key_free(w):
    """N8: a reserve that failed leaves no trace, so the same key works once stock arrives."""
    with pytest.raises(err("InsufficientStock")):
        reserve(w, {"C": 2})
    w.svc.receive("C", "WH1", 5)
    assert dict(reserve(w, {"C": 2}).items) == {"C": 2}


# -- interplay with existing stock operations (N9, N10) ---------------------


def test_place_order_cannot_take_held_units(w):
    """N9: place_order only takes available stock; held units are off-limits."""
    reserve(w, {"B": 4})
    with pytest.raises(err("InsufficientStock")):
        w.svc.place_order("WH1", {"B": 2})


def test_writeoff_below_held_is_allowed_and_available_floors_at_zero(w):
    """N10: adjust is never blocked by holds; when on-hand drops below what is held, available is 0."""
    reserve(w, {"A": 8})
    w.svc.adjust("A", "WH1", -5, note="water damage")
    assert (w.svc.on_hand("A", "WH1"), w.svc.available("A", "WH1")) == (5, 0)
