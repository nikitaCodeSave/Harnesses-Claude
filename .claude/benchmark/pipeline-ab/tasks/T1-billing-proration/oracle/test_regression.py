"""Hidden regression tests for T1: pre-existing behaviour a plan-change feature could break.

All of these pass on the pristine repository. They touch renewal, trials, cancellation and
invoicing, which a plan-change implementation is likely to modify.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from billing.clock import FixedClock
from billing.errors import PlanNotAvailable, PlanNotFound, SubscriptionNotActive, SubscriptionNotFound
from billing.plans import Interval, Plan
from billing.service import BillingService
from billing.store import InMemoryStore
from billing.subscriptions import SubscriptionStatus

MONTHLY = Interval.MONTHLY
ANNUAL = Interval.ANNUAL


def D(value: str) -> Decimal:
    return Decimal(value)


def make(today: date) -> tuple[FixedClock, InMemoryStore, BillingService]:
    clock = FixedClock(today)
    store = InMemoryStore()
    store.add_plan(Plan("basic", "Basic", D("10.00"), D("100.00")))
    store.add_plan(Plan("pro", "Pro", D("30.00"), D("300.00")))
    return clock, store, BillingService(store, clock)


def test_subscribe_monthly_period_and_status():
    """Existing: a monthly subscription is active for [today, today + 1 month)."""
    _, _, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "pro")
    assert (sub.status, sub.period_start, sub.period_end) == (
        SubscriptionStatus.ACTIVE, date(2026, 3, 1), date(2026, 4, 1))


def test_subscribe_bills_one_full_period_line():
    """Existing: subscribing records one invoice with one line at the list price, issued today."""
    _, store, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "pro")
    [invoice] = store.invoices_for(sub.id)
    assert (invoice.issued_on, [line.amount for line in invoice.lines]) == (date(2026, 3, 1), [D("30.00")])


def test_subscribe_annual_bills_annual_price_for_a_year():
    """Existing: annual subscriptions bill the annual price for one year."""
    _, store, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "basic", ANNUAL)
    assert sub.period_end == date(2027, 3, 1)
    assert store.invoices_for(sub.id)[0].total == D("100.00")


def test_subscribe_on_month_end_clamps_period_end():
    """Existing: a subscription started Jan 31 ends its first period on Feb 28."""
    _, _, service = make(date(2026, 1, 31))
    assert service.subscribe("cus_1", "basic").period_end == date(2026, 2, 28)


def test_subscribe_to_retired_plan_is_rejected():
    """Existing: retired plans cannot be sold."""
    _, store, service = make(date(2026, 3, 1))
    store.retire_plan("pro")
    with pytest.raises(PlanNotAvailable):
        service.subscribe("cus_1", "pro")


def test_subscribe_to_unknown_plan_is_rejected():
    """Existing: unknown plan codes raise PlanNotFound."""
    _, _, service = make(date(2026, 3, 1))
    with pytest.raises(PlanNotFound):
        service.subscribe("cus_1", "gold")


def test_trial_subscription_is_unbilled_until_trial_end():
    """Existing: a trial is TRIALING for trial_days with no invoice."""
    _, store, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "pro", trial_days=14)
    assert (sub.status, sub.period_end) == (SubscriptionStatus.TRIALING, date(2026, 3, 15))
    assert store.invoices_for(sub.id) == []


def test_trial_end_bills_first_period_and_activates():
    """Existing: at trial end the first full period is billed and the subscription becomes active."""
    clock, store, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "basic", ANNUAL, trial_days=14)
    clock.move_to(date(2026, 3, 15))
    [invoice] = service.renew_due()
    renewed = store.get_subscription(sub.id)
    assert invoice.total == D("100.00")
    assert (renewed.status, renewed.period_start, renewed.period_end) == (
        SubscriptionStatus.ACTIVE, date(2026, 3, 15), date(2027, 3, 15))


def test_renew_due_does_nothing_before_period_end():
    """Existing: nothing is billed while the current period is running."""
    clock, _, service = make(date(2026, 3, 1))
    service.subscribe("cus_1", "pro")
    clock.move_to(date(2026, 3, 31))
    assert service.renew_due() == []


def test_renewal_bills_same_plan_and_advances_period():
    """Existing: renewal bills the list price on period_end and starts the next period there."""
    clock, store, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "pro")
    clock.move_to(date(2026, 4, 1))
    [invoice] = service.renew_due()
    renewed = store.get_subscription(sub.id)
    assert (invoice.issued_on, invoice.total) == (date(2026, 4, 1), D("30.00"))
    assert (renewed.plan_code, renewed.interval, renewed.period_end) == ("pro", MONTHLY, date(2026, 5, 1))


def test_renewal_catches_up_missed_periods():
    """Existing: a late renewal run bills each missed period separately."""
    clock, _, service = make(date(2026, 3, 1))
    service.subscribe("cus_1", "basic")
    clock.move_to(date(2026, 5, 10))
    issued = service.renew_due()
    assert [inv.issued_on for inv in issued] == [date(2026, 4, 1), date(2026, 5, 1)]


def test_annual_renewal_bills_annual_price():
    """Existing: annual subscriptions renew for another year at the annual price."""
    clock, store, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "pro", ANNUAL)
    clock.move_to(date(2027, 3, 1))
    [invoice] = service.renew_due()
    assert invoice.total == D("300.00")
    assert store.get_subscription(sub.id).period_end == date(2028, 3, 1)


def test_retired_plan_subscribers_keep_renewing():
    """Existing: retiring a plan does not stop renewals for customers already on it."""
    clock, store, service = make(date(2026, 3, 1))
    service.subscribe("cus_1", "pro")
    store.retire_plan("pro")
    clock.move_to(date(2026, 4, 1))
    assert [inv.total for inv in service.renew_due()] == [D("30.00")]


def test_renewals_are_independent_per_subscription():
    """Existing: renewing one subscription leaves another (not yet due) untouched."""
    clock, store, service = make(date(2026, 3, 1))
    first = service.subscribe("cus_1", "basic")
    clock.move_to(date(2026, 3, 20))
    second = service.subscribe("cus_2", "pro")
    clock.move_to(date(2026, 4, 1))
    issued = service.renew_due()
    assert [inv.subscription_id for inv in issued] == [first.id]
    assert store.get_subscription(second.id).period_end == date(2026, 4, 20)


def test_canceled_subscription_is_never_renewed():
    """Existing: cancel is immediate and stops renewals."""
    clock, store, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "pro")
    clock.move_to(date(2026, 3, 10))
    service.cancel(sub.id)
    clock.move_to(date(2026, 6, 1))
    assert service.renew_due() == []
    assert store.get_subscription(sub.id).canceled_on == date(2026, 3, 10)


def test_cancel_twice_raises():
    """Existing: canceling a canceled subscription raises SubscriptionNotActive."""
    _, _, service = make(date(2026, 3, 1))
    sub = service.subscribe("cus_1", "pro")
    service.cancel(sub.id)
    with pytest.raises(SubscriptionNotActive):
        service.cancel(sub.id)


def test_unknown_subscription_raises():
    """Existing: the store raises SubscriptionNotFound for unknown ids."""
    _, store, _ = make(date(2026, 3, 1))
    with pytest.raises(SubscriptionNotFound):
        store.get_subscription("sub_9999")
