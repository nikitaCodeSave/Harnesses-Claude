"""Continuity tests: do F2 and F3 respect decisions announced in earlier features?

Every decision checked here was volunteered once by the owner in an earlier
feature's interview ("## Mention on your own" in features/F1/NOTES.md and
features/F2/NOTES.md) and is absent from the BRIEF and Rules of the feature
whose code it constrains. A test passes only if the decision survived.

Where the decision is about a threshold rather than an error class, either
reasonable error class is accepted, so the test measures the remembered
number, not a naming choice.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March. A book borrowed on 2 March is due Mon 23 March and
renewable from Wed 18 March. A copy returned on 3 March is set aside with
pickup_by Tue 10 March.
"""

from datetime import date
from decimal import Decimal as D

import pytest

import lending.errors as errors
from lending.clock import FixedClock
from lending.models import Material, MemberCategory
from lending.repository import InMemoryRepository
from lending.service import LendingService

START = date(2026, 3, 2)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    for member_id in ("ann", "bob", "cat"):
        s.register_member(member_id, member_id.title(), MemberCategory.ADULT)
    s.register_member("kid", "Kim", MemberCategory.CHILD)
    for isbn in ("HB", "H2", "TW", "OT"):
        s.add_title(isbn, f"Title {isbn}", Material.BOOK, D("30.00"))
    for copy_id, isbn in [
        ("HB-1", "HB"), ("H2-1", "H2"), ("TW-1", "TW"), ("TW-2", "TW"), ("OT-1", "OT"),
    ]:
        s.add_copy(copy_id, isbn)
    return s


def blocked_errors():
    """A money-based refusal of a hold or renewal: the BRIEFs allow either the
    feature's own refusal class or the existing AccountBlocked."""
    names = ("AccountBlocked", "HoldNotAllowed", "RenewalRefused")
    found = tuple(getattr(errors, n) for n in names if hasattr(errors, n))
    return found or (errors.AccountBlocked,)  # nothing exists yet: fail loudly


def uncollected_hold(svc, clock, member_id):
    """member_id's hold on HB becomes ready on 3 March and is never collected."""
    svc.checkout("bob", "HB-1")
    svc.place_hold(member_id, "HB")
    clock.set(date(2026, 3, 3))
    svc.return_copy("HB-1")
    clock.set(date(2026, 3, 11))
    svc.expire_holds()


# --- F1-L1: no new holds for a member owing 5.00 or more ---------------------


def test_member_owing_six_cannot_place_a_hold(svc):
    """F1-L1: owes 6.00 -> the hold is refused."""
    svc.checkout("bob", "HB-1")
    svc.add_charge("ann", D("6.00"), "damaged case")
    with pytest.raises(blocked_errors()):
        svc.place_hold("ann", "HB")


def test_owing_exactly_five_blocks_holds(svc):
    """F1-L1: '5.00 or more' — exactly 5.00 is refused."""
    svc.checkout("bob", "HB-1")
    svc.add_charge("ann", D("5.00"), "damaged case")
    with pytest.raises(blocked_errors()):
        svc.place_hold("ann", "HB")


def test_owing_under_five_can_place_a_hold(svc):
    """F1-L1: 4.75 is under the hold bar."""
    svc.checkout("bob", "HB-1")
    svc.add_charge("ann", D("4.75"), "damaged case")
    assert svc.place_hold("ann", "HB").member_id == "ann"


def test_refused_hold_does_not_join_the_queue(svc):
    """F1-L1 (with F2-N9): the refused hold leaves the queue empty."""
    svc.checkout("bob", "HB-1")
    svc.add_charge("ann", D("6.00"), "damaged case")
    try:
        svc.place_hold("ann", "HB")
    except errors.LendingError:
        pass
    assert svc.holds_for("HB") == []


# --- F1-L2: 1.00 no-show fee for an uncollected hold, children exempt ---------


def test_uncollected_hold_costs_an_adult_one(svc, clock):
    """F1-L2: not collected within the pickup time -> 1.00 on the balance."""
    uncollected_hold(svc, clock, "ann")
    assert svc.balance("ann") == D("1.00")


def test_children_never_pay_the_no_show_fee(svc, clock):
    """F1-L2: children never pay it."""
    uncollected_hold(svc, clock, "kid")
    assert svc.balance("kid") == D("0")


def test_collected_hold_costs_nothing(svc, clock):
    """F1-L2: only an uncollected hold is charged (collected on its pickup day)."""
    svc.checkout("bob", "HB-1")
    svc.place_hold("ann", "HB")
    clock.set(date(2026, 3, 3))
    svc.return_copy("HB-1")
    clock.set(date(2026, 3, 10))
    svc.checkout("ann", "HB-1")
    clock.set(date(2026, 3, 11))
    svc.expire_holds()
    assert svc.balance("ann") == D("0")


def test_no_show_fees_add_up(svc, clock):
    """F1-L2: two uncollected holds -> 2.00."""
    svc.checkout("bob", "HB-1")
    svc.checkout("bob", "H2-1")
    svc.place_hold("ann", "HB")
    svc.place_hold("ann", "H2")
    clock.set(date(2026, 3, 3))
    svc.return_copy("HB-1")
    svc.return_copy("H2-1")
    clock.set(date(2026, 3, 11))
    svc.expire_holds()
    assert svc.balance("ann") == D("2.00")


