from datetime import date
from decimal import Decimal

import pytest

from billing.errors import PlanNotAvailable, PlanNotFound, SubscriptionNotActive
from billing.plans import Interval
from billing.subscriptions import SubscriptionStatus


def test_subscribe_starts_period_today(service):
    sub = service.subscribe("cus_1", "pro")
    assert (sub.period_start, sub.period_end) == (date(2026, 1, 15), date(2026, 2, 15))


def test_subscribe_bills_first_period_immediately(service, store):
    sub = service.subscribe("cus_1", "pro", Interval.ANNUAL)
    [invoice] = store.invoices_for(sub.id)
    assert (invoice.issued_on, invoice.total) == (date(2026, 1, 15), Decimal("300.00"))


def test_subscribe_to_unknown_plan(service):
    with pytest.raises(PlanNotFound):
        service.subscribe("cus_1", "gold")


def test_subscribe_to_retired_plan(service, store):
    store.retire_plan("basic")
    with pytest.raises(PlanNotAvailable):
        service.subscribe("cus_1", "basic")


def test_trial_bills_nothing_up_front(service, store):
    sub = service.subscribe("cus_1", "pro", trial_days=14)
    assert sub.status is SubscriptionStatus.TRIALING
    assert store.invoices_for(sub.id) == []


def test_renew_due_bills_next_period(service, store, clock):
    sub = service.subscribe("cus_1", "basic")
    clock.move_to(date(2026, 2, 15))
    [invoice] = service.renew_due()
    renewed = store.get_subscription(sub.id)
    assert invoice.total == Decimal("10.00")
    assert (renewed.period_start, renewed.period_end) == (date(2026, 2, 15), date(2026, 3, 15))


def test_renew_due_ignores_periods_not_yet_over(service, clock):
    service.subscribe("cus_1", "basic")
    clock.move_to(date(2026, 2, 14))
    assert service.renew_due() == []


def test_trial_end_starts_first_paid_period(service, store, clock):
    sub = service.subscribe("cus_1", "pro", trial_days=14)
    clock.move_to(date(2026, 1, 29))
    [invoice] = service.renew_due()
    paid = store.get_subscription(sub.id)
    assert invoice.total == Decimal("30.00")
    assert (paid.status, paid.period_end) == (SubscriptionStatus.ACTIVE, date(2026, 2, 28))


def test_canceled_subscription_is_not_renewed(service, clock):
    sub = service.subscribe("cus_1", "basic")
    service.cancel(sub.id)
    clock.move_to(date(2026, 3, 1))
    assert service.renew_due() == []


def test_cancel_twice_is_rejected(service):
    sub = service.subscribe("cus_1", "basic")
    service.cancel(sub.id)
    with pytest.raises(SubscriptionNotActive):
        service.cancel(sub.id)
