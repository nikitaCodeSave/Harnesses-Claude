from datetime import datetime, timezone

import pytest

from inventory import FixedClock, InMemoryRepository, InventoryService, Ledger, Product, Warehouse

START = datetime(2024, 3, 1, 9, 0, tzinfo=timezone.utc)


@pytest.fixture
def clock():
    return FixedClock(START)


@pytest.fixture
def repo():
    r = InMemoryRepository()
    r.add_warehouse(Warehouse("WH1", "Main"))
    r.add_warehouse(Warehouse("WH2", "Overflow"))
    r.add_product(Product("MUG", "Mug"))
    r.add_product(Product("TEE", "T-shirt"))
    r.add_product(Product("CAP", "Cap"))
    return r


@pytest.fixture
def ledger():
    return Ledger()


@pytest.fixture
def service(repo, ledger, clock):
    return InventoryService(repo, ledger, clock)