def test_no_show_fee_counts_toward_the_borrowing_block(svc, clock):
    """F1-L2 (with F1-N6): 9.00 owed + 1.00 no-show fee = 10.00 -> can't borrow."""
    svc.checkout("bob", "HB-1")
    svc.place_hold("ann", "HB")
    clock.set(date(2026, 3, 3))
    svc.return_copy("HB-1")
    svc.add_charge("ann", D("9.00"), "damaged case")
    clock.set(date(2026, 3, 11))
    svc.expire_holds()
    with pytest.raises(errors.AccountBlocked):
        svc.checkout("ann", "OT-1")


# --- F1-L3: renewing an overdue loan charges the lateness so far --------------


def test_overdue_renewal_charges_the_fine_so_far(svc, clock):
    """F1-L3: due Mon 23 March, renewed Thu 26 March -> 3 late days -> 0.75 now."""
    loan = svc.checkout("ann", "OT-1")
    clock.set(date(2026, 3, 26))
    svc.renew(loan.loan_id)
    assert svc.balance("ann") == D("0.75")


def test_lateness_before_a_renewal_is_charged_once(svc, clock):
    """F1-L3: back on time against the new due date -> still exactly 0.75."""
    loan = svc.checkout("ann", "OT-1")
    clock.set(date(2026, 3, 26))
    svc.renew(loan.loan_id)
    clock.set(date(2026, 4, 1))
    svc.return_copy("OT-1")
    assert svc.balance("ann") == D("0.75")


def test_child_overdue_renewal_is_free(svc, clock):
    """F1-L3: the usual child exemption applies."""
    loan = svc.checkout("kid", "OT-1")
    clock.set(date(2026, 3, 26))
    svc.renew(loan.loan_id)
    assert svc.balance("kid") == D("0")


def test_renewal_before_the_due_date_charges_nothing(svc, clock):
    """F1-L3: only lateness is charged."""
    loan = svc.checkout("ann", "OT-1")
    clock.set(date(2026, 3, 19))
    svc.renew(loan.loan_id)
    assert svc.balance("ann") == D("0")


# --- F2-L1: a waiting hold blocks renewal; a ready hold does not ---------------


def test_waiting_hold_blocks_renewal(svc, clock):
    """F2-L1: bob is waiting for HB -> ann can't renew her HB loan."""
    loan = svc.checkout("ann", "HB-1")
    svc.place_hold("bob", "HB")
    clock.set(date(2026, 3, 19))
    with pytest.raises(errors.RenewalRefused):
        svc.renew(loan.loan_id)


def test_ready_hold_does_not_block_renewal(svc, clock):
    """F2-L1: cat's hold is ready on the shelf (TW-2, pickup_by 25 March) and
    nobody else waits -> ann renews on 19 March."""
    loan = svc.checkout("ann", "TW-1")
    svc.checkout("bob", "TW-2")
    svc.place_hold("cat", "TW")
    clock.set(date(2026, 3, 18))
    svc.return_copy("TW-2")
    clock.set(date(2026, 3, 19))
    assert svc.renew(loan.loan_id).due_on == date(2026, 4, 9)


def test_cancelled_hold_no_longer_blocks_renewal(svc, clock):
    """F2-L1: nobody is waiting any more."""
    loan = svc.checkout("ann", "HB-1")
    hold = svc.place_hold("bob", "HB")
    svc.cancel_hold(hold.hold_id)
    clock.set(date(2026, 3, 19))
    assert svc.renew(loan.loan_id).renewals == 1


# --- F2-L2: renewals only for members who owe nothing when they ask ------------


def test_owing_anything_blocks_renewal(svc, clock):
    """F2-L2: owes 0.25 -> no renewal."""
    loan = svc.checkout("ann", "OT-1")
    svc.add_charge("ann", D("0.25"), "lost card")
    clock.set(date(2026, 3, 19))
    with pytest.raises(blocked_errors()):
        svc.renew(loan.loan_id)


def test_renewal_refused_for_money_changes_nothing(svc, clock):
    """F2-L2 (with F3-N8): the loan keeps its due date and count."""
    loan = svc.checkout("ann", "OT-1")
    svc.add_charge("ann", D("0.25"), "lost card")
    clock.set(date(2026, 3, 19))
    try:
        svc.renew(loan.loan_id)
    except errors.LendingError:
        pass
    current = svc.get_loan(loan.loan_id)
    assert (current.renewals, current.due_on) == (0, date(2026, 3, 23))


def test_paid_up_member_can_renew(svc, clock):
    """F2-L2: after paying everything off the renewal goes through."""
    loan = svc.checkout("ann", "OT-1")
    svc.add_charge("ann", D("0.25"), "lost card")
    svc.pay("ann", D("0.25"))
    clock.set(date(2026, 3, 19))
    assert svc.renew(loan.loan_id).due_on == date(2026, 4, 9)
