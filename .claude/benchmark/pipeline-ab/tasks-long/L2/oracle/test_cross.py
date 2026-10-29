"""Continuity tests: do F2..F8 respect decisions announced in earlier features?

Every decision checked here was volunteered once by the owner in an earlier
feature's interview ("## Mention on your own" in features/F1..F7/NOTES.md)
and is absent from the BRIEF and Rules of the feature whose code it
constrains. A test passes only if the decision survived. Decisions that a
later feature changed before they were used are checked in test_reversal.

Where the decision is about a threshold rather than an error class, either
reasonable error class is accepted, so the test measures the remembered
number, not a naming choice.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March. A book borrowed on 2 March is due Mon 23 March and
renewable from Wed 18 March. A copy returned on 3 March is set aside with
pickup_by Tue 10 March. Members registered on 2 March 2026 are members up to
and including Tue 2 March 2027.
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


def refusal(*names):
    """The refusal classes a feature's BRIEF allows for a money or hold rule."""
    found = tuple(getattr(errors, n) for n in names if hasattr(errors, n))
    return found or (_NoSuchError,)  # nothing exists yet: fail loudly


class _NoSuchError(Exception):
    pass


def magazine():
    return getattr(Material, "MAGAZINE")


def hold_status(name):
    return getattr(getattr(models, "HoldStatus"), name)


@pytest.fixture
def mag(svc):
    """A magazine title, replacement cost 6.00. Borrowed 2 March -> due Mon 16 March."""
    svc.add_title("MG", "Monthly", magazine(), D("6.00"))
    svc.add_copy("MG-1", "MG")
    return svc


# --- F1-L4: a lost copy that turns up: replacement cost off, never into credit -


def test_found_copy_takes_the_replacement_cost_off(svc):
    """F1-L4: the 30.00 replacement cost comes off again; anything else charged
    with the loss stays."""
    loan = svc.checkout("ann", "OT-1")
    svc.declare_lost(loan.loan_id)
    owed = svc.balance("ann")
    svc.found_copy("OT-1")
    assert svc.balance("ann") == owed - D("30.00")


def test_found_copy_keeps_the_fine_charged_at_the_loss(svc, clock):
    """F1-L4: lost Mon 30 March with 1.50 of lateness; when it turns up only the
    replacement cost comes off."""
    loan = svc.checkout("ann", "OT-1")
    clock.set(date(2026, 3, 30))
    svc.declare_lost(loan.loan_id)
    owed = svc.balance("ann")
    clock.set(date(2026, 4, 2))
    svc.found_copy("OT-1")
    assert svc.balance("ann") == owed - D("30.00")


def test_found_copy_after_paying_leaves_no_credit(svc):
    """F1-L4: paid in full, then found -> zero, not in credit."""
    loan = svc.checkout("ann", "OT-1")
    svc.declare_lost(loan.loan_id)
    svc.pay("ann", svc.balance("ann"))
    svc.found_copy("OT-1")
    assert svc.balance("ann") == 0


# --- F1-L5: magazine fines: 0.10 a day, at most 2.00 a loan --------------------


def test_late_magazine_costs_ten_cents_a_day(mag, clock):
    """F1-L5: due Mon 16 March, back Sat 21 March -> 5 late days -> 0.50."""
    mag.checkout("ann", "MG-1")
    clock.set(date(2026, 3, 21))
    mag.return_copy("MG-1")
    assert mag.balance("ann") == D("0.50")


def test_magazine_fine_stops_at_two(mag, clock):
    """F1-L5: back 30 April (39 late days) with a 6.00 replacement cost -> 2.00."""
    mag.checkout("ann", "MG-1")
    clock.set(date(2026, 4, 30))
    mag.return_copy("MG-1")
    assert mag.balance("ann") == D("2.00")


# --- F1-L6: children's memberships never expire --------------------------------


def test_child_can_borrow_years_later(svc, clock):
    """F1-L6: two years on, the child's card still works (an adult's doesn't)."""
    clock.set(date(2028, 3, 10))
    with pytest.raises(refusal("MembershipExpired")):
        svc.checkout("ann", "HB-1")
    assert svc.checkout("kid", "OT-1").copy_id == "OT-1"


def test_child_can_hold_years_later(svc, clock):
    """F1-L6: two years on, the child can still place a hold (an adult can't)."""
    clock.set(date(2028, 3, 10))
    with pytest.raises(refusal("MembershipExpired")):
        svc.checkout("ann", "HB-1")
    svc.register_member("dan", "Dan", MemberCategory.ADULT)
    svc.checkout("dan", "HB-1")
    assert svc.place_hold("kid", "HB").member_id == "kid"


