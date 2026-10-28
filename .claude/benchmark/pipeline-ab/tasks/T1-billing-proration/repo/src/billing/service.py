"""Billing operations: subscribe, renew, cancel."""

from __future__ import annotations

from dataclasses import replace
from datetime import date, timedelta

from billing.clock import Clock
from billing.errors import PlanNotAvailable, SubscriptionNotActive
from billing.invoices import Invoice, LineItem
from billing.periods import period_end
from billing.plans import Interval, Plan
from billing.store import InMemoryStore
from billing.subscriptions import Subscription, SubscriptionStatus


class BillingService:
    def __init__(self, store: InMemoryStore, clock: Clock) -> None:
        self._store = store
        self._clock = clock

    def subscribe(
        self,
        customer_id: str,
        plan_code: str,
        interval: Interval = Interval.MONTHLY,
        *,
        trial_days: int = 0,
    ) -> Subscription:
        """Start a subscription today.

        Without a trial the first period is billed immediately. With a trial
        nothing is billed until the trial ends (see ``renew_due``).
        """
        plan = self._store.get_plan(plan_code)
        if not plan.active:
            raise PlanNotAvailable(plan_code)
        if trial_days < 0:
            raise ValueError("trial_days must not be negative")

        today = self._clock.today()
        if trial_days:
            subscription = Subscription(
                id=self._store.next_id("sub"),
                customer_id=customer_id,
                plan_code=plan.code,
                interval=interval,
                status=SubscriptionStatus.TRIALING,
                period_start=today,
                period_end=today + timedelta(days=trial_days),
            )
            self._store.save_subscription(subscription)
            return subscription

        subscription = Subscription(
            id=self._store.next_id("sub"),
            customer_id=customer_id,
            plan_code=plan.code,
            interval=interval,
            status=SubscriptionStatus.ACTIVE,
            period_start=today,
            period_end=period_end(today, interval),
        )
        self._store.save_subscription(subscription)
        self._issue_invoice(subscription, [self._period_line(plan, subscription)], today)
        return subscription

    def renew_due(self) -> list[Invoice]:
        """Bill every subscription whose current period has ended.

        A subscription that missed several renewals is caught up one period
        at a time, each with its own invoice dated on the period start.
        """
        today = self._clock.today()
        issued: list[Invoice] = []
        for subscription in self._store.subscriptions():
            while not subscription.is_canceled and subscription.period_end <= today:
                subscription, invoice = self._renew(subscription)
                issued.append(invoice)
        return issued

    def cancel(self, subscription_id: str) -> Subscription:
        """Cancel immediately. No refund; the subscription is never renewed."""
        subscription = self._store.get_subscription(subscription_id)
        if subscription.is_canceled:
            raise SubscriptionNotActive(subscription_id)
        canceled = replace(
            subscription,
            status=SubscriptionStatus.CANCELED,
            canceled_on=self._clock.today(),
        )
        self._store.save_subscription(canceled)
        return canceled

    # internals

    def _renew(self, subscription: Subscription) -> tuple[Subscription, Invoice]:
        plan = self._store.get_plan(subscription.plan_code)
        start = subscription.period_end
        renewed = replace(
            subscription,
            status=SubscriptionStatus.ACTIVE,
            period_start=start,
            period_end=period_end(start, subscription.interval),
        )
        self._store.save_subscription(renewed)
        invoice = self._issue_invoice(renewed, [self._period_line(plan, renewed)], start)
        return renewed, invoice

    @staticmethod
    def _period_line(plan: Plan, subscription: Subscription) -> LineItem:
        interval = subscription.interval
        return LineItem(
            description=(
                f"{plan.name} ({interval.value}) "
                f"{subscription.period_start.isoformat()} to {subscription.period_end.isoformat()}"
            ),
            amount=plan.price_for(interval),
        )

    def _issue_invoice(self, subscription: Subscription, lines: list[LineItem], issued_on: date) -> Invoice:
        invoice = Invoice(
            id=self._store.next_id("inv"),
            subscription_id=subscription.id,
            customer_id=subscription.customer_id,
            issued_on=issued_on,
            lines=tuple(lines),
        )
        self._store.add_invoice(invoice)
        return invoice
