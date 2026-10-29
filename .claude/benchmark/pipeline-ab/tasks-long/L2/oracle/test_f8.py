"""Hidden acceptance tests for F8 — the long-overdue job.

Each test cites the BRIEF line or rule (features/F8/NOTES.md) it checks.
The job is looked up at call time, so a missing interface fails the test
instead of breaking collection.

How late a loan must be, and which loans the job leaves alone, were decided
in earlier features (test_cross / test_reversal). Every overdue loan here is
an adult's book loan 200 days past due — beyond any threshold in
question or any plausible guess at one — and every other loan is not overdue
at all.

Calendar (2026): a book borrowed Mon 2 March is due Mon 23 March; the job
runs on Fri 9 October, 200 days later (the book fine is long capped).
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
JOB_DAY = date(2026, 10, 9)


def lost_status():
    return getattr(CopyStatus, "LOST")


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def svc(clock):
    s = LendingService(InMemoryRepository(), clock)
    for member_id in ("ann", "bob", "cat"):
        s.register_member(member_id, member_id.title(), MemberCategory.ADULT)
    s.add_title("BK", "Book", Material.BOOK, D("30.00"))
    for n in range(1, 6):
        s.add_copy(f"BK-{n}", "BK")
    return s


def run(svc):
    return svc.mark_long_overdue()


def test_job_declares_a_long_overdue_loan_lost(svc, clock):
    """F8 BRIEF: returns the loans it declared lost."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(JOB_DAY)
    assert [l.loan_id for l in run(svc)] == [loan.loan_id]


def test_declared_loan_is_lost_today(svc, clock):
    """F8-N1: exactly as by hand — lost_on is the job day, the copy is lost."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(JOB_DAY)
    run(svc)
    assert svc.get_loan(loan.loan_id).lost_on == JOB_DAY
    assert svc.get_copy("BK-1").status is lost_status()


def test_declared_loan_is_over(svc, clock):
    """F8-N1: the loan is over — not open, not overdue."""
    svc.checkout("ann", "BK-1")
    clock.set(JOB_DAY)
    run(svc)
    assert svc.open_loans("ann") == [] and svc.overdue_loans() == []


def test_job_charges_what_staff_would(svc, clock):
    """F8-N1: the same charges as a loss declared by hand that day."""
    by_job = svc.checkout("ann", "BK-1")
    by_hand = svc.checkout("bob", "BK-2")
    clock.set(JOB_DAY)
    svc.declare_lost(by_hand.loan_id)
    declared = run(svc)
    assert [l.loan_id for l in declared] == [by_job.loan_id]
    assert svc.balance("ann") == svc.balance("bob") > 0


def test_second_run_the_same_day_declares_nothing(svc, clock):
    """F8-N2: running again the same day returns an empty list."""
    svc.checkout("ann", "BK-1")
    clock.set(JOB_DAY)
    run(svc)
    assert run(svc) == []


def test_second_run_charges_nothing_more(svc, clock):
    """F8-N2: nothing new is declared, so nothing more is charged."""
    svc.checkout("ann", "BK-1")
    clock.set(JOB_DAY)
    run(svc)
    owed = svc.balance("ann")
    run(svc)
    assert svc.balance("ann") == owed


def test_later_run_leaves_lost_loans_alone(svc, clock):
    """F8-N3: loans already declared lost are never touched."""
    svc.checkout("ann", "BK-1")
    clock.set(JOB_DAY)
    run(svc)
    owed = svc.balance("ann")
    clock.set(date(2026, 10, 10))
    assert run(svc) == []
    assert svc.balance("ann") == owed


def test_returned_loans_are_left_alone(svc, clock):
    """F8-N3: returned loans are never touched."""
    loan = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 3, 20))
    svc.return_copy("BK-1")
    clock.set(JOB_DAY)
    assert run(svc) == []
    assert svc.get_loan(loan.loan_id).lost_on is None


def test_loans_not_overdue_are_left_alone(svc, clock):
    """F8-N3: a loan that is not overdue is never touched."""
    clock.set(date(2026, 9, 25))
    loan = svc.checkout("ann", "BK-1")  # due 16 October
    clock.set(JOB_DAY)
    assert run(svc) == []
    assert svc.get_loan(loan.loan_id).is_open


def test_job_picks_only_the_long_overdue(svc, clock):
    """F8-N3: in a mix, only the long-overdue loan is declared."""
    old = svc.checkout("ann", "BK-1")
    clock.set(date(2026, 9, 25))
    svc.checkout("bob", "BK-2")
    clock.set(JOB_DAY)
    assert [l.loan_id for l in run(svc)] == [old.loan_id]
    assert len(svc.open_loans("bob")) == 1


def test_job_with_nothing_to_do(svc, clock):
    """F8-N2: no loans at all -> an empty list."""
    clock.set(JOB_DAY)
    assert run(svc) == []


def test_job_declares_every_long_overdue_loan(svc, clock):
    """F8 BRIEF: every loan overdue too long, across members."""
    a = svc.checkout("ann", "BK-1")
    c = svc.checkout("cat", "BK-3")
    clock.set(JOB_DAY)
    assert sorted(l.loan_id for l in run(svc)) == sorted([a.loan_id, c.loan_id])