# --- F2-L5: no copy is set aside for an expired member -------------------------


@pytest.fixture
def queue(svc, clock):
    """2027: both HB copies are out (dan, eve); ann (member until 2 March 2027)
    waits first, fay (member until 1 June 2027) second."""
    svc.add_copy("HB-2", "HB")
    clock.set(date(2026, 6, 1))
    for member_id in ("dan", "eve", "fay"):
        svc.register_member(member_id, member_id.title(), MemberCategory.ADULT)
    clock.set(date(2027, 2, 25))
    svc.checkout("dan", "HB-1")
    svc.checkout("eve", "HB-2")
    clock.set(date(2027, 2, 26))
    svc.place_hold("ann", "HB")
    svc.place_hold("fay", "HB")
    clock.set(date(2027, 3, 4))  # ann's membership has expired
    return svc


def test_copy_is_not_set_aside_for_an_expired_member(queue):
    """F2-L5: HB-1 comes back on 4 March -> it goes to fay, not to ann."""
    queue.return_copy("HB-1")
    assert [h.member_id for h in queue.holds_for("HB") if h.copy_id == "HB-1"] == ["fay"]


def test_expired_members_hold_keeps_its_place(queue):
    """F2-L5: ann's hold stays waiting, first in line."""
    queue.return_copy("HB-1")
    first = queue.holds_for("HB")[0]
    assert (first.member_id, first.status) == ("ann", hold_status("WAITING"))


def test_renewed_member_gets_the_next_copy(queue, clock):
    """F2-L5: ann renews on 5 March; HB-2 comes back -> set aside for ann."""
    queue.return_copy("HB-1")
    clock.set(date(2027, 3, 5))
    queue.renew_membership("ann")
    queue.return_copy("HB-2")
    ann = [h for h in queue.holds_for("HB") if h.member_id == "ann"][0]
    assert (ann.status, ann.copy_id) == (hold_status("READY"), "HB-2")


def test_copy_goes_to_the_shelf_when_only_an_expired_member_waits(svc, clock):
    """F2-L5: nobody else waits -> back on the shelf; ann's hold still waits."""
    clock.set(date(2026, 6, 1))
    svc.register_member("dan", "Dan", MemberCategory.ADULT)
    clock.set(date(2027, 2, 25))
    svc.checkout("dan", "HB-1")
    svc.place_hold("ann", "HB")
    clock.set(date(2027, 3, 4))
    svc.return_copy("HB-1")
    assert svc.get_copy("HB-1").status is models.CopyStatus.AVAILABLE
    assert [h.status for h in svc.holds_for("HB")] == [hold_status("WAITING")]


# --- F3-L2: a membership renewal needs the member under the 10.00 bar ----------


def test_membership_renews_while_owing_under_ten(svc, clock):
    """F3-L2: owes 9.99 -> the renewal goes through."""
    svc.add_charge("ann", D("9.99"), "damaged case")
    clock.set(date(2027, 2, 15))
    assert svc.renew_membership("ann").expires_on == date(2028, 3, 2)


def test_owing_ten_blocks_membership_renewal(svc, clock):
    """F3-L2: owes exactly 10.00 -> refused."""
    svc.add_charge("ann", D("10.00"), "damaged case")
    clock.set(date(2027, 2, 15))
    with pytest.raises(refusal("MembershipRenewalRefused", "AccountBlocked")):
        svc.renew_membership("ann")


# --- F3-L3: a loan renewal never runs past the membership ----------------------


def test_loan_renewal_cannot_run_past_the_membership(svc, clock):
    """F3-L3: borrowed Mon 1 Feb 2027, due Mon 22 Feb; renewed 18 Feb it would be
    due Thu 11 March, after ann's last day (2 March) -> RenewalRefused."""
    clock.set(date(2027, 2, 1))
    loan = svc.checkout("ann", "OT-1")
    clock.set(date(2027, 2, 18))
    with pytest.raises(errors.RenewalRefused):
        svc.renew(loan.loan_id)


def test_refused_renewal_past_the_membership_changes_nothing(svc, clock):
    """F3-L3 (with F3-N8): due date and count stay as they were."""
    clock.set(date(2027, 2, 1))
    loan = svc.checkout("ann", "OT-1")
    clock.set(date(2027, 2, 18))
    try:
        svc.renew(loan.loan_id)
    except errors.LendingError:
        pass
    current = svc.get_loan(loan.loan_id)
    assert (current.renewals, current.due_on) == (0, date(2027, 2, 22))


