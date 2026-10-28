"""Domain errors. Everything raised on purpose by this package is an InventoryError."""

from __future__ import annotations


class InventoryError(Exception):
    """Base class for all domain errors."""


class DuplicateEntity(InventoryError):
    def __init__(self, kind: str, key: str) -> None:
        super().__init__(f"{kind} {key!r} already exists")
        self.kind = kind
        self.key = key


class UnknownSku(InventoryError):
    def __init__(self, sku: str) -> None:
        super().__init__(f"unknown SKU {sku!r}")
        self.sku = sku


class UnknownWarehouse(InventoryError):
    def __init__(self, warehouse: str) -> None:
        super().__init__(f"unknown warehouse {warehouse!r}")
        self.warehouse = warehouse


class InvalidQuantity(InventoryError):
    def __init__(self, quantity: object, reason: str = "must be a positive integer") -> None:
        super().__init__(f"invalid quantity {quantity!r}: {reason}")
        self.quantity = quantity


class InsufficientStock(InventoryError):
    def __init__(self, sku: str, warehouse: str, requested: int, available: int) -> None:
        super().__init__(
            f"not enough {sku!r} in {warehouse!r}: requested {requested}, available {available}"
        )
        self.sku = sku
        self.warehouse = warehouse
        self.requested = requested
        self.available = available


class InvalidOrder(InventoryError):
    """The order request itself is malformed (e.g. it has no lines)."""


class OrderNotFound(InventoryError):
    def __init__(self, order_id: str) -> None:
        super().__init__(f"order {order_id!r} not found")
        self.order_id = order_id


class InvalidOrderState(InventoryError):
    def __init__(self, order_id: str, status: object, action: str) -> None:
        super().__init__(f"cannot {action} order {order_id!r} in status {status}")
        self.order_id = order_id
        self.status = status
        self.action = action
