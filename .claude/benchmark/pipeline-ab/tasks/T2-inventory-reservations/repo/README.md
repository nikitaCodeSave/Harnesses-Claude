# inventory

Stock and order bookkeeping for the warehouse service. Pure Python, no I/O;
persistence is an in-memory repository behind a small interface.

## Concepts

- **On-hand** — physical units of a SKU in a warehouse. Derived from the
  append-only `Ledger`; never stored. Only receipts, adjustments (counts,
  write-offs) and shipments write to the ledger.
- **Allocated** — units promised to `PLACED` orders that have not shipped yet.
- **Available** — `on_hand - allocated`, floored at zero. This is what new
  orders may take.

Order lifecycle: `place_order` (allocates, all lines or nothing) →
`ship_order` (writes `SHIPMENT` ledger entries) or `cancel_order` (releases
the allocation).

## Conventions

- All time comes from an injected `Clock` (`FixedClock` in tests). Never call
  `datetime.now()` in package code.
- Domain failures raise subclasses of `inventory.errors.InventoryError`.
- `InventoryService` is the only thing that mutates state.

## Layout

```
src/inventory/   clock, errors, models, ledger, repository, service, reports
tests/           pytest suite (shared fixtures in conftest.py)
```

## Tests

```bash
python3 -m pytest -q
```