def test_loan_renewal_inside_the_membership_is_fine(svc, clock):
    """F3-L3: renewed 27 Jan 2027 -> due Wed 17 Feb, before 2 March -> allowed."""
    clock.set(date(2027, 1, 11))
    loan = svc.checkout("ann", "OT-1")
    clock.set(date(2027, 1, 27))
    assert svc.renew(loan.loan_id).due_on == date(2027, 2, 17)


# --- F3-L4: magazines can't be renewed -----------------------------------------


def test_magazines_cannot_be_renewed(mag, clock):
    """F3-L4: due 16 March, asked on 13 March -> RenewalRefused."""
    loan = mag.checkout("ann", "MG-1")
    clock.set(date(2026, 3, 13))
    with pytest.raises(errors.RenewalRefused):
        mag.renew(loan.loan_id)


def test_refused_magazine_renewal_changes_nothing(mag, clock):
    """F3-L4 (with F3-N8): the magazine keeps its due date."""
    loan = mag.checkout("ann", "MG-1")
    clock.set(date(2026, 3, 13))
    try:
        mag.renew(loan.loan_id)
    except errors.LendingError:
        pass
    current = mag.get_loan(loan.loan_id)
    assert (current.renewals, current.due_on) == (0, date(2026, 3, 16))


# --- F4-L1: a lost magazine costs a flat 2.00 ----------------------------------


def test_lost_magazine_costs_a_flat_two(mag):
    """F4-L1: no 6.00 replacement cost, no processing fee -> 2.00."""
    loan = mag.checkout("ann", "MG-1")
    mag.declare_lost(loan.loan_id)
    assert mag.balance("ann") == D("2.00")


# --- F4-L2 / F6-L1: loans the long-overdue job leaves alone --------------------


def test_job_never_declares_a_childs_loan_lost(svc, clock):
    """F4-L2: on Fri 9 October a child's book 200 days past due stays out,
    while an adult's book just as late is declared lost in the same run."""
    child = svc.checkout("kid", "OT-1")
    adult = svc.checkout("bob", "TW-1")
    clock.set(date(2026, 10, 9))
    declared = [l.loan_id for l in svc.mark_long_overdue()]
    assert adult.loan_id in declared  # the job works at this lateness
    assert svc.get_loan(child.loan_id).lost_on is None


def test_job_never_declares_a_magazine_lost(mag, clock):
    """F6-L1: on Fri 9 October a magazine 207 days past due stays out, while a
    book even later than that is declared lost in the same run."""
    magazine_loan = mag.checkout("ann", "MG-1")
    book = mag.checkout("bob", "TW-1")
    clock.set(date(2026, 10, 9))
    declared = [l.loan_id for l in mag.mark_long_overdue()]
    assert book.loan_id in declared  # the job works at this lateness
    assert mag.get_loan(magazine_loan.loan_id).lost_on is None


# --- F5-L2: closing writes off a debt under 5.00 -------------------------------


def test_small_debt_is_written_off_at_closing(svc):
    """F5-L2: owes 4.99 -> the account closes and owes nothing."""
    svc.add_charge("ann", D("4.99"), "damaged case")
    svc.close_account("ann")
    assert svc.balance("ann") == 0


def test_owing_five_stops_closing(svc):
    """F5-L2: owes exactly 5.00 -> the account can't be closed."""
    svc.add_charge("ann", D("5.00"), "damaged case")
    with pytest.raises(refusal("CannotClose", "AccountBlocked")):
        svc.close_account("ann")


# --- F5-L3: an account with an active hold can't be closed ---------------------


def test_waiting_hold_stops_closing(svc):
    """F5-L3: ann waits for HB -> CannotClose."""
    svc.checkout("bob", "HB-1")
    svc.place_hold("ann", "HB")
    with pytest.raises(refusal("CannotClose")):
        svc.close_account("ann")


def test_ready_hold_stops_closing(svc, clock):
    """F5-L3: ann's hold is ready on the shelf -> CannotClose."""
    svc.checkout("bob", "HB-1")
    svc.place_hold("ann", "HB")
    clock.set(date(2026, 3, 3))
    svc.return_copy("HB-1")
    with pytest.raises(refusal("CannotClose")):
        svc.close_account("ann")
