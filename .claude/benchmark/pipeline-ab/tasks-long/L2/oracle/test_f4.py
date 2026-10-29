"""Hidden acceptance tests for F4 — lost items.

Each test cites the BRIEF line or rule (features/F4/NOTES.md) it checks.
Symbols introduced by the feature are looked up at call time, so a missing
interface fails the test instead of breaking collection.

What a loss costs and what a found copy gives back were decided in earlier
features, not in F4 (they are checked by test_cross / test_reversal). Money
here is therefore compared between two members whose losses differ only in
the rule under test, never against an absolute amount.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March and 5, 12, 19, 26 April. A book borrowed on 2 March
is due Mon 23 March; a DVD borrowed on 2 March is due Mon 9 March.
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


def lost_status():
    return getattr(CopyStatus, "LOST")


def err(name):
    return getattr(errors, name)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    for member_id in ("ann", "bob", "cat"):
        s.register_member(member_id, member_id.title(), MemberCategory.ADULT)
    s.register_member("kid", "Kim", MemberCategory.CHILD)
    s.register_member("kai", "Kai", MemberCategory.CHILD)
    s.add_title("BK", "Book", Material.BOOK, D("30.00"))
    s.add_title("CH", "Cheap book", Material.BOOK, D("1.00"))
    s.add_title("DV", "Film", Material.DVD, D("15.00"))
    s.add_title("SO", "Single copy", Material.BOOK, D("20.00"))
    s.add_title("WL", "Withdrawn and lost", Material.BOOK, D("20.00"))
    for n in range(1, 10):
        s.add_copy(f"BK-{n}", "BK")
    s.add_copy("CH-1", "CH")
    s.add_copy("DV-1", "DV")
    s.add_copy("DV-2", "DV")
    s.add_copy("SO-1", "SO")
    s.add_copy("WL-1", "WL")
    s.add_copy("WL-2", "WL")
    return s


# --- declaring a loss --------------------------------------------------------


def test_declare_lost_returns_the_loan_with_lost_on_today(svc, clock):
    """F4 BRIEF + F4-N2: declare_lost returns the loan; lost_on is today."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 10))
    lost = svc.declare_lost(loan.loan_id)
    assert lost.loan_id == loan.loan_id and lost.lost_on == date(2026, 3, 10)


def test_new_loan_is_not_lost(svc):
    """F4 BRIEF: Loan.lost_on defaults to None."""
    assert svc.checkout("ann", "BK-1").lost_on is None


def test_lost_copy_has_status_lost(svc):
    """F4-N2: the copy becomes LOST."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    assert svc.get_copy("BK-1").status is lost_status()


def test_lost_loan_is_not_returned(svc):
    """F4-N2: returned_on stays empty — the copy did not come back."""
    loan = svc.checkout("ann", "BK-1")
    assert svc.declare_lost(loan.loan_id).returned_on is None


def test_lost_loan_is_not_open(svc):
    """F4-N2: no longer among the member's open loans."""
    loan = svc.checkout("ann", "BK-1")
    svc.checkout("ann", "BK-2")
    svc.declare_lost(loan.loan_id)
    assert [l.copy_id for l in svc.open_loans("ann")] == ["BK-2"]


def test_lost_loan_frees_a_place_in_the_loan_limit(svc):
    """F4-N2: a lost loan no longer counts toward the limit (adults: 8)."""
    for n in range(1, 8):
        svc.checkout("ann", f"BK-{n}")
    cheap = svc.checkout("ann", "CH-1")  # a 1.00 title keeps the balance far below the block
    svc.declare_lost(cheap.loan_id)
    assert svc.checkout("ann", "BK-8").copy_id == "BK-8"


def test_lost_loan_is_not_overdue(svc, clock):
    """F4-N2: a lost loan no longer shows as overdue."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 30))
    svc.declare_lost(loan.loan_id)
    assert svc.overdue_loans() == []


def test_lost_loan_stays_in_the_history(svc):
    """F4-N2: it stays in the member's loan history."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    assert [l.loan_id for l in svc.loan_history("ann")] == [loan.loan_id]


