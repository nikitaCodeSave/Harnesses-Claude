"""Hidden acceptance tests for F7 — closing an account.

Each test cites the BRIEF line or rule (features/F7/NOTES.md) it checks.
Symbols introduced by the feature are looked up at call time, so a missing
interface fails the test instead of breaking collection.

What closing does with money owed and with active holds was decided in an
earlier feature (test_cross). Every account closed here owes nothing and
holds nothing at the moment of closing.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March.
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


def err(name):
    return getattr(errors, name)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    for member_id in ("ann", "bob"):
        s.register_member(member_id, member_id.title(), MemberCategory.ADULT)
    s.add_title("BK", "Book", Material.BOOK, D("30.00"))
    s.add_title("SO", "Single copy", Material.BOOK, D("20.00"))
    for n in range(1, 4):
        s.add_copy(f"BK-{n}", "BK")
    s.add_copy("SO-1", "SO")
    return s


def test_new_member_is_not_closed(svc):
    """F7 BRIEF: Member.closed_on defaults to None."""
    assert svc.get_member("ann").closed_on is None


def test_close_returns_the_member_closed_today(svc, clock):
    """F7 BRIEF + F7-N2: close_account returns the member; closed_on is today."""
    clock.set(date(2026, 3, 10))
    member = svc.close_account("ann")
    assert (member.member_id, member.closed_on) == ("ann", date(2026, 3, 10))


def test_cannot_close_with_a_copy_on_loan(svc):
    """F7-N1: a copy on loan -> CannotClose."""
    svc.checkout("ann", "BK-1")
    with pytest.raises(err("CannotClose")):
        svc.close_account("ann")


def test_refused_closure_leaves_the_account_open(svc):
    """F7-N4: a refused closure leaves the account open and untouched."""
    svc.checkout("ann", "BK-1")
    with pytest.raises(err("CannotClose")):
        svc.close_account("ann")
    assert svc.get_member("ann").closed_on is None
    assert svc.checkout("ann", "BK-2").copy_id == "BK-2"


def test_can_close_after_returning_everything(svc, clock):
    """F7-N1: with everything back, the account closes."""
    svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 5))
    svc.return_copy("BK-1")
    assert svc.close_account("ann").closed_on == date(2026, 3, 5)


def test_lost_loans_do_not_stop_closing(svc):
    """F7-N1: lost loans are over and don't count (the loss is paid first)."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    if svc.balance("ann") > 0:
        svc.pay("ann", svc.balance("ann"))
    assert svc.close_account("ann").closed_on == START


def test_closed_account_cannot_check_out(svc):
    """F7-N3: checking out is AccountClosed."""
    svc.close_account("ann")
    with pytest.raises(err("AccountClosed")):
        svc.checkout("ann", "BK-1")


def test_closed_account_cannot_place_a_hold(svc):
    """F7-N3: placing a hold is AccountClosed."""
    svc.checkout("bob", "SO-1")
    svc.close_account("ann")
    with pytest.raises(err("AccountClosed")):
        svc.place_hold("ann", "SO")


def test_closed_account_cannot_be_closed_again(svc):
    """F7-N3: closing it again is AccountClosed."""
    svc.close_account("ann")
    with pytest.raises(err("AccountClosed")):
        svc.close_account("ann")


def test_closed_member_can_still_be_looked_up(svc):
    """F7-N2: nothing is deleted — the member can still be looked up."""
    svc.close_account("ann")
    assert svc.get_member("ann").name == "Ann"


def test_closed_member_keeps_the_loan_history(svc, clock):
    """F7-N2: their loan history can still be looked up."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 5))
    svc.return_copy("BK-1")
    svc.close_account("ann")
    assert [l.loan_id for l in svc.loan_history("ann")] == [loan.loan_id]


def test_closed_member_balance_still_answers(svc):
    """F7-N2: their balance can still be looked up."""
    svc.close_account("ann")
    assert svc.balance("ann") == 0


def test_closing_leaves_other_accounts_alone(svc):
    """F7-N2/N3: only that account is closed."""
    svc.close_account("ann")
    assert svc.checkout("bob", "BK-1").copy_id == "BK-1"


def test_closing_an_unknown_member(svc):
    """F7 BRIEF: unknown members keep raising MemberNotFound."""
    with pytest.raises(errors.MemberNotFound):
        svc.close_account("zed")


def test_new_errors_are_lending_errors():
    """F7 BRIEF: both new errors are LendingErrors."""
    assert issubclass(err("AccountClosed"), errors.LendingError)
    assert issubclass(err("CannotClose"), errors.LendingError)


def test_copy_is_untouched_by_a_refused_closure(svc):
    """F7-N4: the copy on loan stays on loan."""
    svc.checkout("ann", "BK-1")
    with pytest.raises(err("CannotClose")):
        svc.close_account("ann")
    assert svc.get_copy("BK-1").status is CopyStatus.ON_LOAN
