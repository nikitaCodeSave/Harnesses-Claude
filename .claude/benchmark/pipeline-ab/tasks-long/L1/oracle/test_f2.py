"""Hidden acceptance tests for F2 — holds.

Each test cites the BRIEF line or rule (features/F2/NOTES.md) it checks.
Symbols introduced by the feature are looked up at call time, so a missing
interface fails the test instead of breaking collection. Members here owe
nothing, so earlier money rules never interfere.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March. "HB" has a single copy; "TW" has two.
"""

from datetime import date
from decimal import Decimal as D

import pytest

import lending.errors as errors
import lending.models as models
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
    s.add_title("HB", "Hold book", Material.BOOK, D("30.00"))
    s.add_title("TW", "Twin book", Material.BOOK, D("30.00"))
    for copy_id, isbn in [("HB-1", "HB"), ("TW-1", "TW"), ("TW-2", "TW")]:
        s.add_copy(copy_id, isbn)
    return s


@pytest.fixture
def hb_out(svc):
    """HB's only copy is on loan to bob (due Mon 23 March)."""
    svc.checkout("bob", "HB-1")
    return svc


def status(name):
    return getattr(models.HoldStatus, name)


def copy_status(name):
    return getattr(models.CopyStatus, name)


# --- placing holds ---------------------------------------------------------


def test_hold_refused_while_a_copy_is_on_the_shelf(svc):
    """F2-N1: a copy is available -> HoldNotAllowed."""
    with pytest.raises(errors.HoldNotAllowed):
        svc.place_hold("ann", "HB")


def test_new_hold_waits_with_no_copy_or_pickup_date(hb_out):
    """F2-N3, BRIEF Hold fields: WAITING, placed today, no copy, no pickup date."""
    hold = hb_out.place_hold("ann", "HB")
    assert (hold.member_id, hold.isbn, hold.placed_on) == ("ann", "HB", START)
    assert hold.status is status("WAITING")
    assert hold.copy_id is None and hold.pickup_by is None


def test_hold_refused_when_every_copy_is_withdrawn(svc):
    """F2-N1: nothing will ever come back."""
    svc.withdraw_copy("HB-1")
    with pytest.raises(errors.HoldNotAllowed):
        svc.place_hold("ann", "HB")


def test_hold_on_unknown_title(svc):
    """F2-N1: unknown title -> TitleNotFound."""
    with pytest.raises(errors.TitleNotFound):
        svc.place_hold("ann", "NOPE")


def test_hold_by_unknown_member(hb_out):
    """F2-N1: unknown member -> MemberNotFound."""
    with pytest.raises(errors.MemberNotFound):
        hb_out.place_hold("nobody", "HB")


def test_second_hold_on_same_title_refused(hb_out):
    """F2-N2: one active hold per member per title."""
    hb_out.place_hold("ann", "HB")
    with pytest.raises(errors.HoldNotAllowed):
        hb_out.place_hold("ann", "HB")


def test_member_cannot_hold_a_title_they_have_on_loan(hb_out):
    """F2-N2: bob has HB on loan."""
    with pytest.raises(errors.HoldNotAllowed):
        hb_out.place_hold("bob", "HB")


def test_refused_hold_changes_nothing(hb_out):
    """F2-N9: a refused duplicate leaves the queue as it was."""
    hb_out.place_hold("ann", "HB")
    with pytest.raises(errors.HoldNotAllowed):
        hb_out.place_hold("ann", "HB")
    assert [h.member_id for h in hb_out.holds_for("HB")] == ["ann"]


def test_queue_is_first_come_first_served(hb_out, clock):
    """F2-N3, F2-N8: holds_for lists the queue in placement order."""
    hb_out.place_hold("cat", "HB")
    clock.advance(1)
    hb_out.place_hold("kid", "HB")
    hb_out.place_hold("ann", "HB")
    assert [h.member_id for h in hb_out.holds_for("HB")] == ["cat", "kid", "ann"]


# --- copies coming back ------------------------------------------------------


def test_returned_copy_goes_to_the_hold_shelf(hb_out, clock):
    """F2-N4: copy ON_HOLD_SHELF, first hold READY with that copy."""
    hold = hb_out.place_hold("ann", "HB")
    clock.set(date(2026, 3, 10))
    hb_out.return_copy("HB-1")
    assert hb_out.get_copy("HB-1").status is copy_status("ON_HOLD_SHELF")
    assert hold.status is status("READY")
    assert hold.copy_id == "HB-1"


def test_pickup_window_is_seven_days(hb_out, clock):
    """F2-N4: returned Tue 10 March -> pickup_by Tue 17 March."""
    hold = hb_out.place_hold("ann", "HB")
    clock.set(date(2026, 3, 10))
    hb_out.return_copy("HB-1")
    assert hold.pickup_by == date(2026, 3, 17)


def test_pickup_window_ending_on_sunday_moves_to_monday(hb_out, clock):
    """F2-N4: dropped back Sun 8 March -> +7 is Sun 15 -> pickup_by Mon 16 March."""
    hold = hb_out.place_hold("ann", "HB")
    clock.set(date(2026, 3, 8))
    hb_out.return_copy("HB-1")
    assert hold.pickup_by == date(2026, 3, 16)


