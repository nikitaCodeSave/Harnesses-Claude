"""Hidden regression tests: behaviour of the lending package before F1-F3.

Only interfaces that exist in the original repo are used here.
"""

from datetime import date
from decimal import Decimal as D

import pytest

import lending.errors as errors
from lending.clock import FixedClock
from lending.models import CopyStatus, Material, MemberCategory
from lending.reports import overdue_report
from lending.repository import InMemoryRepository
from lending.service import LendingService

START = date(2026, 3, 2)  # Monday


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
    for n in range(1, 10):
        s.add_copy(f"BK-{n}", "BK")
    s.add_copy("DV-1", "DV")
    return s


def test_book_is_due_in_21_days(svc):
    assert svc.checkout("ann", "BK-1").due_on == date(2026, 3, 23)


def test_dvd_is_due_in_7_days(svc):
    assert svc.checkout("ann", "DV-1").due_on == date(2026, 3, 9)


def test_due_date_on_a_sunday_moves_to_monday(svc, clock):
    clock.set(date(2026, 3, 1))  # Sunday; +21 days is Sunday 22 March
    assert svc.checkout("ann", "BK-1").due_on == date(2026, 3, 23)


def test_checkout_puts_copy_on_loan(svc):
    svc.checkout("ann", "BK-1")
    assert svc.get_copy("BK-1").status is CopyStatus.ON_LOAN


def test_copy_on_loan_cannot_be_borrowed_again(svc):
    svc.checkout("ann", "BK-1")
    with pytest.raises(errors.CopyNotAvailable):
        svc.checkout("kid", "BK-1")


def test_adult_loan_limit_is_eight(svc):
    for n in range(1, 9):
        svc.checkout("ann", f"BK-{n}")
    with pytest.raises(errors.LoanLimitReached):
        svc.checkout("ann", "BK-9")


def test_child_loan_limit_is_four(svc):
    for n in range(1, 5):
        svc.checkout("kid", f"BK-{n}")
    with pytest.raises(errors.LoanLimitReached):
        svc.checkout("kid", "BK-5")


def test_return_closes_the_loan_and_shelves_the_copy(svc, clock):
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 10))
    returned = svc.return_copy("BK-1")
    assert (returned.loan_id, returned.returned_on) == (loan.loan_id, date(2026, 3, 10))
    assert svc.get_copy("BK-1").status is CopyStatus.AVAILABLE
    assert svc.open_loans("ann") == []


def test_returning_a_copy_that_is_not_out(svc):
    with pytest.raises(errors.NoOpenLoan):
        svc.return_copy("BK-1")


def test_unknown_copy(svc):
    with pytest.raises(errors.CopyNotFound):
        svc.checkout("ann", "NOPE")


def test_member_ids_are_unique(svc):
    with pytest.raises(errors.DuplicateMember):
        svc.register_member("ann", "Ann again")


def test_withdrawn_copy_cannot_be_borrowed(svc):
    svc.withdraw_copy("DV-1")
    assert svc.available_copies("DV") == []
    with pytest.raises(errors.CopyNotAvailable):
        svc.checkout("ann", "DV-1")


def test_copy_on_loan_cannot_be_withdrawn(svc):
    svc.checkout("ann", "BK-1")
    with pytest.raises(errors.CopyNotAvailable):
        svc.withdraw_copy("BK-1")


def test_overdue_report_longest_first(svc):
    svc.checkout("ann", "BK-1")  # due 23 March
    svc.checkout("kid", "DV-1")  # due 9 March
    lines = overdue_report(svc, as_of=date(2026, 3, 25))
    assert [(l.copy_id, l.days_overdue) for l in lines] == [("DV-1", 16), ("BK-1", 2)]


def test_loan_history_keeps_returned_loans(svc):
    svc.checkout("ann", "BK-1")
    svc.return_copy("BK-1")
    svc.checkout("ann", "BK-1")
    assert [l.is_open for l in svc.loan_history("ann")] == [False, True]
