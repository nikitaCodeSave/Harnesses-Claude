import pytest

from inventory import AdjustmentReason
from inventory.errors import InvalidQuantity


def test_balance_is_sum_of_entries(ledger, clock):
    ledger.record("MUG", "WH1", 10, AdjustmentReason.RECEIPT, clock.now())
    ledger.record("MUG", "WH1", -3, AdjustmentReason.ADJUSTMENT, clock.now())
    assert ledger.balance("MUG", "WH1") == 7


def test_entries_filter_by_sku_and_warehouse(ledger, clock):
    ledger.record("MUG", "WH1", 1, AdjustmentReason.RECEIPT, clock.now())
    ledger.record("MUG", "WH2", 2, AdjustmentReason.RECEIPT, clock.now())
    ledger.record("TEE", "WH1", 3, AdjustmentReason.RECEIPT, clock.now())
    assert [e.delta for e in ledger.entries(sku="MUG", warehouse="WH2")] == [2]


def test_entry_ids_are_sequential(ledger, clock):
    first = ledger.record("MUG", "WH1", 1, AdjustmentReason.RECEIPT, clock.now())
    second = ledger.record("MUG", "WH1", 1, AdjustmentReason.RECEIPT, clock.now())
    assert (first.entry_id, second.entry_id) == ("ADJ-000001", "ADJ-000002")


def test_zero_delta_is_rejected(ledger, clock):
    with pytest.raises(InvalidQuantity):
        ledger.record("MUG", "WH1", 0, AdjustmentReason.ADJUSTMENT, clock.now())
