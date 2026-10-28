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

Before I write the code I need a few business rules from you. I've read the package and the shape is clear: holds subtract from `available`, expiry is checked whenever a hold is read or used, and `confirm` turns a hold into a `PLACED` order. The rules below are your call, though, and hidden tests will probably check some of them. Each one has my suggested default, so you can just reply "defaults are fine" or correct the ones you disagree with.

**1. How long a hold lasts**
- How long does an unconfirmed hold live? I'd add an optional `reservation_ttl` argument to the constructor, so `InventoryService(repo, ledger, clock)` still works, with a default of **15 minutes**. What should the default be?
- A hold counts as expired once `now >= expires_at`, so it is already gone at exactly `expires_at`.

**2. Reusing an idempotency key**
- Same key with the same warehouse and items: return the **original reservation in whatever state it's in now**, even if it has been released, has expired or was confirmed. A cart that wants a fresh hold sends a new key. (The alternative is to create a new hold if the old one is no longer active.)
- Same key with a different warehouse or items: raise `IdempotencyConflict`. The order of items doesn't matter. Keys are shared across all warehouses, not scoped to one.

**3. `confirm_reservation`**
- Confirming a reservation that is already confirmed: **return the same `Order`**, so a retry after payment is safe. (The alternative is to raise `InvalidReservationState`.)
- If stock was written off after the hold was made, confirm still **succeeds without checking stock again**. This matches how `PLACED` orders behave today: `ship_order` is where physical stock gets checked.
- An expired hold raises `ReservationExpired`. A released hold raises `InvalidReservationState`.

**4. `release_reservation`**
- Releasing a hold that is already released: **return it unchanged**.
- Releasing an expired hold: **return it unchanged with status `EXPIRED`**. The stock is already free, so there's nothing left to do. (The alternative is to raise `ReservationExpired`.)
- Releasing a confirmed hold raises `InvalidReservationState`. To undo it, cancel the order instead.

**5. Reporting**
- `allocated()` keeps counting only `PLACED` orders. I'd add a separate `held(sku, warehouse)` query.
- The `StockRow` columns stay as they are. `available` will reflect holds, so in a report `on_hand - allocated` can be larger than `available`. Should I add a `held` column to the report instead?

### [build] user

Most defaults are fine, but a few need correcting.

**1.** The default hold is 20 minutes, not 15. Expiry at `now >= expires_at` is right, so the hold is already gone at exactly `expires_at`. The optional `reservation_ttl` argument is fine.

**2.** Both points are fine as you've written them.

**3.**
- Confirming an already-confirmed reservation returns the same `Order`. This holds at any time, even after the 20 minutes have passed.
- Confirm creates an ordinary `PLACED` order in the same warehouse for exactly the units held. If the hold was partial, only those units go on the order.
- Available must not change at confirm. The hold turns into the order's allocation, and on-hand moves only when the order ships.
- A write-off before confirm: either behaviour is fine with me.
- `ReservationExpired` and `InvalidReservationState` are right.

**4.** Fine as you've written it.

**5.** Your `allocated()` and `held` plan is fine. I don't mind whether the report gets a `held` column.

I'm adding one rule you didn't ask about, because it affects how you build `reserve`. Each line holds as many units as are available right now, up to the quantity asked. A line with nothing available is left out of `items` entirely. If no line can hold anything, `reserve` raises `InsufficientStock` and creates nothing.

### [build] agent

Reservations are in, and all of your rules are implemented as you set them. The full suite passes: 51 tests, of which 31 are new in `tests/test_reservations.py`. I haven't committed anything.

**How it behaves**
- **`reserve`:** each line holds whatever is available right now, up to the quantity asked. Lines with nothing available are left out. If no line can hold anything, it raises `InsufficientStock` and creates nothing. Holds last 20 minutes by default; the optional `reservation_ttl` argument changes that, and `InventoryService(repo, ledger, clock)` still works.
- **Retries:** the same key with the same request returns the original reservation in its current state. A different warehouse or different items raise `IdempotencyConflict`. Retries are compared against what the cart *asked for*, not what was actually held, so retrying a partial hold works. If a `reserve` call fails with `InsufficientStock`, its key stays unused and a later retry can succeed.
- **Expiry:** a hold stops counting at exactly `expires_at`, with no sweep job. Any read after that point (`get_reservation`, `confirm_reservation`, `release_reservation` or a retried `reserve`) shows the reservation as `EXPIRED`.
- **`confirm_reservation`:** creates a `PLACED` order for exactly the units held, and `available` doesn't change. Confirming again returns the same `Order` at any time. An expired hold raises `ReservationExpired`; a released one raises `InvalidReservationState`.
- **`release_reservation`:** frees the stock. Releasing a hold that is already released or expired returns it unchanged; releasing a confirmed one raises `InvalidReservationState`.

**Decisions I made where you left it open**
- **Write-off before confirm:** confirm doesn't check stock again, which matches how `PLACED` orders work today. If stock is short, `ship_order` is where it fails.
- **Stock report:** I added a `held` column to `StockRow` as the last field, defaulting to 0, so existing callers and tests still work.
- **New `held(sku, warehouse)` query:** `available` is now `on_hand - allocated - held`, floored at zero.
- **Empty idempotency key:** raises `InvalidOrder`, and so does an empty items dict. A zero quantity or unknown SKU raises the same errors as `place_order`.
- **Extra fields:** `Reservation` also stores `idempotency_key` and `requested`, both optional, so it can be built from just the fields you listed. Reservation IDs look like `RES-0001`.

The code is in `service.py`, `models.py`, `errors.py`, `repository.py` and `reports.py`. I also updated the README and the package exports.
