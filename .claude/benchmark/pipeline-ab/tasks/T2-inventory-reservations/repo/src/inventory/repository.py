"""In-memory persistence. Swappable for a database-backed repository later."""

from __future__ import annotations

from .errors import DuplicateEntity, OrderNotFound, UnknownSku, UnknownWarehouse
from .models import Order, OrderStatus, Product, Warehouse


class InMemoryRepository:
    def __init__(self) -> None:
        self._products: dict[str, Product] = {}
        self._warehouses: dict[str, Warehouse] = {}
        self._orders: dict[str, Order] = {}
        self._order_seq = 0

    # -- catalogue -------------------------------------------------------
    def add_product(self, product: Product) -> None:
        if product.sku in self._products:
            raise DuplicateEntity("product", product.sku)
        self._products[product.sku] = product

    def get_product(self, sku: str) -> Product:
        try:
            return self._products[sku]
        except KeyError:
            raise UnknownSku(sku) from None

    def products(self) -> list[Product]:
        return sorted(self._products.values(), key=lambda p: p.sku)

    def add_warehouse(self, warehouse: Warehouse) -> None:
        if warehouse.code in self._warehouses:
            raise DuplicateEntity("warehouse", warehouse.code)
        self._warehouses[warehouse.code] = warehouse

    def get_warehouse(self, code: str) -> Warehouse:
        try:
            return self._warehouses[code]
        except KeyError:
            raise UnknownWarehouse(code) from None

    # -- orders ----------------------------------------------------------
    def next_order_id(self) -> str:
        self._order_seq += 1
        return f"ORD-{self._order_seq:04d}"

    def save_order(self, order: Order) -> None:
        self._orders[order.order_id] = order

    def get_order(self, order_id: str) -> Order:
        try:
            return self._orders[order_id]
        except KeyError:
            raise OrderNotFound(order_id) from None

    def orders(
        self, warehouse: str | None = None, status: OrderStatus | None = None
    ) -> list[Order]:
        return [
            o
            for o in self._orders.values()
            if (warehouse is None or o.warehouse == warehouse)
            and (status is None or o.status is status)
        ]
