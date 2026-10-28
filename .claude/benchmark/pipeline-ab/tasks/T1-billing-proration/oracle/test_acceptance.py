"""Hidden acceptance tests for T1: mid-cycle plan changes with proration.

Only the public interface fixed in BRIEF.md and pre-existing domain objects are used.
Each docstring cites the BRIEF line or the NOTES rule (N1..N12) it checks.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

import billing.errors as billing_errors
from billing.clock import FixedClock
from billing.errors import PlanNotAvailable, PlanNotFound, SubscriptionNotActive
from billing.plans import Interval, Plan
from billing.service import BillingService
from billing.store import InMemoryStore

# Looked up lazily so a missing class fails only the tests that need it.
InvalidPlanChange = getattr(billing_errors, "InvalidPlanChange", None)

MONTHLY = Interval.MONTHLY
ANNUAL = Interval.ANNUAL


def D(value: str) -> Decimal:
    return Decimal(value)


class World:
    """A fresh store, clock and service with the plans used across NOTES examples."""

    def __init__(self, today: date) -> None:
        self.clock = FixedClock(today)
        self.store = InMemoryStore()
        self.store.add_plan(Plan("basic", "Basic", D("10.00"), D("100.00")))
        self.store.add_plan(Plan("pro", "Pro", D("30.00"), D("300.00")))
        self.store.add_plan(Plan("premium", "Premium", D("75.00"), D("750.00")))
        self.store.add_plan(Plan("legacy", "Legacy", D("20.00"), D("200.00")))
        self.service = BillingService(self.store, self.clock)

    def subscribe(self, plan: str, interval: Interval = MONTHLY, trial_days: int = 0) -> str:
        return self.service.subscribe("cus_1", plan, interval, trial_days=trial_days).id

    def on(self, day: date) -> None:
        self.clock.move_to(day)

    def sub(self, sub_id: str):
        return self.store.get_subscription(sub_id)

    def invoices(self, sub_id: str) -> list:
        return self.store.invoices_for(sub_id)

    def renew_on(self, day: date) -> Decimal:
        """Run the renewal job on ``day`` and return the total billed by it."""
        self.on(day)
        return sum((inv.total for inv in self.service.renew_due()), Decimal("0.00"))


def feb_basic_monthly() -> tuple[World, str]:
    """Basic monthly, period 2026-02-01 .. 2026-03-01 (28 days)."""
    world = World(date(2026, 2, 1))
    return world, world.subscribe("basic")


def march_monthly(plan: str) -> tuple[World, str]:
    """Monthly subscription, period 2026-03-01 .. 2026-04-01 (31 days)."""
    world = World(date(2026, 3, 1))
    return world, world.subscribe(plan)


def pro_annual_2026() -> tuple[World, str]:
    """Pro annual, period 2026-01-10 .. 2027-01-10 (365 days)."""
    world = World(date(2026, 1, 10))
    return world, world.subscribe("pro", ANNUAL)


# --- Upgrades: immediate, prorated (N1-N4) -------------------------------------------------


def test_upgrade_bills_prorated_difference():
    """BRIEF return value + N2/N3/N4: half of a 28-day month Basic->Pro bills 15.00 - 5.00 = 10.00."""
    world, sub_id = feb_basic_monthly()
    world.on(date(2026, 2, 15))
    invoice = world.service.change_plan(sub_id, "pro")
    assert invoice.total == D("10.00")


def test_upgrade_invoice_has_credit_and_charge_lines():
    """N4: exactly two lines, a credit for unused Basic and a charge for remaining Pro."""
    world, sub_id = feb_basic_monthly()
    world.on(date(2026, 2, 15))
    invoice = world.service.change_plan(sub_id, "pro")
    assert sorted(line.amount for line in invoice.lines) == [D("-5.00"), D("15.00")]


def test_upgrade_lines_are_rounded_separately():
    """N4 example: Pro->Premium on Mar 11 of a 31-day period gives -20.32 / +50.81, total 30.49."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    invoice = world.service.change_plan(sub_id, "premium")
    assert sorted(line.amount for line in invoice.lines) == [D("-20.32"), D("50.81")]
    assert invoice.total == D("30.49")


