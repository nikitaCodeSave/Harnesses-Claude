from datetime import date
from decimal import Decimal

import pytest

from lending import FixedClock, InMemoryRepository, LendingService, Material, MemberCategory

# Monday. The library is closed on Sundays.
START = date(2026, 3, 2)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def service(clock):
    svc = LendingService(InMemoryRepository(), clock)
    svc.register_member("ann", "Ann Adult")
    svc.register_member("kid", "Kim Kid", MemberCategory.CHILD)
    svc.add_title("978-1", "The Long Winter", Material.BOOK, Decimal("18.00"))
    svc.add_title("dvd-1", "Night Train", Material.DVD, Decimal("12.00"))
    svc.add_copy("B1", "978-1")
    svc.add_copy("B2", "978-1")
    svc.add_copy("D1", "dvd-1")
    return svc