def test_only_the_first_waiting_hold_gets_the_copy(hb_out):
    """F2-N4: the second in line keeps waiting."""
    first = hb_out.place_hold("ann", "HB")
    second = hb_out.place_hold("cat", "HB")
    hb_out.return_copy("HB-1")
    assert first.status is status("READY")
    assert second.status is status("WAITING")


def test_copy_with_nobody_waiting_goes_back_on_the_shelf(svc):
    """F2-N4: a hold on another title doesn't catch this copy."""
    svc.checkout("bob", "HB-1")
    svc.checkout("ann", "TW-1")
    svc.checkout("cat", "TW-2")
    svc.place_hold("kid", "TW")
    svc.return_copy("HB-1")
    assert svc.get_copy("HB-1").status is copy_status("AVAILABLE")


def test_set_aside_copy_is_not_for_anyone_else(hb_out):
    """F2-N5: someone other than the holder -> CopyNotAvailable."""
    hb_out.place_hold("ann", "HB")
    hb_out.return_copy("HB-1")
    with pytest.raises(errors.CopyNotAvailable):
        hb_out.checkout("cat", "HB-1")


def test_holder_checkout_fulfils_the_hold(hb_out):
    """F2-N5, F2-N8: hold FULFILLED and gone from the queue; the loan is theirs."""
    hold = hb_out.place_hold("ann", "HB")
    hb_out.return_copy("HB-1")
    loan = hb_out.checkout("ann", "HB-1")
    assert loan.member_id == "ann"
    assert hold.status is status("FULFILLED")
    assert hb_out.holds_for("HB") == []


# --- the daily job -------------------------------------------------------------


def test_ready_hold_expires_after_pickup_day(hb_out, clock):
    """F2-N6: returned Mon 2 March, pickup_by Mon 9 March, job on 10 March."""
    hold = hb_out.place_hold("ann", "HB")
    hb_out.return_copy("HB-1")
    clock.set(date(2026, 3, 10))
    assert [h.hold_id for h in hb_out.expire_holds()] == [hold.hold_id]
    assert hold.status is status("EXPIRED")


def test_hold_is_not_expired_on_its_pickup_day(hb_out, clock):
    """F2-N6: the pickup_by day itself is still fine."""
    hold = hb_out.place_hold("ann", "HB")
    hb_out.return_copy("HB-1")
    clock.set(date(2026, 3, 9))
    assert hb_out.expire_holds() == []
    assert hold.status is status("READY")


def test_expired_copy_goes_back_on_the_shelf(hb_out, clock):
    """F2-N6: nobody else waiting -> AVAILABLE."""
    hb_out.place_hold("ann", "HB")
    hb_out.return_copy("HB-1")
    clock.set(date(2026, 3, 10))
    hb_out.expire_holds()
    assert hb_out.get_copy("HB-1").status is copy_status("AVAILABLE")


def test_expired_copy_passes_to_the_next_in_line(hb_out, clock):
    """F2-N6: next hold READY with the copy, pickup_by = today + 7."""
    hb_out.place_hold("ann", "HB")
    nxt = hb_out.place_hold("cat", "HB")
    hb_out.return_copy("HB-1")
    clock.set(date(2026, 3, 10))
    hb_out.expire_holds()
    assert nxt.status is status("READY")
    assert (nxt.copy_id, nxt.pickup_by) == ("HB-1", date(2026, 3, 17))


def test_running_the_job_twice_expires_nothing_new(hb_out, clock):
    """F2-N6: running it again the same day expires nothing."""
    hb_out.place_hold("ann", "HB")
    hb_out.return_copy("HB-1")
    clock.set(date(2026, 3, 10))
    hb_out.expire_holds()
    assert hb_out.expire_holds() == []


# --- cancelling ------------------------------------------------------------------


def test_cancelled_waiting_hold_leaves_the_queue(hb_out):
    """F2-N7, F2-N8: CANCELLED and no longer listed."""
    hold = hb_out.place_hold("ann", "HB")
    assert hb_out.cancel_hold(hold.hold_id).status is status("CANCELLED")
    assert hb_out.holds_for("HB") == []


def test_cancelled_ready_hold_passes_the_copy_on(hb_out):
    """F2-N7: the copy moves on exactly as on expiry."""
    first = hb_out.place_hold("ann", "HB")
    nxt = hb_out.place_hold("cat", "HB")
    hb_out.return_copy("HB-1")
    hb_out.cancel_hold(first.hold_id)
    assert nxt.status is status("READY")
    assert nxt.copy_id == "HB-1"


def test_cancelling_an_inactive_hold_is_refused(hb_out):
    """F2-N7: a hold no longer active -> HoldNotAllowed."""
    hold = hb_out.place_hold("ann", "HB")
    hb_out.cancel_hold(hold.hold_id)
    with pytest.raises(errors.HoldNotAllowed):
        hb_out.cancel_hold(hold.hold_id)


def test_cancelling_an_unknown_hold(svc):
    """F2-N7: unknown hold id -> HoldNotFound."""
    with pytest.raises(errors.HoldNotFound):
        svc.cancel_hold("H-NOPE")
