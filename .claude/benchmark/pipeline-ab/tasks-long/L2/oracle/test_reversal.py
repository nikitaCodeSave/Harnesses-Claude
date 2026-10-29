"""Reversal tests: does the latest version of a changed decision apply?

Each decision here was volunteered "for later" in one feature and changed,
again "for later", in a later feature before any code needed it
(features/*/NOTES.md, "## Mention on your own"):

  F2-L3 -> changed by F3-L1, used in F4: what a lost copy costs.
  F2-L4 -> changed by F5-L1, used in F6: magazines and holds.
  F4-L2 -> changed by F7-L1, used in F8: when the job declares a loan lost.

A test passes only if the later version won. Parts of these decisions that
were never changed are checked in test_cross.

Calendar used throughout (2026): Mon 2 March is the start; Sundays are
1, 8, 15, 22, 29 March and 5, 12, 19, 26 April. A book borrowed on 2 March is
due Mon 23 March. The job dates are past 28 and within 42 days whether the
days are counted as calendar days (as the notes say) or as open days.
"""

from datetime import date
from decimal import Decimal as D

import pytest

import lending.models as models
from lending.clock import FixedClock
from lending.models import Material, MemberCategory
from lending.repository import InMemoryRepository
from lending.service import LendingService

START = date(2026, 3, 2)


def magazine():
    return getattr(Material, "MAGAZINE")


def hold_status(name):
    return getattr(getattr(models, "HoldStatus"), name)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    for member_id in ("ann", "bob"):
        s.register_member(member_id, member_id.title(), MemberCategory.ADULT)
    s.register_member("kid", "Kim", MemberCategory.CHILD)
    s.add_title("BK", "Book", Material.BOOK, D("30.00"))
    s.add_title("DV", "Film", Material.DVD, D("15.00"))
    for n in range(1, 4):
        s.add_copy(f"BK-{n}", "BK")
    s.add_copy("DV-1", "DV")
    return s


@pytest.fixture
def mag(svc):
    """One magazine copy, out with bob; ann waits for it."""
    svc.add_title("MG", "Monthly", magazine(), D("6.00"))
    svc.add_copy("MG-1", "MG")
    svc.checkout("bob", "MG-1")
    return svc


# --- F2-L3 -> F3-L1: a lost copy costs its replacement cost + 3.00; children nothing


def test_lost_book_costs_replacement_plus_three(svc):
    """F3-L1: 30.00 + a 3.00 processing fee (not 5.00)."""
    loan = svc.checkout("ann", "BK-1")
    svc.declare_lost(loan.loan_id)
    assert svc.balance("ann") == D("33.00")


def test_lost_dvd_costs_replacement_plus_three(svc):
    """F3-L1: 15.00 + 3.00."""
    loan = svc.checkout("ann", "DV-1")
    svc.declare_lost(loan.loan_id)
    assert svc.balance("ann") == D("18.00")


def test_child_pays_nothing_for_a_lost_copy(svc):
    """F3-L1: no replacement cost, no fee (not "replacement cost only")."""
    loan = svc.checkout("kid", "BK-1")
    svc.declare_lost(loan.loan_id)
    assert svc.balance("kid") == 0


# --- F2-L4 -> F5-L1: magazines can be held; pickup within 3 days ---------------


def test_magazine_can_be_held(mag):
    """F5-L1: a hold on a magazine with every copy out is accepted."""
    hold = mag.place_hold("ann", "MG")
    assert hold.status is hold_status("WAITING")


def test_magazine_set_aside_waits_three_days(mag, clock):
    """F5-L1: back Tue 3 March -> pickup by Fri 6 March (not 10 March)."""
    mag.place_hold("ann", "MG")
    clock.set(date(2026, 3, 3))
    mag.return_copy("MG-1")
    assert mag.holds_for("MG")[0].pickup_by == date(2026, 3, 6)


def test_magazine_pickup_skips_sunday(mag, clock):
    """F5-L1: back Thu 5 March -> Sun 8 March -> Mon 9 March."""
    mag.place_hold("ann", "MG")
    clock.set(date(2026, 3, 5))
    mag.return_copy("MG-1")
    assert mag.holds_for("MG")[0].pickup_by == date(2026, 3, 9)


def test_uncollected_magazine_hold_expires_after_three_days(mag, clock):
    """F5-L1: ready from 3 March, pickup by 6 March -> the job on Sat 7 March
    expires it."""
    hold = mag.place_hold("ann", "MG")
    clock.set(date(2026, 3, 3))
    mag.return_copy("MG-1")
    clock.set(date(2026, 3, 7))
    assert [h.hold_id for h in mag.expire_holds()] == [hold.hold_id]


# --- F4-L2 -> F7-L1: declared lost once more than 28 days past due -------------


def test_job_declares_lost_at_thirty_five_days(svc, clock):
    """F7-L1: due Mon 23 March; Mon 27 April is 35 calendar days past due
    (30 open days) -> lost, not waiting for 42."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 4, 27))
    assert [l.loan_id for l in svc.mark_long_overdue()] == [loan.loan_id]


def test_job_declares_lost_at_forty_days(svc, clock):
    """F7-L1: Sat 2 May is 40 calendar days past due (35 open days) -> lost."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 5, 2))
    assert [l.loan_id for l in svc.mark_long_overdue()] == [loan.loan_id]
