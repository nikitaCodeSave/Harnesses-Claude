"""Hidden acceptance tests for F1 — overdue fines and member accounts.

Each test cites the BRIEF line or rule (features/F1/NOTES.md) it checks.
Symbols introduced by the feature are looked up at call time, so a missing
interface fails the test instead of breaking collection.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March. A book borrowed on 2 March is due Mon 23 March,
a DVD borrowed on 2 March is due Mon 9 March.
"""

from datetime import date
from decimal import Decimal as D

import pytest

import lending.errors as errors
from lending.clock import FixedClock
from lending.models import CopyStatus, Material, MemberCategory
from lending.repository import InMemoryRepository
from lending.service import LendingService

START = date(2026, 3, 2)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    s.register_member("ann", "Ann", MemberCategory.ADULT)
    s.register_member("kid", "Kim", MemberCategory.CHILD)
    s.add_title("BK", "Book", Material.BOOK, D("30.00"))
    s.add_title("DV", "Film", Material.DVD, D("15.00"))
    s.add_title("OT", "Other book", Material.BOOK, D("20.00"))
    for copy_id, isbn in [("BK-1", "BK"), ("DV-1", "DV"), ("OT-1", "OT")]:
        s.add_copy(copy_id, isbn)
    return s


def late_return(svc, clock, member_id, copy_id, back_on):
    svc.checkout(member_id, copy_id)
    clock.set(back_on)
    return svc.return_copy(copy_id)


# --- fines -----------------------------------------------------------------


def test_book_costs_a_quarter_per_late_day(svc, clock):
    """F1-N1, F1-N2: book due 23 March back 24 March -> 1 late day -> 0.25."""
    late_return(svc, clock, "ann", "BK-1", date(2026, 3, 24))
    assert svc.balance("ann") == D("0.25")


def test_dvd_costs_one_per_late_day(svc, clock):
    """F1-N1, F1-N2: DVD due 9 March back 11 March -> 2 late days -> 2.00."""
    late_return(svc, clock, "ann", "DV-1", date(2026, 3, 11))
    assert svc.balance("ann") == D("2.00")


def test_return_on_the_due_date_is_free(svc, clock):
    """F1-N2: back on the due date -> no fine."""
    late_return(svc, clock, "ann", "BK-1", date(2026, 3, 23))
    assert svc.balance("ann") == D("0")


def test_sundays_are_not_counted_as_late_days(svc, clock):
    """F1-N2 example: due Mon 23 March, back Mon 30 March -> 6 late days -> 1.50."""
    late_return(svc, clock, "ann", "BK-1", date(2026, 3, 30))
    assert svc.balance("ann") == D("1.50")


def test_fine_is_capped_at_replacement_cost(svc, clock):
    """F1-N3: DVD (replacement 15.00) back seven weeks late -> 15.00, not more."""
    late_return(svc, clock, "ann", "DV-1", date(2026, 4, 30))
    assert svc.balance("ann") == D("15.00")


def test_children_are_never_fined(svc, clock):
    """F1-N4: a child's late return charges nothing."""
    late_return(svc, clock, "kid", "DV-1", date(2026, 3, 20))
    assert svc.balance("kid") == D("0")


def test_overdue_loan_still_out_adds_nothing(svc, clock):
    """F1-N5: fines are charged when the copy comes back, not while it is out."""
    svc.checkout("ann", "DV-1")
    clock.set(date(2026, 3, 20))
    assert svc.balance("ann") == D("0")


def test_fines_from_several_returns_add_up(svc, clock):
    """F1-N5: each late return adds its own fine (0.25 + 2.00)."""
    svc.checkout("ann", "BK-1")
    svc.checkout("ann", "DV-1")
    clock.set(date(2026, 3, 11))
    svc.return_copy("DV-1")
    clock.set(date(2026, 3, 24))
    svc.return_copy("BK-1")
    assert svc.balance("ann") == D("2.25")


# --- balance, charges, payments ---------------------------------------------


def test_new_member_owes_nothing(svc):
    """F1 BRIEF: balance(member_id) is what the member owes right now."""
    assert svc.balance("ann") == D("0")


def test_balance_of_unknown_member(svc):
    """F1 BRIEF: unknown members keep raising MemberNotFound."""
    with pytest.raises(errors.MemberNotFound):
        svc.balance("nobody")


