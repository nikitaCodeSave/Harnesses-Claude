"""Append-only stock ledger. On-hand stock is derived from it, never stored."""

from __future__ import annotations

from datetime import datetime

from .errors import InvalidQuantity
from .models import Adjustment, AdjustmentReason


class Ledger:
    def __init__(self) -> None:
        self._entries: list[Adjustment] = []

    def record(
        self,
        sku: str,
        warehouse: str,
        delta: int,
        reason: AdjustmentReason,
        at: datetime,
        ref: str | None = None,
        note: str | None = None,
    ) -> Adjustment:
        if delta == 0:
            raise InvalidQuantity(delta, "a ledger entry must move stock")
        entry = Adjustment(
            entry_id=f"ADJ-{len(self._entries) + 1:06d}",
            sku=sku,
            warehouse=warehouse,
            delta=delta,
            reason=reason,
            at=at,
            ref=ref,
            note=note,
        )
        self._entries.append(entry)
        return entry

    def entries(self, sku: str | None = None, warehouse: str | None = None) -> list[Adjustment]:
        return [
            e
            for e in self._entries
            if (sku is None or e.sku == sku) and (warehouse is None or e.warehouse == warehouse)
        ]

    def balance(self, sku: str, warehouse: str) -> int:
        return sum(e.delta for e in self.entries(sku, warehouse))

    def __len__(self) -> int:
        return len(self._entries)
