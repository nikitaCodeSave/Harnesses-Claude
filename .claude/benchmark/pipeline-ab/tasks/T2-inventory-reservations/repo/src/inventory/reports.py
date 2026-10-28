"""Read-only stock views for the back office."""

from __future__ import annotations

from dataclasses import dataclass

from .repository import InMemoryRepository
from .service import InventoryService


@dataclass(frozen=True)
class StockRow:
    sku: str
    on_hand: int
    allocated: int
    available: int


def stock_report(
    repository: InMemoryRepository, service: InventoryService, warehouse: str
) -> list[StockRow]:
    """One row per catalogue SKU for ``warehouse``, sorted by SKU."""
    repository.get_warehouse(warehouse)
    return [
        StockRow(
            sku=product.sku,
            on_hand=service.on_hand(product.sku, warehouse),
            allocated=service.allocated(product.sku, warehouse),
            available=service.available(product.sku, warehouse),
        )
        for product in repository.products()
    ]
