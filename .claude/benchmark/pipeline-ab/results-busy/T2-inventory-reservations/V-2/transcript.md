### [build] operator

Add stock reservations to the `inventory` package. Checkout must be able to hold stock for a cart before payment, then either confirm the hold into an order or release it. Holds nobody confirms must lapse on their own after a while, and retries from the cart service must be safe (idempotency key).

Interface — hidden tests call exactly this; `InventoryService(repository, ledger, clock)` keeps working as is:
- `InventoryService.reserve(warehouse: str, items: dict[str, int], idempotency_key: str) -> Reservation`
- `InventoryService.confirm_reservation(reservation_id: str) -> Order`
- `InventoryService.release_reservation(reservation_id: str) -> Reservation`
- `InventoryService.get_reservation(reservation_id: str) -> Reservation`
- `InventoryService.available(sku, warehouse)` must take holds into account.
- `inventory.models`: dataclass `Reservation` with `reservation_id: str`, `warehouse: str`, `items: dict[str, int]` (units held per SKU), `status: ReservationStatus`, `expires_at: datetime`, `order_id: str | None`; enum `ReservationStatus` with members `ACTIVE`, `CONFIRMED`, `RELEASED`, `EXPIRED`.
- `inventory.errors`: new `ReservationNotFound`, `ReservationExpired`, `InvalidReservationState`, `IdempotencyConflict` (all subclass `InventoryError`); reuse the existing errors where they fit.
- Time comes only from the injected clock. There is no background job: expiry must take effect without anyone calling a sweep.

I own the business rules — ask me if something is unclear.

### [build] agent

Before I write this, I need a few business-rule decisions from you. I've read the code: holds will sit next to orders in the repository, `available` becomes on-hand − allocated − active holds, and expiry is computed from the clock whenever a hold is read, so no sweep is needed. The open questions are below. Each has a suggested default, so you can just reply "defaults OK" or change the ones you disagree with.

**1. How long a hold lasts.** How long does a hold live? I suggest **15 minutes**, fixed per service. It would be an optional constructor argument, so `InventoryService(repository, ledger, clock)` keeps working. Is a hold already expired at exactly `expires_at`? I suggest **yes** (`now >= expires_at`).

**2. Idempotency key**
- **a.** Same key with the same warehouse and items: I suggest returning **the original reservation as it is now**, even if it has since been released, expired or confirmed. It would not create a new hold. The alternative is a fresh hold once the old one has expired or been released.
- **b.** Same key with a different warehouse or items: raise `IdempotencyConflict`.
- **c.** Scope: I suggest one **global** key space, not one per warehouse.
- **d.** If a `reserve` fails (e.g. `InsufficientStock`), I suggest it **does not use up the key**, so a later retry can succeed.

**3. `release_reservation`**
- ACTIVE → RELEASED.
- Already RELEASED: return it unchanged, so retries are safe.
- EXPIRED: return it unchanged, still EXPIRED (the stock is already free). The alternative is raising `InvalidReservationState`.
- CONFIRMED: raise `InvalidReservationState`.

**4. `confirm_reservation`**
- ACTIVE → creates a PLACED order with `placed_at` set to the confirm time and sets `order_id`. The held units become allocated to that order, so `available` doesn't change. There's no fresh stock check, because the hold already guaranteed the units.
- EXPIRED: raise `ReservationExpired`.
- RELEASED: raise `InvalidReservationState`.
- Already CONFIRMED: I suggest **returning the existing order**, so a payment retry is safe. The alternative is raising `InvalidReservationState`.

**5. Validation (no decision needed unless you object).** I'll reuse the existing errors:
- `UnknownWarehouse` / `UnknownSku` for unknown locations or products
- `InvalidOrder` for an empty `items`
- `InvalidQuantity` for bad quantities
- `InsufficientStock` when there isn't enough stock (all lines or nothing, like `place_order`)

### [build] user

Mostly OK, but corrections:

1. Hold lasts 20 minutes, not 15. expires_at = creation time + 20 min. Expired at exactly expires_at (now >= expires_at): yes. A configurable TTL is fine as long as the default is 20.

2. a–d all agreed. Key is global, a repeat with the same warehouse and same requested items (what was asked for, not what ended up held) returns the existing reservation in its current state and doesn't move expires_at. A different warehouse or items gives IdempotencyConflict, even if the original is finished. A failed reserve leaves no trace.

3. Agreed. Release of an already-RELEASED or an EXPIRED reservation is a no-op that returns it unchanged. Release of a CONFIRMED one gives InvalidReservationState.

4. Agreed. Repeated confirm of an already-CONFIRMED reservation returns the same order and creates nothing, even after the 20 minutes have passed. EXPIRED gives ReservationExpired, RELEASED gives InvalidReservationState. Confirm only places the order for exactly the units held.

5. Validation errors are fine to reuse (unknown warehouse, unknown SKU, zero or negative quantity). A rejected request holds nothing, even for its valid lines. Empty items: any InventoryError is fine. But InsufficientStock is NOT all-or-nothing for reservations: each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of items entirely. Only if no line can hold anything does reserve fail with InsufficientStock, and then nothing is created. Direct place_order stays all-or-nothing, as today, and it can only take available stock (on-hand − placed orders − active holds).

### [build] agent

Stock reservations are in, following the rules you set. The full suite passes: 46 tests, including 25 new ones in `tests/test_reservations.py`. I haven't committed anything.

**How it works**
- **Expiry needs no sweep.** A hold stops counting against stock as soon as the clock reaches `expires_at`. The next time anything reads the reservation (`get_reservation`, a repeated `reserve`, confirm, release, or `available`), its status changes to `EXPIRED`.
- **`available` = on-hand − allocated − held**, never below zero. `place_order` uses the same figure, so it stays all-or-nothing and can't take held stock. There's also a new `held(sku, warehouse)` query.
- **Partial holds:** each line holds as many units as are available, up to what was asked, and lines with nothing available are left out. `InsufficientStock` is raised only when no line can hold anything.
- **Idempotency:** the key is global and checked first. A repeat with the same warehouse and the same requested items returns the existing reservation as it is now, without moving `expires_at`. Any difference raises `IdempotencyConflict`, even if the original is finished. Invalid requests and failed reserves create nothing and don't use up the key or a reservation ID.
- **Confirm** places a `PLACED` order for exactly the units held, without re-checking stock. Repeating it returns the same order, even after the 20 minutes. An expired hold raises `ReservationExpired`; a released one raises `InvalidReservationState`.
- **Release** marks an active hold `RELEASED`. On an already released or expired hold it does nothing and returns it unchanged; on a confirmed one it raises `InvalidReservationState`.
- **Hold length:** 20 minutes by default, changeable with an optional `reservation_ttl=` argument. `InventoryService(repository, ledger, clock)` works as before.

**Small choices I made on my own**
- `Reservation` has three extra fields with defaults after the required ones: `idempotency_key`, `requested` (what was asked for, used for the retry comparison) and `created_at`.
- An empty or missing idempotency key raises `InvalidOrder`.
- If nothing can be held, the `InsufficientStock` error names the first SKU in the request.
- Reservation IDs look like `RES-0001`.

**Your call: the stock report.** `reports.stock_report` doesn't show held units yet. It has no "held" column, so for a SKU with holds, on-hand − allocated won't equal the available figure in the same row. I can add a `held` column at the end of the row, which wouldn't break existing comparisons. Should I?

The main changes are in `src/inventory/service.py`, with storage in `repository.py`, the new types in `models.py` and `errors.py`, and an updated `README.md`.