def test_returned_loan_cannot_be_declared_lost(svc):
    """F4-N1: a loan whose copy came back is NoOpenLoan."""
    loan = svc.checkout("ann", "BK-1")
    svc.return_copy("BK-1")
    with pytest.raises(errors.NoOpenLoan):
        svc.declare_lost(loan.loan_id)


def test_lost_loan_cannot_be_declared_lost_again(svc):
    """F4-N1: a loan already declared lost is NoOpenLoan."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    with pytest.raises(errors.NoOpenLoan):
        svc.declare_lost(loan.loan_id)


def test_unknown_loan_cannot_be_declared_lost(svc):
    """F4-N1: an unknown loan id is LoanNotFound."""
    with pytest.raises(errors.LoanNotFound):
        svc.declare_lost("L9999")


def test_refused_declaration_changes_nothing(svc):
    """F4-N6: a refused declaration charges nothing and leaves the copy alone."""
    loan = svc.checkout("ann", "BK-1")
    svc.return_copy("BK-1")
    with pytest.raises(errors.NoOpenLoan):
        svc.declare_lost(loan.loan_id)
    assert svc.balance("ann") == 0
    assert svc.get_copy("BK-1").status is CopyStatus.AVAILABLE


# --- lateness at the loss ----------------------------------------------------


def test_overdue_loss_also_charges_the_fine_so_far(svc, clock):
    """F4-N3: due 23 March, lost Mon 30 March -> 6 late days (Sun 29th not
    counted) = 1.50 more than an equal loss that was not overdue."""
    late = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 16))
    on_time = svc.checkout("bob", "BK-2")  # due 6 April
    clock.set(date(2026, 3, 30))
    svc.declare_lost(late.loan_id)
    svc.declare_lost(on_time.loan_id)
    assert svc.balance("ann") - svc.balance("bob") == D("1.50")


def test_fine_at_loss_is_capped_by_the_replacement_cost(svc, clock):
    """F4-N3 (usual cap): a DVD due 9 March and lost 30 April is fined its
    replacement cost, 15.00, and no more."""
    late = svc.checkout("ann", "DV-1")
    clock.set(date(2026, 4, 28))
    on_time = svc.checkout("bob", "DV-2")  # due 5 May
    clock.set(date(2026, 4, 30))
    svc.declare_lost(late.loan_id)
    svc.declare_lost(on_time.loan_id)
    assert svc.balance("ann") - svc.balance("bob") == D("15.00")


def test_child_overdue_loss_charges_no_fine(svc, clock):
    """F4-N3 (usual child exemption): a child's overdue loss costs exactly what
    an on-time loss costs."""
    late = svc.checkout("kid", "BK-1")
    clock.set(date(2026, 3, 16))
    on_time = svc.checkout("kai", "BK-2")
    clock.set(date(2026, 3, 30))
    svc.declare_lost(late.loan_id)
    svc.declare_lost(on_time.loan_id)
    assert svc.balance("kid") == svc.balance("kai")


def test_no_lateness_is_charged_after_the_loss(svc, clock):
    """F4-N3: after the loss no more lateness is ever charged for that loan."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 30))
    svc.declare_lost(loan.loan_id)
    owed = svc.balance("ann")
    clock.set(date(2026, 4, 30))
    svc.overdue_loans()
    assert svc.balance("ann") == owed


# --- a lost copy is out of circulation ---------------------------------------


def test_lost_copy_cannot_be_checked_out(svc):
    """F4-N4: a lost copy can't be checked out (CopyNotAvailable)."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    with pytest.raises(errors.CopyNotAvailable):
        svc.checkout("bob", "BK-1")


def test_lost_copy_cannot_be_returned_normally(svc):
    """F4-N4: handing a lost copy in through a normal return is NoOpenLoan."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    with pytest.raises(errors.NoOpenLoan):
        svc.return_copy("BK-1")


