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

Before I write this, I need your call on a few rules. Each one changes what the hidden tests would see. I've put a suggested default on each, so "all defaults" is a fine answer.

**1. Hold duration.** How long does an unconfirmed hold last? Should it be one fixed value, or can it be configured?
*Suggestion:* 15 minutes by default, changeable through an optional keyword on the constructor (`InventoryService(repo, ledger, clock, reservation_ttl=timedelta(...))`). Existing calls to the constructor keep working.

**2. Expiry boundary.** Is a hold already expired at the exact moment `now == expires_at`?
*Suggestion:* yes, it's expired once `now >= expires_at`.

**3. Reusing an idempotency key.**
- Same key with the same warehouse and items: return the original reservation unchanged. That means the same ID and the same `expires_at`, and the hold isn't extended.
- Same key with a different warehouse or items: raise `IdempotencyConflict`.
- Same key after the original hold was released, expired or confirmed: return the old reservation in its current state rather than making a new hold. The cart would need a new key to try again.
- Keys are global, not per warehouse.
- If `reserve` fails (for example with `InsufficientStock`), nothing is recorded, so retrying with the same key can succeed later.

The point I'm least sure of is the third bullet. The alternative is to let a key be reused once its hold is gone.

**4. Repeated or late calls.**

| Call | ACTIVE | CONFIRMED | RELEASED | EXPIRED |
|---|---|---|---|---|
| `confirm_reservation` | creates the order | returns the **same** order (safe to retry) | `InvalidReservationState` | `ReservationExpired` |
| `release_reservation` | → RELEASED | `InvalidReservationState` (cancel the order instead) | returns it unchanged (safe to retry) | returns it unchanged, status EXPIRED |

Is that right? In particular, do you want the two "safe to retry" cells to raise `InvalidReservationState` instead?

**5. Stock check on confirm.** Confirming moves the held units straight into a PLACED order with no new availability check. That holds even if a write-off reduced stock in the meantime, which matches the current code: `adjust` doesn't protect allocations either.
*Suggestion:* yes, no check.

Unless you tell me otherwise, I'll also do the following:
- **All or nothing:** `reserve` is all-or-nothing, like `place_order`.
- **Validation:** `reserve` checks items with the existing errors (`UnknownSku`, `UnknownWarehouse`, `InvalidQuantity`, `InvalidOrder`).
- **Stock numbers:** `allocated()` keeps counting only orders, so the stock report doesn't change. I'll add a `held()` query, and `available` becomes on-hand − allocated − active holds.
- **Expiry:** expiry is worked out from the clock whenever a hold is read or stock is counted, so nothing needs to run a sweep.

### [build] user

1. Hold duration: 20 minutes, not 15. Hold lasts 20 minutes from creation, so expires_at = creation time + 20 min. A configurable keyword is fine as long as the default is 20 minutes.

2. Expiry boundary: yes, expired from expires_at on, that instant included. Units become available again with no sweep.

3. Idempotency keys: all your bullets are right, including the third. Same key and same request returns the existing reservation in its current state, whatever that is. One clarification: 'same request' means the same warehouse and the same requested items, meaning what was asked for, not what ended up held. A failed reserve leaves no trace.

4. Table: correct as written, and keep both 'safe to retry' cells as no-ops, not errors. A repeated confirm on a CONFIRMED reservation returns the same order and creates nothing, even after the 20 minutes have passed.

5. Confirm: the held units become the order's allocation, so available doesn't change at confirm. Whether confirm checks stock after a write-off is up to you.

Your other defaults:
- All-or-nothing reserve: no, that's wrong. Reserve is partial. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of `items` entirely, not even shown with 0. Only if no line can hold anything does reserve fail with InsufficientStock, and then nothing is created. Confirm creates an order for exactly the units held. `place_order` stays all-or-nothing and can only take available stock.
- Validation: same as `place_order`, so UnknownWarehouse, UnknownSku and InvalidQuantity for zero or negative quantities. A rejected request holds nothing, not even for its valid lines.
- Stock numbers: available = on-hand − PLACED-order allocations − ACTIVE holds, per SKU per warehouse, never below 0. A hold in one warehouse doesn't affect others. Reserve, release, expire and confirm never write to the ledger or change on-hand. I don't mind about the stock report or a `held()` query.
- Expiry computed on read: fine.

### [build] agent

Stock reservations are in, following the rules you set. The full suite passes (62 tests, including 36 new ones in `tests/test_reservations.py`). I haven't committed anything.

**What changed**
- **`models.py`:** added `ReservationStatus` and the `Reservation` dataclass with exactly the fields you specified. Both are also exported from `inventory`.
- **`errors.py`:** added the four new errors, all subclassing `InventoryError`.
- **`repository.py`:** reservations are stored with IDs `RES-0001`, `RES-0002`, … Each idempotency key is stored with the warehouse and items that were asked for, not what ended up held. That stored request is what a retry is compared against.
- **`service.py`:**
  - The constructor takes an optional `reservation_ttl`, defaulting to 20 minutes, so `InventoryService(repo, ledger, clock)` works unchanged.
  - New `reserve`, `confirm_reservation`, `release_reservation` and `get_reservation`.
  - New `held(sku, warehouse)` query.
  - `available` is now on-hand − PLACED allocations − active holds, never below 0.
- **README:** documents the reservation lifecycle.

**How some of it works**
- **Expiry:** whenever a reservation is looked up, or holds are counted for `available`/`held`, the clock is checked. From `expires_at` on, that instant included, the hold is marked EXPIRED and stops counting. Nothing needs to run a sweep.
- **Request checks:** `reserve` checks the request first (same errors as `place_order`), then the idempotency key, then stock. So a retry with the same key gets the original reservation back even if stock has since run out.
- **Confirm:** the order gets exactly the held units, and `allocated` takes over from `held`, so `available` doesn't move. Order IDs come from the same sequence as `place_order`.

**Decisions I made where you left it open**
- **No stock check on confirm.** Confirm doesn't check stock again after a write-off. This matches how `place_order` and `adjust` already treat allocations, and `ship_order` still refuses to ship more than is physically there.
- **Error when nothing can be held.** The `InsufficientStock` names the first requested line and reports 0 available.
- **Stock report unchanged.** I left it as is. Its `available` column now counts holds, so on a SKU with active holds, `on_hand − allocated` will no longer equal `available`. The difference is the held units. Adding a `held` column would change `StockRow` and break the existing report test, so I didn't. Say if you want it.
- **Shared items dict.** `Reservation.items` is the stored dict itself, the same way `Order` objects are shared today. A caller that changes it would change the hold.
