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

I've read the codebase. Before I write anything I need a few business rules from you. Each question has the default I'd pick, so you can reply "defaults are fine" or correct only the ones you disagree with.

**1. How long a hold lasts.** What should the TTL be? My default is 15 minutes, set as a module constant. `InventoryService` would get an optional keyword argument `reservation_ttl` so the existing 3-argument constructor still works.

**2. The expiry boundary.** Is a hold already expired at exactly `expires_at`, meaning `now >= expires_at`? My default is yes. Expiry would be applied whenever a reservation is read (`get`/`confirm`/`release`/`available`), so no sweep is needed.

**3. Idempotency key.**
- If the same key arrives with the same warehouse and items, should I return the original reservation unchanged, whatever its status is now (active, confirmed, released or expired), without creating a new hold? My default is yes: a key maps to one reservation forever.
- If the same key arrives with a different warehouse or items, should it raise `IdempotencyConflict`? My default is yes.
- Are keys global or scoped per warehouse? My default is global.

**4. Confirm rules.**
- Confirming an ACTIVE hold creates a `PLACED` order. The order's `placed_at` is the confirm time and the hold goes away.
- Confirming an EXPIRED hold raises `ReservationExpired`.
- Confirming a RELEASED hold raises `InvalidReservationState`.
- Confirming an already CONFIRMED hold: should it return the same `Order` (a safe retry) or raise `InvalidReservationState`? My default is to return the same order.

**5. Release rules.**
- Releasing an ACTIVE hold sets it to RELEASED.
- Releasing a CONFIRMED hold raises `InvalidReservationState`, because the order has to go through `cancel_order`.
- Releasing an already RELEASED hold: no-op that returns it, or an error? My default is a no-op.
- Releasing an EXPIRED hold: no-op that returns it still EXPIRED, or raise `ReservationExpired`? My default is a no-op returning EXPIRED, since the stock is already free either way.

**6. Write-off after a hold.** Suppose a hold is active and an `adjust` write-off then pushes physical stock below what's promised. Should `confirm` fail with `InsufficientStock`, or honour the hold anyway? `place_order` only checks availability, so it doesn't settle this. My default is to fail with `InsufficientStock` and leave the hold ACTIVE.

**7. Reporting.** Should held units count in `allocated()` and in the stock report, or stay separate? My default is separate: `allocated()` stays orders-only, I add a `held(sku, warehouse)` query, and `available = on_hand − allocated − held`. One catch: the report's `allocated + available = on_hand` will then no longer hold while there are holds, unless I also add a `held` column to `StockRow`. I'd add it with a default of 0 so existing calls keep working.

These are the rules I'll treat as settled unless you object:
- `reserve` is all-or-nothing.
- `reserve` reuses the existing errors: `InvalidOrder` for empty items, `InvalidQuantity`, `UnknownSku`/`UnknownWarehouse`, and `InsufficientStock` computed against holds.
- Reservation IDs look like `RES-0001`.
- Reservations are stored in `InMemoryRepository`, next to orders.

### [build] user

1. TTL is 20 minutes, not 15. expires_at = creation time + 20 min. A configurable kwarg is fine as long as the default is 20.
2. Yes, expired from expires_at on, that instant included, with no sweep. Expired holds stay retrievable with status EXPIRED.
3. All three defaults are right. A repeat with the same key and the same request returns the existing reservation in its current state and doesn't move expires_at. Compare the requested items, not what was actually held. A different warehouse or items raises IdempotencyConflict, even if the original is finished. Keys are global. A reserve call that fails leaves no trace, so its key can be reused.
4. Confirming an ACTIVE hold places an ordinary PLACED order in the same warehouse for exactly the units held. The reservation becomes CONFIRMED and its order_id is that order's id. The hold turns into the order's allocation, so available doesn't change at confirm. EXPIRED raises ReservationExpired and RELEASED raises InvalidReservationState, as you said. Confirming an already CONFIRMED hold returns the same order and creates nothing, at any time, even after 20 minutes.
5. All your defaults are right. Release of a CONFIRMED hold raises InvalidReservationState. Release of a RELEASED or an EXPIRED hold is a no-op that returns it unchanged.
6. Either is fine, I don't mind. Use your default.
7. I don't mind about reporting. Your default is fine. available = on_hand − allocated to PLACED orders − active holds, per SKU per warehouse, never below 0. Receive and adjust are never blocked by holds. If a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are.

Your settled rules:
- reserve is NOT all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of items entirely. Only if no line can hold anything does reserve fail with InsufficientStock, and then nothing is created.
- Bad input is validated like place_order: UnknownWarehouse, UnknownSku, InvalidQuantity for zero or negative. A rejected request holds nothing, not even for its valid lines.
- Reserving, releasing, expiring and confirming never write to the ledger or change on-hand.
- place_order can only take available stock, so holds count against it. It stays all-or-nothing.
- Unknown reservation id raises ReservationNotFound from get, confirm and release.
- ID format and storage are up to you.

### [build] agent

Reservations are in and implemented to your rules, and the full suite passes (53 tests, including 34 new ones in `tests/test_reservations.py`). I haven't committed anything.

**How it works**
- **Expiry needs no sweep.** Whenever a reservation is read, it is marked `EXPIRED` if the clock is at or past `expires_at`. That covers `get_reservation`, `confirm_reservation`, `release_reservation`, a repeated `reserve`, and `available()`/`held()`. Expired holds stay retrievable.
- **Hold length** defaults to 20 minutes. You can change it with an optional keyword argument, `InventoryService(repo, ledger, clock, reservation_ttl=...)`, and the existing 3-argument call still works.
- **Availability:** `available = max(0, on_hand − allocated − held)`. `held(sku, warehouse)` is a new query for units in active holds. `place_order` stays all-or-nothing and can't take held stock.
- **Idempotency keys** are stored in the repository alongside the warehouse and the *requested* items. Item order doesn't matter when comparing a repeat. A failed `reserve` stores nothing, so its key can be used again.
- **Confirming** creates an ordinary `PLACED` order for exactly the units held. The hold becomes the order's allocation, so `available` doesn't change.
- **Write-off before confirm (question 6):** I went with my default. If a write-off since the hold leaves too little physical stock, confirm raises `InsufficientStock` and the hold stays `ACTIVE`.
- **New pieces:**
  - `ReservationStatus` and `Reservation` in `models.py`, with exactly the fields you listed and `order_id` defaulting to `None`.
  - The four new errors in `errors.py`.
  - Reservation storage in `repository.py`, with IDs like `RES-0001`.
  - Both new models are exported from the package.

**Two things you might not expect**
- **Who wins after a write-off:** when stock is short after a write-off, whichever hold is confirmed first gets it.
- **Reporting:** `StockRow` has a new `held` column that defaults to 0, so existing `StockRow(sku, on_hand, allocated, available)` calls still work. The README now describes the reservation lifecycle.