def test_title_with_every_copy_lost_cannot_be_held(svc):
    """F4-N4: a title whose copies are all lost can't be held."""
    loan = svc.checkout("ann", "SO-1")
    svc.declare_lost(loan.loan_id)
    with pytest.raises(errors.HoldNotAllowed):
        svc.place_hold("cat", "SO")


def test_title_with_copies_lost_or_withdrawn_cannot_be_held(svc):
    """F4-N4: all copies lost or withdrawn -> HoldNotAllowed."""
    svc.withdraw_copy("WL-2")
    loan = svc.checkout("ann", "WL-1")
    svc.declare_lost(loan.loan_id)
    with pytest.raises(errors.HoldNotAllowed):
        svc.place_hold("cat", "WL")


def test_waiting_holds_stay_when_the_copy_is_lost(svc):
    """F4-N4: holds already waiting on the title stay in the queue."""
    loan = svc.checkout("ann", "SO-1")
    hold = svc.place_hold("bob", "SO")
    svc.declare_lost(loan.loan_id)
    assert [h.hold_id for h in svc.holds_for("SO")] == [hold.hold_id]


# --- a lost copy that turns up -----------------------------------------------


def test_found_copy_goes_back_on_the_shelf(svc):
    """F4-N5: with nobody waiting, a found copy goes back on the shelf."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    svc.found_copy("BK-1")
    assert svc.get_copy("BK-1").status is CopyStatus.AVAILABLE


def test_found_copy_returns_the_copy(svc):
    """F4 BRIEF: found_copy returns the copy."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    assert svc.found_copy("BK-1").copy_id == "BK-1"


def test_found_copy_is_set_aside_for_the_first_waiting_hold(svc, clock):
    """F4-N5: exactly like a return — set aside for the first waiting hold,
    pickup by the day + 7 (Tue 3 March -> Tue 10 March)."""
    loan = svc.checkout("ann", "SO-1")
    hold = svc.place_hold("bob", "SO")
    svc.declare_lost(loan.loan_id)
    clock.set(date(2026, 3, 3))
    svc.found_copy("SO-1")
    ready = svc.holds_for("SO")[0]
    assert (ready.hold_id, ready.copy_id, ready.pickup_by) == (hold.hold_id, "SO-1", date(2026, 3, 10))
    assert svc.get_copy("SO-1").status is CopyStatus.ON_HOLD_SHELF


def test_found_copy_leaves_the_loan_lost(svc, clock):
    """F4-N5: the loan stays closed as lost — lost_on stays, returned_on empty."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    clock.set(date(2026, 3, 5))
    svc.found_copy("BK-1")
    again = svc.get_loan(loan.loan_id)
    assert (again.lost_on, again.returned_on) == (START, None)
    assert svc.open_loans("ann") == []


def test_found_copy_can_be_borrowed_again(svc):
    """F4-N5: back into circulation like a returned copy."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    svc.found_copy("BK-1")
    assert svc.checkout("bob", "BK-1").copy_id == "BK-1"


def test_found_on_a_copy_that_is_not_lost(svc):
    """F4-N5: found_copy on a copy that isn't lost is NotLost."""
    with pytest.raises(err("NotLost")):
        svc.found_copy("BK-1")


def test_found_twice_is_not_lost(svc):
    """F4-N5: once found, the copy is no longer lost."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    svc.found_copy("BK-1")
    with pytest.raises(err("NotLost")):
        svc.found_copy("BK-1")


def test_found_on_an_unknown_copy(svc):
    """F4-N5: an unknown copy is CopyNotFound."""
    with pytest.raises(errors.CopyNotFound):
        svc.found_copy("XX-1")


def test_not_lost_is_a_lending_error():
    """F4 BRIEF: NotLost(LendingError)."""
    assert issubclass(err("NotLost"), errors.LendingError)
