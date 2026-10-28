from datetime import date
from decimal import Decimal

import pytest

from lending import CopyStatus, Material
from lending.errors import CopyNotAvailable, LoanLimitReached, MemberNotFound, NoOpenLoan


def test_checkout_book_is_due_in_21_days(service):
    loan = service.checkout("ann", "B1")
    assert loan.borrowed_on == date(2026, 3, 2)
    assert loan.due_on == date(2026, 3, 23)


def test_checkout_dvd_is_due_in_7_days(service):
    assert service.checkout("ann", "D1").due_on == date(2026, 3, 9)


def test_due_date_never_falls_on_a_sunday(service, clock):
    clock.set(date(2026, 3, 1))  # a Sunday: +21 days is Sunday 22 March
    assert service.checkout("ann", "B1").due_on == date(2026, 3, 23)


def test_checkout_marks_copy_on_loan(service):
    service.checkout("ann", "B1")
    assert service.get_copy("B1").status is CopyStatus.ON_LOAN


def test_copy_already_on_loan_cannot_be_borrowed(service):
    service.checkout("ann", "B1")
    with pytest.raises(CopyNotAvailable):
        service.checkout("kid", "B1")


def test_unknown_member_cannot_borrow(service):
    with pytest.raises(MemberNotFound):
        service.checkout("nobody", "B1")


def test_child_loan_limit_is_four(service):
    service.add_title("978-9", "Picture Book", Material.BOOK, Decimal("9.00"))
    for n in range(5):
        service.add_copy(f"P{n}", "978-9")
    for n in range(4):
        service.checkout("kid", f"P{n}")
    with pytest.raises(LoanLimitReached):
        service.checkout("kid", "P4")


def test_return_closes_loan_and_shelves_copy(service, clock):
    loan = service.checkout("ann", "B1")
    clock.advance(3)
    returned = service.return_copy("B1")
    assert returned.loan_id == loan.loan_id
    assert returned.returned_on == date(2026, 3, 5)
    assert service.get_copy("B1").status is CopyStatus.AVAILABLE
    assert service.open_loans("ann") == []


def test_returning_a_shelved_copy_is_an_error(service):
    with pytest.raises(NoOpenLoan):
        service.return_copy("B1")


def test_loan_history_keeps_returned_loans(service):
    service.checkout("ann", "B1")
    service.return_copy("B1")
    service.checkout("ann", "B1")
    history = service.loan_history("ann")
    assert [l.is_open for l in history] == [False, True]
