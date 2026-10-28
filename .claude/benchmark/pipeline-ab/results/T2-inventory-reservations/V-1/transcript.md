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

Before I write code, I need a few business rules from you. I've put a suggested default on each, so you can answer "defaults are fine" or just correct the ones you disagree with.

**1. How long does a hold last?** Nothing in the spec says, and hidden tests will likely depend on it. I'd suggest **15 minutes from `reserve`**, fixed (a retry doesn't extend it). A hold would count as expired once `now >= expires_at`, so it's dead at exactly that instant.

**2. Retrying with the same idempotency key**
- Same key with the same warehouse and items: return the original reservation, with no new hold and no time extension.
- Same key with a different warehouse or items: `IdempotencyConflict`.
- After the reservation ends (released, expired or confirmed), I'd suggest the key stays bound to it for good. A retry gets back the original reservation with its final status, so the cart knows to start over with a new key.
- If a `reserve` fails (e.g. `InsufficientStock`), I'd suggest the key isn't consumed, so a retry after a restock can succeed.

**3. Confirming a reservation**
- An active hold becomes a `PLACED` order, timestamped at confirm time. The reservation becomes `CONFIRMED` with its `order_id` set.
- Confirming one that's already confirmed: I'd suggest returning the same order, so payment-callback retries are safe. The alternative is raising `InvalidReservationState`.
- Expired: `ReservationExpired`. Released: `InvalidReservationState`.

**4. Releasing a reservation**
- An active hold becomes `RELEASED`.
- Already released: return it unchanged.
- Already expired: I'd suggest returning it unchanged with status `EXPIRED`, since the stock is already free. The alternative is raising `ReservationExpired`.
- Confirmed: `InvalidReservationState`. To undo it, the caller cancels the order.

**5. Stock written off while it's held.** Today `adjust()` only stops on-hand going below zero, so a write-off can leave held units without stock behind them. At confirm time I'd suggest **confirming anyway**, which is how existing `PLACED` orders already behave after a write-off, and `ship_order` still checks physical stock. The alternative is to re-check at confirm, raise `InsufficientStock` and leave the hold active.

Unless you say otherwise, I'll also do the following:
- Leave `allocated` covering orders only.
- Add a `held(sku, warehouse)` query and set `available = on_hand − allocated − held`, floored at 0. `place_order` will respect holds automatically.
- Add an optional `held` column to `stock_report`; existing rows still compare equal.
- Validate `reserve` the same way as `place_order`: all lines or nothing, using the existing errors.
- Make idempotency keys global, not per warehouse.

### [build] user

1. No, 20 minutes from creation, fixed. A retry doesn't extend it. Expired from expires_at on, that instant included. Agreed on that part.

2. Agreed on all of it: the key stays bound for good, and a retry with a different warehouse or items gives IdempotencyConflict even if the original is finished. A failed reserve leaves no trace, so the key can be reused. One note: "same request" means the same requested items, not what was actually held.

3. Agreed. Confirming an already-confirmed reservation returns the same order and creates nothing, even after the 20 minutes. Expired gives ReservationExpired, released gives InvalidReservationState. Available doesn't change at confirm, because the hold becomes the order's allocation.

4. Agreed on all of it. Releasing a released or expired reservation returns it unchanged, with no error.

5. Confirming anyway is fine. receive and adjust are never blocked by holds. If a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are.

On your list of extras:
- Validation: same checks as place_order (UnknownWarehouse, UnknownSku, InvalidQuantity), and a rejected request holds nothing. But "all lines or nothing" is wrong for stock. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of items entirely. Only if no line can hold anything does reserve fail with InsufficientStock, and then nothing is created. place_order stays all-or-nothing.
- available = on-hand − allocated to PLACED orders − active holds, per SKU per warehouse, floored at 0. A hold in one warehouse doesn't affect another.
- Holds never write to the ledger or change on-hand.
- Global keys are right.
- The held column and held() query are fine.

### [build] agent

Stock reservations are in, following the rules you gave. All 56 tests pass: the 20 existing ones plus 36 new ones in `tests/test_reservations.py`, one or more for each rule. Nothing is committed yet.

**How it works**
- **Expiry needs no sweep.** Whenever a hold is read, it's checked against the clock. Once `now >= expires_at` it stops counting toward `held()` and `available()`, and from then on `get_reservation`, `confirm` and `release` all see it as `EXPIRED`. One catch: a `Reservation` object a caller got earlier won't change its own `status` until something reads it again through the service.
- **Retries:** each idempotency key is stored with the warehouse and the items *requested*, not the items actually held. A repeat of the same request (dict order doesn't matter) gets back the original reservation, whatever state it's in now. A different request with the same key raises `IdempotencyConflict`. A key is only stored after a successful `reserve`, so a failed call uses up neither the key nor a reservation ID.
- **`reserve`** checks the request the same way `place_order` does (unknown warehouse or SKU, bad quantity, empty request), then holds as much of each line as is available, up to the amount asked. Lines with nothing available are left out. It raises `InsufficientStock` only when nothing at all can be held.
- **`confirm_reservation`** turns the held items into a `PLACED` order through the same order-creation code `place_order` now uses. It doesn't re-check stock, so `available` stays the same. Confirming again returns the same order and creates nothing.
- **Untouched:** holds never write to the ledger, and `receive`, `adjust` and `place_order` work as before, except that `place_order` now sees less available stock while holds exist.

**Additions**
- **`held(sku, warehouse)`**: new query. `available` is now on-hand minus allocated minus held, floored at 0.
- **`StockRow.held`**: new report column, defaulting to `0`. Existing comparisons using four arguments still work.
- **Hold length:** a `RESERVATION_TTL` constant (20 minutes) in `service.py`.
- **Reservation IDs:** formatted `RES-0001`, `RES-0002`, and so on.
- **`models.py`:** `Reservation` has exactly the fields you specified. The stored request behind each idempotency key is kept separately, in a small `ReservationRequest` record in the repository.
- **Errors:** the four new ones subclass `InventoryError`. An empty `reserve` request reuses the existing `InvalidOrder` error, as `place_order` does.
- **Docs:** the README describes the reservation lifecycle and the rules.

One edge case I didn't ask you about: the idempotency key is looked up only after the request passes validation. So a malformed request that reuses a key gets the validation error (e.g. `InvalidQuantity`), not `IdempotencyConflict`.
