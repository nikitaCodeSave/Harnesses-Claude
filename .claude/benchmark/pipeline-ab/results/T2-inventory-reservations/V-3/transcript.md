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

Before I write this, I need a few business rules from you. I've put my suggested answer next to each one, so you can just say "defaults" if they're fine.

1. **How long does a hold last?** Suggestion: 15 minutes from `reserve`, set once with an optional `InventoryService(..., reservation_ttl=timedelta(minutes=15))` argument so the 3-argument constructor still works. A hold counts as expired from the moment `now >= expires_at`. Hidden tests may advance the clock by a specific amount, so I need the real number, not my guess.

2. **What happens when the cart service retries with the same idempotency key?**
   - Same warehouse and items: return the original reservation unchanged. That applies even if it has since been confirmed, released or expired; the cart needs a new key for a new hold. Suggestion: yes.
   - Same key with a different warehouse or items: `IdempotencyConflict`. Suggestion: yes.
   - The other option is that a retry after the hold ended creates a new hold. Tell me if you want that instead.

3. **What happens when confirm or release hits a reservation that isn't active?**

   | Current status | `confirm_reservation` | `release_reservation` |
   |---|---|---|
   | CONFIRMED | return the same order (retry-safe) | `InvalidReservationState` |
   | RELEASED | `InvalidReservationState` | return it unchanged (retry-safe) |
   | EXPIRED | `ReservationExpired` | `ReservationExpired` |

   The alternative is to be strict and raise `InvalidReservationState` on every repeat instead of returning the earlier result.

4. **What if stock is written off during a hold?** Suppose `adjust` drops on-hand below the held quantity. Suggestion: confirm still turns the hold into a PLACED order, the same way existing orders survive a write-off today. The other option is to have confirm raise `InsufficientStock`.

5. **Do holds count as "allocated"?** Suggestion: no. `allocated()` stays "PLACED orders only", as the README defines it, and I add a separate `held(sku, warehouse)`. Then `available = on_hand - allocated - held`, floored at 0. One catch: the stock report row would then no longer satisfy `available = on_hand - allocated`. Should I add a `held` column to `StockRow`, or count holds inside `allocated`?

For errors I'll reuse the existing ones: `UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, `InvalidOrder` for an empty `items`, and `InsufficientStock` when there isn't enough available. A reserve is all-or-nothing, like `place_order`.

### [build] user

1. The hold lasts 20 minutes, not 15. `expires_at` is the creation time plus 20 minutes. From `expires_at` on, with that instant included, the hold counts as expired. A TTL argument is fine as long as the default is 20 minutes.

2. Both of your suggestions are right. Same key with the same warehouse and the same requested items returns the existing reservation in its current state. It creates no new hold and doesn't move `expires_at`. Same key with a different warehouse or different items raises `IdempotencyConflict`, even if the original reservation is finished. A `reserve` call that fails leaves nothing behind, so its key can be used again. Keys are unique across all warehouses.

3. Your table is wrong in three places:
   - **Confirming a CONFIRMED reservation:** return the same order and create nothing new. This holds at any time, even after the 20 minutes have passed.
   - **Releasing an EXPIRED reservation:** this is a no-op that returns it unchanged, with no error. Releasing an already-RELEASED one is also a no-op.
   - **Releasing a CONFIRMED reservation:** raise `InvalidReservationState`.
   - **Confirming an EXPIRED reservation:** raise `ReservationExpired`, including one that has only just lapsed.
   - **Confirming a RELEASED reservation:** raise `InvalidReservationState`.
   - **Unknown id:** `get_reservation`, `confirm_reservation` and `release_reservation` all raise `ReservationNotFound`.

4. I don't mind. `receive` and `adjust` are never blocked by holds. If a write-off drops on-hand below what is held, available shows 0 and the reservations stay as they are. Either behaviour is fine for confirm in that case.

5. Your approach is fine: keep `allocated` as it is and add a separate `held`. I don't mind whether the stock report shows held units. Available is on-hand minus units in PLACED orders minus units in ACTIVE reservations, per SKU per warehouse, never below 0. A hold in one warehouse doesn't affect any other warehouse.

Your closing note about reserve being all-or-nothing is wrong. Reserve gives partial holds:
- Each line holds as many units as are available right now, up to the quantity asked for.
- A line with nothing available is left out of `items` entirely, not even shown with 0.
- Only when no line can hold anything does `reserve` raise `InsufficientStock`, and then nothing is created.
- `place_order` stays all-or-nothing, and it can only take available stock.

Validation works exactly like `place_order`:
- Unknown warehouse raises `UnknownWarehouse`.
- Unknown SKU raises `UnknownSku`.
- Zero or negative quantity raises `InvalidQuantity`.
- A rejected request holds nothing, not even for its valid lines.
- Your `InvalidOrder` for an empty `items` is fine.

Confirm places an ordinary PLACED order in the same warehouse for exactly the units held, which after a partial hold means only those. The reservation becomes CONFIRMED and its `order_id` is that order's id. Available doesn't change at confirm. Reserving, releasing, expiring and confirming never write to the ledger or change on-hand.

### [build] agent

Stock reservations are now in the `inventory` package and follow the rules you gave. The full suite passes: 51 tests, including 24 new ones in `tests/test_reservations.py`. I haven't committed anything.

**What's new**
- **Data types and errors:** `Reservation`, `ReservationStatus` and the four new errors match your spec exactly. `Reservation` and `ReservationStatus` can also be imported straight from `inventory`.
- **Methods on `InventoryService`:** `reserve`, `confirm_reservation`, `release_reservation` and `get_reservation`, plus a separate `held(sku, warehouse)`. `available` is now on-hand minus allocated minus held, never below 0.
- **Hold length:** the constructor takes an optional `reservation_ttl`, defaulting to 20 minutes. `InventoryService(repository, ledger, clock)` works as before.
- **Storage:** the in-memory repository now stores reservations and remembers which reservation each idempotency key created.
- **README:** describes held stock and the reservation lifecycle.

**Behaviour you might not assume**
- **Expiry needs no sweep.** Whenever a reservation is read, it's marked expired if the clock has reached `expires_at`. "Read" includes `available`, `held`, `get_reservation`, confirm, release and an idempotent retry.
- **Retries compare what was requested, not what was held.** If someone asks for 50 mugs and gets 10, retrying with 50 returns that same reservation.
- **A retry with the same key but a different request that is also invalid** (say, an unknown SKU) raises the validation error rather than `IdempotencyConflict`. That's because the request is validated before the key is looked up.
- **When nothing can be held**, the `InsufficientStock` error names the first line of the request.
- **Confirm doesn't re-check on-hand.** You said either way was fine; I chose this because it matches how placed orders already survive a write-off.

**Left alone:** `reports.stock_report` doesn't show held units, since you didn't mind either way. As a result, a row can read on-hand 8, allocated 3, available 3, with the gap being held units. If you want a `held` column, I can add it at the end of `StockRow` with a default of 0 so the existing 4-value rows still compare equal.
