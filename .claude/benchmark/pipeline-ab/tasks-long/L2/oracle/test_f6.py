"""Hidden acceptance tests for F6 — magazines.

Each test cites the BRIEF line or rule (features/F6/NOTES.md) it checks.
Symbols introduced by the feature are looked up at call time, so a missing
interface fails the test instead of breaking collection.

Late fines, holds, renewals and losses of magazines were decided in earlier
features (test_cross / test_reversal). No test here returns a magazine late,
holds, renews or loses one.

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


def magazine():
    return getattr(Material, "MAGAZINE")


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    s.register_member("ann", "Ann", MemberCategory.ADULT)
    s.register_member("kid", "Kim", MemberCategory.CHILD)
    s.add_title("BK", "Book", Material.BOOK, D("30.00"))
    for n in range(1, 10):
        s.add_copy(f"BK-{n}", "BK")
    return s


@pytest.fixture
def mags(svc):
    svc.add_title("MG", "Monthly", magazine(), D("6.00"))
    for n in range(1, 6):
        svc.add_copy(f"MG-{n}", "MG")
    return svc


def test_magazine_title_can_be_added(svc):
    """F6 BRIEF: magazine titles are added with add_title as usual."""
    title = svc.add_title("MG", "Monthly", magazine(), D("6.00"))
    assert title.material is magazine()


def test_magazine_goes_out_for_fourteen_days(mags):
    """F6-N1 example: borrowed Mon 2 March -> due Mon 16 March."""
    assert mags.checkout("ann", "MG-1").due_on == date(2026, 3, 16)


def test_magazine_period_from_another_day(mags, clock):
    """F6-N1: borrowed Sat 7 March -> due Sat 21 March."""
    clock.set(date(2026, 3, 7))
    assert mags.checkout("ann", "MG-1").due_on == date(2026, 3, 21)


def test_three_magazines_are_fine(mags):
    """F6-N2: at most 3 magazines on loan at once — 3 is allowed."""
    for n in range(1, 4):
        mags.checkout("ann", f"MG-{n}")
    assert len(mags.open_loans("ann")) == 3


def test_fourth_magazine_is_refused(mags):
    """F6-N2: a fourth is LoanLimitReached."""
    for n in range(1, 4):
        mags.checkout("ann", f"MG-{n}")
    with pytest.raises(errors.LoanLimitReached):
        mags.checkout("ann", "MG-4")


def test_refused_magazine_checkout_changes_nothing(mags):
    """F6-N3: no loan, the copy stays on the shelf."""
    for n in range(1, 4):
        mags.checkout("ann", f"MG-{n}")
    with pytest.raises(errors.LoanLimitReached):
        mags.checkout("ann", "MG-4")
    assert len(mags.open_loans("ann")) == 3
    assert mags.get_copy("MG-4").status is CopyStatus.AVAILABLE


def test_returning_a_magazine_frees_a_place(mags):
    """F6-N2: the limit is about magazines on loan right now."""
    for n in range(1, 4):
        mags.checkout("ann", f"MG-{n}")
    mags.return_copy("MG-1")
    assert mags.checkout("ann", "MG-4").copy_id == "MG-4"


def test_magazine_limit_leaves_books_alone(mags):
    """F6-N2: three magazines do not stop book loans."""
    for n in range(1, 4):
        mags.checkout("ann", f"MG-{n}")
    assert mags.checkout("ann", "BK-1").copy_id == "BK-1"


def test_magazines_count_toward_the_adult_limit(mags):
    """F6-N2: 7 books + 1 magazine = 8 loans; a ninth is refused."""
    for n in range(1, 8):
        mags.checkout("ann", f"BK-{n}")
    mags.checkout("ann", "MG-1")
    with pytest.raises(errors.LoanLimitReached):
        mags.checkout("ann", "BK-8")


def test_full_adult_limit_refuses_a_magazine(mags):
    """F6-N2: 8 books on loan -> no magazine either."""
    for n in range(1, 9):
        mags.checkout("ann", f"BK-{n}")
    with pytest.raises(errors.LoanLimitReached):
        mags.checkout("ann", "MG-1")


def test_magazines_count_toward_the_child_limit(mags):
    """F6-N2: a child with 3 magazines and 1 book is at their limit of 4."""
    for n in range(1, 4):
        mags.checkout("kid", f"MG-{n}")
    mags.checkout("kid", "BK-1")
    with pytest.raises(errors.LoanLimitReached):
        mags.checkout("kid", "BK-2")


def test_magazine_returned_on_time_costs_nothing(mags, clock):
    """F6-N1: back by the due date -> nothing owed."""
    mags.checkout("ann", "MG-1")
    clock.set(date(2026, 3, 16))
    mags.return_copy("MG-1")
    assert mags.balance("ann") == 0
