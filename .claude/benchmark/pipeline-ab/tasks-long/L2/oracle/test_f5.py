"""Hidden acceptance tests for F5 — membership expiry.

Each test cites the BRIEF line or rule (features/F5/NOTES.md) it checks.
Symbols introduced by the feature are looked up at call time, so a missing
interface fails the test instead of breaking collection.

What memberships mean for children, for holds, for loan renewals and for
money owed was decided in earlier features (test_cross). Every member here
is an adult who owes nothing, and nobody holds anything.

Calendar: ann joins Mon 2 March 2026, so her membership expires Tue 2 March
2027 and is renewable from Sun 31 January 2027. Sundays in 2027: 31 January,
7, 14, 21, 28 February, 7, 14 March.
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
EXPIRY = date(2027, 3, 2)
EXPIRED = date(2027, 3, 3)


def err(name):
    return getattr(errors, name)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    s.register_member("ann", "Ann", MemberCategory.ADULT)
    s.add_title("BK", "Book", Material.BOOK, D("30.00"))
    s.add_title("SO", "Single copy", Material.BOOK, D("20.00"))
    for n in range(1, 4):
        s.add_copy(f"BK-{n}", "BK")
    s.add_copy("SO-1", "SO")
    clock.set(date(2026, 6, 1))
    s.register_member("bob", "Bob", MemberCategory.ADULT)  # expires 1 June 2027
    clock.set(START)
    return s


# --- a year's membership -----------------------------------------------------


def test_registration_sets_a_year(svc):
    """F5-N1 example: joined 2 March 2026 -> expires_on 2 March 2027."""
    assert svc.get_member("ann").expires_on == EXPIRY


def test_registration_on_another_day(svc):
    """F5-N1: the same date next year."""
    assert svc.get_member("bob").expires_on == date(2027, 6, 1)


def test_last_day_is_still_valid(svc, clock):
    """F5-N1: valid up to and including the expiry day."""
    clock.set(EXPIRY)
    assert svc.get_member("ann").expires_on == EXPIRY
    assert svc.checkout("ann", "BK-1").copy_id == "BK-1"


# --- expired members can't take anything new ---------------------------------


def test_expired_member_cannot_check_out(svc, clock):
    """F5-N2: from 3 March 2027 checkout is MembershipExpired."""
    clock.set(EXPIRED)
    with pytest.raises(err("MembershipExpired")):
        svc.checkout("ann", "BK-1")


def test_refused_checkout_creates_no_loan(svc, clock):
    """F5-N4: the refused checkout leaves the copy on the shelf."""
    clock.set(EXPIRED)
    with pytest.raises(err("MembershipExpired")):
        svc.checkout("ann", "BK-1")
    assert svc.open_loans("ann") == []
    assert svc.get_copy("BK-1").status is CopyStatus.AVAILABLE


def test_expired_member_cannot_place_a_hold(svc, clock):
    """F5-N2: an expired member's hold is MembershipExpired."""
    clock.set(date(2027, 2, 20))
    svc.checkout("bob", "SO-1")
    clock.set(EXPIRED)
    with pytest.raises(err("MembershipExpired")):
        svc.place_hold("ann", "SO")


def test_expired_member_cannot_renew_a_loan(svc, clock):
    """F5-N2: renewing after expiry is refused. Book borrowed Fri 5 Feb 2027 is
    due Fri 26 Feb, inside the membership; on 8 March it is overdue, which alone
    would not stop a renewal. The renewal also could not run past the
    membership, so either refusal is accepted."""
    clock.set(date(2027, 2, 5))
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2027, 3, 8))
    with pytest.raises((err("MembershipExpired"), errors.RenewalRefused)):
        svc.renew(loan.loan_id)


def test_expired_member_can_return(svc, clock):
    """F5-N2: returning copies still works (borrowed Fri 5 Feb 2027, due 26 Feb)."""
    clock.set(date(2027, 2, 5))
    svc.checkout("ann", "BK-1")
    clock.set(date(2027, 3, 8))
    with pytest.raises(err("MembershipExpired")):
        svc.checkout("ann", "BK-2")  # ann's membership really has expired
    svc.return_copy("BK-1")
    assert svc.get_copy("BK-1").status is CopyStatus.AVAILABLE


def test_expired_member_can_pay(svc, clock):
    """F5-N2: paying still works."""
    svc.add_charge("ann", D("4.00"), "damaged case")
    clock.set(EXPIRED)
    assert svc.pay("ann", D("4.00")) == 0


def test_expired_member_can_be_charged(svc, clock):
    """F5-N2: being charged still works."""
    clock.set(EXPIRED)
    assert svc.add_charge("ann", D("2.00"), "lost card") == D("2.00")


# --- renewing ----------------------------------------------------------------


def test_renew_membership_returns_the_member(svc, clock):
    """F5 BRIEF: renew_membership returns the member."""
    clock.set(date(2027, 2, 15))
    assert svc.renew_membership("ann").member_id == "ann"


def test_renewal_before_expiry_adds_a_year(svc, clock):
    """F5-N3: renewing before the expiry day adds a year to it."""
    clock.set(date(2027, 2, 15))
    svc.renew_membership("ann")
    assert svc.get_member("ann").expires_on == date(2028, 3, 2)


def test_renewal_on_the_expiry_day_adds_a_year(svc, clock):
    """F5-N3: on the expiry day too: 2 March 2027 -> 2 March 2028."""
    clock.set(EXPIRY)
    assert svc.renew_membership("ann").expires_on == date(2028, 3, 2)


def test_renewal_opens_thirty_days_before(svc, clock):
    """F5-N3 example: renewable from Sun 31 January 2027 on."""
    clock.set(date(2027, 1, 31))
    assert svc.renew_membership("ann").expires_on == date(2028, 3, 2)


def test_renewal_too_early_is_refused(svc, clock):
    """F5-N3: 30 January 2027 is too early."""
    clock.set(date(2027, 1, 30))
    with pytest.raises(err("MembershipRenewalRefused")):
        svc.renew_membership("ann")


def test_refused_renewal_keeps_the_expiry(svc, clock):
    """F5-N4: a refused renewal leaves the expiry as it was."""
    clock.set(date(2026, 9, 1))
    with pytest.raises(err("MembershipRenewalRefused")):
        svc.renew_membership("ann")
    assert svc.get_member("ann").expires_on == EXPIRY


def test_renewal_after_expiry_counts_from_today(svc, clock):
    """F5-N3 example: renewed Mon 15 March 2027 -> 15 March 2028."""
    clock.set(date(2027, 3, 15))
    assert svc.renew_membership("ann").expires_on == date(2028, 3, 15)


def test_renewed_member_can_borrow_again(svc, clock):
    """F5-N2/N3: after a late renewal the member is active again."""
    clock.set(date(2027, 3, 15))
    svc.renew_membership("ann")
    assert svc.checkout("ann", "BK-1").copy_id == "BK-1"


def test_renewing_an_unknown_member(svc):
    """F5 BRIEF: unknown members keep raising MemberNotFound."""
    with pytest.raises(errors.MemberNotFound):
        svc.renew_membership("zed")


def test_new_errors_are_lending_errors():
    """F5 BRIEF: both new errors are LendingErrors."""
    assert issubclass(err("MembershipExpired"), errors.LendingError)
    assert issubclass(err("MembershipRenewalRefused"), errors.LendingError)
