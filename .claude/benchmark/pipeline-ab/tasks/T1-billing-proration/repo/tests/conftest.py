from datetime import date
from decimal import Decimal

import pytest

from billing.clock import FixedClock
from billing.plans import Plan
from billing.service import BillingService
from billing.store import InMemoryStore


@pytest.fixture
def clock() -> FixedClock:
    return FixedClock(date(2026, 1, 15))


@pytest.fixture
def store() -> InMemoryStore:
    store = InMemoryStore()
    store.add_plan(Plan("basic", "Basic", Decimal("10.00"), Decimal("100.00")))
    store.add_plan(Plan("pro", "Pro", Decimal("30.00"), Decimal("300.00")))
    return store


@pytest.fixture
def service(store: InMemoryStore, clock: FixedClock) -> BillingService:
    return BillingService(store, clock)
