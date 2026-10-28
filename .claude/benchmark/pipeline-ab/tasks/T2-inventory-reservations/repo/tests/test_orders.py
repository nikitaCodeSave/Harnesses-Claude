import pytest

from inventory import OrderStatus
from inventory.errors import InsufficientStock, InvalidOrder, InvalidOrderState, OrderNotFound


@pytest.fixture
def stocked(service):
    service.receive("MUG", "WH1", 10)
    service.receive("TEE", "WH1", 5)
    return service


def test_place_order_allocates_without_moving_stock(stocked):
    stocked.place_order("WH1", {"MUG": 4})
    assert (stocked.on_hand("MUG", "WH1"), stocked.available("MUG", "WH1")) == (10, 6)


def test_place_order_is_all_or_nothing(stocked, repo):
    with pytest.raises(InsufficientStock):
        stocked.place_order("WH1", {"MUG": 2, "TEE": 6})
    assert repo.orders() == []


def test_order_ids_are_sequential(stocked):
    first = stocked.place_order("WH1", {"MUG": 1})
    second = stocked.place_order("WH1", {"MUG": 1})
    assert (first.order_id, second.order_id) == ("ORD-0001", "ORD-0002")


def test_empty_order_is_rejected(stocked):
    with pytest.raises(InvalidOrder):
        stocked.place_order("WH1", {})


def test_ship_order_writes_shipment_and_reduces_on_hand(stocked, ledger):
    order = stocked.place_order("WH1", {"MUG": 3})
    stocked.ship_order(order.order_id)
    assert stocked.on_hand("MUG", "WH1") == 7
    assert ledger.entries(sku="MUG")[-1].ref == order.order_id


def test_cancel_order_frees_allocation(stocked):
    order = stocked.place_order("WH1", {"TEE": 5})
    stocked.cancel_order(order.order_id)
    assert stocked.available("TEE", "WH1") == 5


def test_cannot_cancel_shipped_order(stocked):
    order = stocked.place_order("WH1", {"MUG": 1})
    stocked.ship_order(order.order_id)
    with pytest.raises(InvalidOrderState):
        stocked.cancel_order(order.order_id)


def test_shipped_order_is_closed_at_clock_time(stocked, clock):
    order = stocked.place_order("WH1", {"MUG": 1})
    clock.advance(hours=2)
    shipped = stocked.ship_order(order.order_id)
    assert (shipped.status, shipped.closed_at) == (OrderStatus.SHIPPED, clock.now())


def test_unknown_order_is_reported(stocked):
    with pytest.raises(OrderNotFound):
        stocked.ship_order("ORD-9999")