def test_change_date_counts_as_a_remaining_day():
    """N3: on the last day of the period one day remains: -0.36 / +1.07, total 0.71."""
    world, sub_id = feb_basic_monthly()
    world.on(date(2026, 2, 28))
    invoice = world.service.change_plan(sub_id, "pro")
    assert invoice.total == D("0.71")


def test_annual_upgrade_uses_real_year_length():
    """N3/N4: Pro->Premium annual with 92 of 366 days left: -75.41 / +188.52, total 113.11."""
    world = World(date(2027, 6, 1))
    sub_id = world.subscribe("pro", ANNUAL)
    world.on(date(2028, 3, 1))
    invoice = world.service.change_plan(sub_id, "premium")
    assert invoice.total == D("113.11")


def test_upgrade_switches_plan_immediately():
    """N2: right after an upgrade the subscription is on the new plan."""
    world, sub_id = feb_basic_monthly()
    world.on(date(2026, 2, 15))
    world.service.change_plan(sub_id, "pro")
    assert world.sub(sub_id).plan_code == "pro"


def test_upgrade_keeps_billing_period():
    """N2: an upgrade does not move the period start or end."""
    world, sub_id = feb_basic_monthly()
    world.on(date(2026, 2, 15))
    world.service.change_plan(sub_id, "pro")
    sub = world.sub(sub_id)
    assert (sub.period_start, sub.period_end) == (date(2026, 2, 1), date(2026, 3, 1))


def test_upgrade_invoice_is_recorded_on_change_date():
    """BRIEF (recorded like every other invoice) + N4: issued on the change date."""
    world, sub_id = feb_basic_monthly()
    world.on(date(2026, 2, 15))
    invoice = world.service.change_plan(sub_id, "pro")
    assert invoice.issued_on == date(2026, 2, 15)
    assert invoice.id in [inv.id for inv in world.invoices(sub_id)]


# --- Downgrades: at period end (N5) ------------------------------------------------------


def test_downgrade_bills_nothing_now():
    """N5: a downgrade returns None and records no invoice."""
    world, sub_id = march_monthly("premium")
    world.on(date(2026, 3, 11))
    assert world.service.change_plan(sub_id, "basic") is None
    assert len(world.invoices(sub_id)) == 1


def test_downgrade_keeps_current_plan_until_period_end():
    """N5: after requesting a downgrade the customer is still on the current plan."""
    world, sub_id = march_monthly("premium")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "basic")
    assert world.sub(sub_id).plan_code == "premium"


def test_downgrade_applies_at_renewal_at_full_price():
    """N5: the renewal on the period end moves to the cheaper plan and bills its full price."""
    world, sub_id = march_monthly("premium")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "basic")
    assert world.renew_on(date(2026, 4, 1)) == D("10.00")
    assert world.sub(sub_id).plan_code == "basic"


def test_downgrade_with_switch_to_annual_waits_for_period_end():
    """N5/N6: Premium monthly -> Basic annual is billed 100.00 at the Apr 1 renewal for a year."""
    world, sub_id = march_monthly("premium")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "basic", ANNUAL)
    assert world.renew_on(date(2026, 4, 1)) == D("100.00")
    sub = world.sub(sub_id)
    assert (sub.plan_code, sub.interval, sub.period_end) == ("basic", ANNUAL, date(2027, 4, 1))


# --- Interval switches: at period end (N6) -----------------------------------------------


def test_switch_to_annual_bills_nothing_now():
    """N6: monthly -> annual on the same plan returns None and records no invoice."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    assert world.service.change_plan(sub_id, "pro", ANNUAL) is None
    assert len(world.invoices(sub_id)) == 1


def test_switch_to_annual_keeps_monthly_period_until_its_end():
    """N6: until the period end the subscription stays monthly with the same dates."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "pro", ANNUAL)
    sub = world.sub(sub_id)
    assert (sub.interval, sub.period_start, sub.period_end) == (MONTHLY, date(2026, 3, 1), date(2026, 4, 1))


