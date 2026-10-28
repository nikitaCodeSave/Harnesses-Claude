import pytest

from inventory import AdjustmentReason
from inventory.errors import InsufficientStock, InvalidQuantity, UnknownSku, UnknownWarehouse


def test_receive_increases_on_hand(service):
    service.receive("MUG", "WH1", 12, ref="PO-1")
    assert service.on_hand("MUG", "WH1") == 12


def test_receive_records_timestamped_receipt(service, ledger, clock):
    service.receive("MUG", "WH1", 5)
    (entry,) = ledger.entries()
    assert (entry.reason, entry.at) == (AdjustmentReason.RECEIPT, clock.now())


def test_receive_rejects_non_positive_quantity(service):
    with pytest.raises(InvalidQuantity):
        service.receive("MUG", "WH1", 0)


def test_stock_is_tracked_per_warehouse(service):
    service.receive("MUG", "WH1", 4)
    assert service.on_hand("MUG", "WH2") == 0


def test_writeoff_cannot_go_below_zero(service):
    service.receive("MUG", "WH1", 2)
    with pytest.raises(InsufficientStock):
        service.adjust("MUG", "WH1", -3, note="broken")


def test_unknown_sku_and_warehouse_are_rejected(service):
    with pytest.raises(UnknownSku):
        service.on_hand("NOPE", "WH1")
    with pytest.raises(UnknownWarehouse):
        service.on_hand("MUG", "NOPE")
