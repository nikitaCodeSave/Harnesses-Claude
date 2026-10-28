"""Hidden acceptance tests for F3 — renewals.

Each test cites the BRIEF line or rule (features/F3/NOTES.md) it checks.
Symbols introduced by the feature are looked up at call time, so a missing
interface fails the test instead of breaking collection. Members here owe
nothing and nobody holds anything, and no test renews an overdue loan more
than once, so earlier money and hold rules never interfere.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March. A book borrowed on 2 March is due Mon 23 March, so
it is renewable from Wed 18 March.
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
    for n in range(1, 6):
        s.add_copy(f"BK-{n}", "BK")
    s.add_copy("DV-1", "DV")
    return s


@pytest.fixture
def loan(svc):
    """ann's book loan, borrowed Mon 2 March, due Mon 23 March."""
    return svc.checkout("ann", "BK-1")


def test_new_loan_has_no_renewals(loan):
    """F3 BRIEF: Loan.renewals defaults to 0."""
    assert loan.renewals == 0


def test_renewal_counts_from_the_renewal_day(svc, clock, loan):
    """F3-N1 example: due 23 March, renewed Thu 19 March -> due Thu 9 April."""
    clock.set(date(2026, 3, 19))
    assert svc.renew(loan.loan_id).due_on == date(2026, 4, 9)


def test_renewal_increments_the_counter(svc, clock, loan):
    """F3 BRIEF: renewals is how many times the loan has been renewed."""
    clock.set(date(2026, 3, 19))
    assert svc.renew(loan.loan_id).renewals == 1


def test_renewal_is_the_same_loan(svc, clock, loan):
    """F3 BRIEF, F3-N7: same loan_id, copy, member and borrowed_on."""
    clock.set(date(2026, 3, 19))
    renewed = svc.renew(loan.loan_id)
    assert (renewed.loan_id, renewed.copy_id, renewed.member_id, renewed.borrowed_on) == (
        loan.loan_id, "BK-1", "ann", START,
    )


def test_renewal_is_stored(svc, clock, loan):
    """F3 BRIEF: renews the open loan in place."""
    clock.set(date(2026, 3, 19))
    svc.renew(loan.loan_id)
    assert svc.get_loan(loan.loan_id).due_on == date(2026, 4, 9)
    assert svc.get_copy("BK-1").status is CopyStatus.ON_LOAN


def test_renewal_opens_five_days_before_due(svc, clock, loan):
    """F3-N3: due 23 March -> renewable on Wed 18 March."""
    clock.set(date(2026, 3, 18))
    assert svc.renew(loan.loan_id).due_on == date(2026, 4, 8)


def test_renewal_too_early_is_refused(svc, clock, loan):
    """F3-N3: on 17 March it is RenewalRefused."""
    clock.set(date(2026, 3, 17))
    with pytest.raises(errors.RenewalRefused):
        svc.renew(loan.loan_id)


def test_renewal_on_the_due_date(svc, clock, loan):
    """F3-N1, F3-N3: renewed on Mon 23 March -> due Mon 13 April."""
    clock.set(date(2026, 3, 23))
    assert svc.renew(loan.loan_id).due_on == date(2026, 4, 13)


def test_two_renewals_are_allowed(svc, clock, loan):
    """F3-N2: renewed 19 March (due 9 April) and 6 April (due 27 April)."""
    clock.set(date(2026, 3, 19))
    svc.renew(loan.loan_id)
    clock.set(date(2026, 4, 6))
    renewed = svc.renew(loan.loan_id)
    assert (renewed.renewals, renewed.due_on) == (2, date(2026, 4, 27))


def test_third_renewal_is_refused(svc, clock, loan):
    """F3-N2: the third request is RenewalRefused."""
    for day in (date(2026, 3, 19), date(2026, 4, 6)):
        clock.set(day)
        svc.renew(loan.loan_id)
    clock.set(date(2026, 4, 24))
    with pytest.raises(errors.RenewalRefused):
        svc.renew(loan.loan_id)


def test_refused_third_renewal_changes_nothing(svc, clock, loan):
    """F3-N8: count and due date stay as they were."""
    for day in (date(2026, 3, 19), date(2026, 4, 6)):
        clock.set(day)
        svc.renew(loan.loan_id)
    clock.set(date(2026, 4, 24))
    with pytest.raises(errors.RenewalRefused):
        svc.renew(loan.loan_id)
    current = svc.get_loan(loan.loan_id)
    assert (current.renewals, current.due_on) == (2, date(2026, 4, 27))


def test_refused_early_renewal_changes_nothing(svc, clock, loan):
    """F3-N8: due date and renewal count untouched."""
    clock.set(date(2026, 3, 10))
    with pytest.raises(errors.RenewalRefused):
        svc.renew(loan.loan_id)
    current = svc.get_loan(loan.loan_id)
    assert (current.renewals, current.due_on) == (0, date(2026, 3, 23))


def test_dvds_cannot_be_renewed(svc, clock):
    """F3-N4: DVD due Mon 9 March, asked on Fri 6 March -> RenewalRefused."""
    dvd = svc.checkout("ann", "DV-1")
    clock.set(date(2026, 3, 6))
    with pytest.raises(errors.RenewalRefused):
        svc.renew(dvd.loan_id)


def test_overdue_loan_can_be_renewed(svc, clock, loan):
    """F3-N5, F3-N1: overdue on Thu 26 March -> renewed, due Thu 16 April."""
    clock.set(date(2026, 3, 26))
    renewed = svc.renew(loan.loan_id)
    assert (renewed.renewals, renewed.due_on) == (1, date(2026, 4, 16))


def test_returned_loan_cannot_be_renewed(svc, clock, loan):
    """F3-N6: the copy has already come back."""
    clock.set(date(2026, 3, 19))
    svc.return_copy("BK-1")
    with pytest.raises(errors.RenewalRefused):
        svc.renew(loan.loan_id)


def test_unknown_loan(svc):
    """F3 BRIEF, F3-N6: unknown loan ids keep raising LoanNotFound."""
    with pytest.raises(errors.LoanNotFound):
        svc.renew("L9999")


def test_member_at_the_borrowing_limit_can_renew(svc, clock):
    """F3-N7: the borrowing limit does not apply (a child at 4 loans)."""
    loans = [svc.checkout("kid", f"BK-{n}") for n in range(1, 5)]
    clock.set(date(2026, 3, 19))
    assert svc.renew(loans[0].loan_id).renewals == 1


def test_return_before_the_new_due_date_is_on_time(svc, clock, loan):
    """F3-N1: after renewing on 19 March (due 9 April), back on 1 April -> no fine."""
    clock.set(date(2026, 3, 19))
    svc.renew(loan.loan_id)
    clock.set(date(2026, 4, 1))
    svc.return_copy("BK-1")
    assert svc.balance("ann") == D("0")