def test_switch_to_annual_starts_annual_period_at_renewal():
    """N6: the Apr 1 renewal bills the full annual price for Apr 1 2026 .. Apr 1 2027."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "pro", ANNUAL)
    assert world.renew_on(date(2026, 4, 1)) == D("300.00")
    sub = world.sub(sub_id)
    assert (sub.interval, sub.period_start, sub.period_end) == (ANNUAL, date(2026, 4, 1), date(2027, 4, 1))


def test_switch_to_monthly_bills_nothing_now():
    """N6: annual -> monthly returns None and records no invoice (no refund of the year)."""
    world, sub_id = pro_annual_2026()
    world.on(date(2026, 5, 5))
    assert world.service.change_plan(sub_id, "pro", MONTHLY) is None
    assert len(world.invoices(sub_id)) == 1


def test_switch_to_monthly_happens_at_end_of_annual_term():
    """N6: the renewal on 2027-01-10 bills one month at the monthly price."""
    world, sub_id = pro_annual_2026()
    world.on(date(2026, 5, 5))
    world.service.change_plan(sub_id, "pro", MONTHLY)
    assert world.renew_on(date(2027, 1, 10)) == D("30.00")
    sub = world.sub(sub_id)
    assert (sub.interval, sub.period_start, sub.period_end) == (MONTHLY, date(2027, 1, 10), date(2027, 2, 10))


def test_upgrade_with_switch_to_annual_bills_upgrade_now_at_monthly_prices():
    """N6 split: Pro monthly -> Premium annual on Mar 11 bills only the monthly upgrade, 30.49."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    invoice = world.service.change_plan(sub_id, "premium", ANNUAL)
    assert invoice.total == D("30.49")


def test_upgrade_with_switch_to_annual_moves_to_annual_at_renewal():
    """N6 split: after the immediate upgrade, the Apr 1 renewal bills Premium annual, 750.00."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "premium", ANNUAL)
    assert world.renew_on(date(2026, 4, 1)) == D("750.00")
    sub = world.sub(sub_id)
    assert (sub.plan_code, sub.interval) == ("premium", ANNUAL)


def test_upgrade_with_switch_to_monthly_bills_upgrade_now_at_annual_prices():
    """N6 split: Pro annual -> Premium monthly on 2026-07-01 bills 193/365 of the annual difference."""
    world, sub_id = pro_annual_2026()
    world.on(date(2026, 7, 1))
    invoice = world.service.change_plan(sub_id, "premium", MONTHLY)
    assert sorted(line.amount for line in invoice.lines) == [D("-158.63"), D("396.58")]


# --- Scheduled changes (N7-N9) -----------------------------------------------------------


def test_upgrade_while_downgrade_scheduled_prorates_from_current_plan():
    """N8 example: on Pro with Basic scheduled, Premium on Mar 11 bills 30.49 (from Pro)."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "basic")
    world.on(date(2026, 3, 11))
    invoice = world.service.change_plan(sub_id, "premium")
    assert invoice.total == D("30.49")


def test_upgrade_discards_scheduled_downgrade():
    """N7: after an upgrade the scheduled downgrade is gone; the renewal bills Premium."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "basic")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "premium")
    assert world.renew_on(date(2026, 4, 1)) == D("75.00")


def test_later_scheduled_change_replaces_earlier_one():
    """N7: Premium -> Pro scheduled, then -> Basic scheduled: the renewal bills Basic."""
    world, sub_id = march_monthly("premium")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "pro")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "basic")
    assert world.renew_on(date(2026, 4, 1)) == D("10.00")


def test_reselecting_current_plan_cancels_scheduled_change_without_billing():
    """N9: with a downgrade scheduled, asking for the current plan returns None, no invoice."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "basic")
    world.on(date(2026, 3, 11))
    assert world.service.change_plan(sub_id, "pro") is None
    assert len(world.invoices(sub_id)) == 1