def test_add_charge_returns_new_balance(svc):
    """F1 BRIEF / F1-N8: add_charge returns the new balance."""
    svc.add_charge("ann", D("2.50"), "damaged case")
    assert svc.add_charge("ann", D("1.25"), "lost card") == D("3.75")


def test_manual_charges_share_the_balance_with_fines(svc, clock):
    """F1-N8: manual charges go on the same balance as fines."""
    late_return(svc, clock, "ann", "BK-1", date(2026, 3, 24))
    svc.add_charge("ann", D("1.00"), "lost card")
    assert svc.balance("ann") == D("1.25")


def test_non_positive_charge_is_rejected(svc):
    """F1-N8, F1-N9: a negative charge is InvalidAmount and changes nothing."""
    with pytest.raises(errors.InvalidAmount):
        svc.add_charge("ann", D("-1.00"), "refund")
    assert svc.balance("ann") == D("0")


def test_partial_payment_returns_what_is_still_owed(svc):
    """F1-N7: partial payments are fine; pay returns what is still owed."""
    svc.add_charge("ann", D("4.00"), "lost card")
    assert svc.pay("ann", D("1.50")) == D("2.50")
    assert svc.balance("ann") == D("2.50")


def test_overpayment_is_rejected(svc):
    """F1-N7, F1-N9: paying more than is owed is InvalidAmount; balance unchanged."""
    svc.add_charge("ann", D("1.00"), "lost card")
    with pytest.raises(errors.InvalidAmount):
        svc.pay("ann", D("1.01"))
    assert svc.balance("ann") == D("1.00")


def test_payment_with_nothing_owed_is_rejected(svc):
    """F1-N7: no credit on accounts."""
    with pytest.raises(errors.InvalidAmount):
        svc.pay("ann", D("1.00"))


def test_zero_payment_is_rejected(svc):
    """F1-N7: a payment must be positive."""
    svc.add_charge("ann", D("1.00"), "lost card")
    with pytest.raises(errors.InvalidAmount):
        svc.pay("ann", D("0"))


def test_fraction_of_a_cent_is_rejected(svc):
    """F1-N7: whole cents only."""
    svc.add_charge("ann", D("2.00"), "lost card")
    with pytest.raises(errors.InvalidAmount):
        svc.pay("ann", D("1.005"))


# --- the borrowing block ------------------------------------------------------


def test_owing_exactly_ten_blocks_checkout(svc):
    """F1-N6: balance of 10.00 or more -> AccountBlocked."""
    svc.add_charge("ann", D("10.00"), "damaged case")
    with pytest.raises(errors.AccountBlocked):
        svc.checkout("ann", "OT-1")


def test_owing_just_under_ten_can_borrow(svc):
    """F1-N6: 9.99 is under the bar."""
    svc.add_charge("ann", D("9.99"), "damaged case")
    assert svc.checkout("ann", "OT-1").copy_id == "OT-1"


def test_fines_count_toward_the_block(svc, clock):
    """F1-N3, F1-N6: a capped 15.00 fine blocks borrowing."""
    late_return(svc, clock, "ann", "DV-1", date(2026, 4, 30))
    with pytest.raises(errors.AccountBlocked):
        svc.checkout("ann", "OT-1")


def test_blocked_checkout_changes_nothing(svc):
    """F1-N9: no loan created, copy stays on the shelf."""
    svc.add_charge("ann", D("12.00"), "damaged case")
    with pytest.raises(errors.AccountBlocked):
        svc.checkout("ann", "OT-1")
    assert svc.get_copy("OT-1").status is CopyStatus.AVAILABLE
    assert svc.open_loans("ann") == []


def test_blocked_member_can_still_return(svc, clock):
    """F1-N6: returning always works, even while blocked."""
    svc.checkout("ann", "OT-1")
    svc.add_charge("ann", D("12.00"), "damaged case")
    clock.set(date(2026, 3, 10))
    svc.return_copy("OT-1")
    assert svc.get_copy("OT-1").status is CopyStatus.AVAILABLE


def test_paying_below_the_bar_unblocks(svc):
    """F1-N6, F1-N7: paying always works and lowers the balance under the bar."""
    svc.add_charge("ann", D("10.00"), "damaged case")
    svc.pay("ann", D("0.01"))
    assert svc.checkout("ann", "OT-1").copy_id == "OT-1"
