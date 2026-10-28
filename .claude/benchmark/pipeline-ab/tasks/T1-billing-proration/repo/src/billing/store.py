"""In-memory repository.

The production deployment swaps this for a database-backed store with the
same methods; nothing outside this module may reach into its internals.
"""

from __future__ import annotations

from dataclasses import replace

from billing.errors import InvalidPlan, InvoiceError, PlanNotFound, SubscriptionNotFound
from billing.invoices import Invoice
from billing.plans import Plan
from billing.subscriptions import Subscription


class InMemoryStore:
    def __init__(self) -> None:
        self._plans: dict[str, Plan] = {}
        self._subscriptions: dict[str, Subscription] = {}
        self._invoices: dict[str, Invoice] = {}
        self._counters: dict[str, int] = {}

    def next_id(self, prefix: str) -> str:
        self._counters[prefix] = self._counters.get(prefix, 0) + 1
        return f"{prefix}_{self._counters[prefix]:04d}"

    # plans

    def add_plan(self, plan: Plan) -> None:
        if plan.code in self._plans:
            raise InvalidPlan(f"plan {plan.code!r} already exists")
        self._plans[plan.code] = plan

    def get_plan(self, code: str) -> Plan:
        try:
            return self._plans[code]
        except KeyError:
            raise PlanNotFound(code) from None

    def retire_plan(self, code: str) -> Plan:
        retired = replace(self.get_plan(code), active=False)
        self._plans[code] = retired
        return retired

    def plans(self) -> list[Plan]:
        return list(self._plans.values())

    # subscriptions

    def save_subscription(self, subscription: Subscription) -> None:
        self._subscriptions[subscription.id] = subscription

    def get_subscription(self, subscription_id: str) -> Subscription:
        try:
            return self._subscriptions[subscription_id]
        except KeyError:
            raise SubscriptionNotFound(subscription_id) from None

    def subscriptions(self) -> list[Subscription]:
        return list(self._subscriptions.values())

    # invoices

    def add_invoice(self, invoice: Invoice) -> None:
        if invoice.id in self._invoices:
            raise InvoiceError(f"invoice {invoice.id} already recorded")
        self._invoices[invoice.id] = invoice

    def invoices_for(self, subscription_id: str) -> list[Invoice]:
        """Invoices of one subscription, in the order they were recorded."""
        return [inv for inv in self._invoices.values() if inv.subscription_id == subscription_id]