def test_renewal_after_cancelled_scheduled_change_stays_on_current_plan():
    """N9: once the scheduled downgrade is cancelled the renewal bills the current plan."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "basic")
    world.on(date(2026, 3, 11))
    world.service.change_plan(sub_id, "pro")
    assert world.renew_on(date(2026, 4, 1)) == D("30.00")
    assert world.sub(sub_id).plan_code == "pro"


def test_reselecting_current_plan_with_nothing_scheduled_is_invalid():
    """BRIEF (InvalidPlanChange) + N9: same plan and interval, nothing scheduled, raises."""
    assert InvalidPlanChange is not None, "billing.errors.InvalidPlanChange is missing"
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    with pytest.raises(InvalidPlanChange):
        world.service.change_plan(sub_id, "pro")


# --- Free trials (N10) -------------------------------------------------------------------


def trial(plan: str) -> tuple[World, str]:
    """14-day trial from 2026-03-01; trial ends 2026-03-15."""
    world = World(date(2026, 3, 1))
    return world, world.subscribe(plan, MONTHLY, trial_days=14)


def test_change_during_trial_bills_nothing():
    """N10: an upgrade during a trial returns None and records no invoice."""
    world, sub_id = trial("pro")
    world.on(date(2026, 3, 5))
    assert world.service.change_plan(sub_id, "premium") is None
    assert world.invoices(sub_id) == []


def test_downgrade_during_trial_applies_immediately():
    """N10: during a trial even a downgrade switches the plan right away."""
    world, sub_id = trial("premium")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "basic")
    assert world.sub(sub_id).plan_code == "basic"


def test_interval_switch_during_trial_applies_immediately():
    """N10: during a trial an interval switch takes effect right away."""
    world, sub_id = trial("pro")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "pro", ANNUAL)
    assert world.sub(sub_id).interval is ANNUAL


def test_change_during_trial_keeps_trial_end_date():
    """N10: switching to annual during a trial does not move the trial end."""
    world, sub_id = trial("pro")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "pro", ANNUAL)
    assert world.sub(sub_id).period_end == date(2026, 3, 15)


def test_trial_end_bills_full_price_of_new_plan():
    """N10: upgraded during the trial, the customer is billed Premium in full at trial end."""
    world, sub_id = trial("pro")
    world.on(date(2026, 3, 5))
    world.service.change_plan(sub_id, "premium")
    assert world.renew_on(date(2026, 3, 15)) == D("75.00")


# --- Validation (N11, N12) ---------------------------------------------------------------


def test_unknown_target_plan_is_rejected():
    """N11: a plan code that does not exist raises PlanNotFound."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    with pytest.raises(PlanNotFound):
        world.service.change_plan(sub_id, "gold")


def test_retired_target_plan_is_rejected():
    """N11: moving to a retired plan raises PlanNotAvailable."""
    world, sub_id = march_monthly("basic")
    world.store.retire_plan("premium")
    world.on(date(2026, 3, 11))
    with pytest.raises(PlanNotAvailable):
        world.service.change_plan(sub_id, "premium")


def test_customer_on_retired_plan_can_upgrade():
    """N11: a customer on a retired plan may upgrade off it (Legacy 20.00 -> Pro 30.00, 21/31 left)."""
    world, sub_id = march_monthly("legacy")
    world.store.retire_plan("legacy")
    world.on(date(2026, 3, 11))
    invoice = world.service.change_plan(sub_id, "pro")
    assert invoice.total == D("6.77")


def test_canceled_subscription_cannot_change_plan():
    """N11: a canceled subscription raises SubscriptionNotActive."""
    world, sub_id = march_monthly("pro")
    world.on(date(2026, 3, 11))
    world.service.cancel(sub_id)
    with pytest.raises(SubscriptionNotActive):
        world.service.change_plan(sub_id, "premium")


def test_rejected_change_leaves_no_trace():
    """N12: a rejected request records no invoice and leaves the subscription untouched."""
    world, sub_id = march_monthly("basic")
    world.store.retire_plan("premium")
    world.on(date(2026, 3, 11))
    before = world.sub(sub_id)
    with pytest.raises(PlanNotAvailable):
        world.service.change_plan(sub_id, "premium")
    assert world.sub(sub_id) == before
    assert len(world.invoices(sub_id)) == 1
