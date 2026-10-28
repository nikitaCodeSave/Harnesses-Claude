### [spec+build] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [spec+build] agent

Before I write the spec I need your call on some business rules. I've read the code. Each question has my suggested default, so you can just answer "defaults OK" or override only the ones you disagree with.

**Hold lifetime**
1. **How long does a hold last?** I suggest 15 minutes by default, set through an optional `InventoryService(..., reservation_ttl=timedelta(...))` keyword argument. The existing 3-argument constructor keeps working. Should the cart be able to choose the TTL per call? I'd say no.
2. **The exact boundary.** I suggest a hold counts as expired when `now >= expires_at`, so at exactly `expires_at` it is already gone.
3. **Extending a hold.** I suggest this is out of scope (a non-goal).

**Idempotency**
4. **Same key, same request** (same warehouse and same items, in any order): return the original reservation as it is now, with no new hold. That holds even if it has since expired, been released, or been confirmed. In those cases the cart gets back an EXPIRED, RELEASED or CONFIRMED reservation, and has to use a new key to try again.
   - The alternative is that a key whose hold has lapsed or been released starts a fresh hold. Which do you want?
5. **Same key, different request:** raise `IdempotencyConflict`. Keys are global, not per warehouse, and are kept forever.
6. **Order of checks.** A replay with the same key returns the stored result even if stock has changed since. Validation errors (unknown SKU, bad quantity, empty items) are not recorded against the key, so the cart can fix the request and retry with the same key.

**State transitions**
7. **Confirm:**
   - On an ACTIVE hold: create a PLACED order with exactly the held items, and the hold becomes CONFIRMED with `order_id` set. The units move from "held" to "allocated" without ever showing as available in between.
   - On an already CONFIRMED hold: return the same order again, so a retry is safe. The alternative is raising `InvalidReservationState`.
   - On an expired hold: `ReservationExpired`.
   - On a RELEASED hold: `InvalidReservationState`.
8. **Release:**
   - On an ACTIVE hold: it becomes RELEASED.
   - On an already RELEASED hold: return it unchanged, so a retry is safe.
   - On a CONFIRMED hold: `InvalidReservationState`.
   - On an expired hold: `ReservationExpired`? Or return it unchanged, since the stock is already free either way? I lean towards **returning it unchanged**, because the cart's goal ("free the stock") is already met.
9. **Write-offs under a hold.** Suppose a write-off drops on-hand below what a hold covers, then the hold is confirmed. Should the confirm:
   - (a) still succeed, which is my default? This matches today's behaviour, where `adjust` can already push on-hand below allocated and `available` floors at 0. Shipping is where a real shortage surfaces.
   - (b) fail with `InsufficientStock`?

**Visibility**
10. **Who holds count against.** Holds reduce `available` for both `reserve` and `place_order`. `on_hand` doesn't change.
    - Should `allocated` (and the `allocated` column in `stock_report`) include held units, or should holds be separate? I suggest separate: add `InventoryService.held(sku, warehouse)` and leave `allocated` as "PLACED orders only".
    - That means the report row will no longer satisfy `on_hand - allocated == available` while holds exist. Should I add a `held` column to `StockRow`? That would change its constructor, which existing callers and tests use positionally. My default is to add it as a last field with default 0.
11. **Validation:**
    - The same rules as `place_order`: all-or-nothing, `InvalidOrder` for empty items, `UnknownSku`/`UnknownWarehouse`/`InvalidQuantity`, and `InsufficientStock` when available stock is short.
    - An empty idempotency key raises `InvalidOrder`? Or should there be a different error?
    - IDs look like `RES-0001`.
12. **Status as seen on reads.** Once its time passes, a lapsed hold reads as `EXPIRED` from `get_reservation`. It also reads as EXPIRED in idempotent replays and in any other place a reservation is returned, with no sweep needed.

### [spec+build] user

Your defaults are fine except where noted below.

1. Change the hold to **20 minutes**, not 15. `expires_at` is the creation time plus 20 minutes. An optional constructor kwarg for the TTL is fine, as long as the default is 20 minutes. No per-call TTL.
2. Agreed. From `expires_at` on, that instant included, the hold is expired.
3. Extending a hold is out of scope.
4. Agreed. A replay with the same key and the same request returns the existing reservation in its current state, whatever that is. It creates no new hold and doesn't move `expires_at`. The "same request" check compares what was *requested*, not what ended up held.
5. Agreed. The same key with a different warehouse or different items raises `IdempotencyConflict`, even if the original reservation is finished. Keys are global.
6. Agreed. A `reserve` call that fails leaves no trace, so its key can be reused.
7. Agreed. Confirming an already-CONFIRMED hold returns the same order and creates nothing, even after the 20 minutes have passed. After a partial hold, the order covers only the units actually held.
8. Agreed. Releasing an EXPIRED hold is a no-op that returns it unchanged, with no error. Releasing a RELEASED hold also returns it unchanged.
9. Either (a) or (b) is fine. Go with your default.
10. Keeping holds separate is fine. I don't mind the `held` method or the report column, as long as the `StockRow` constructor stays compatible. Holds must reduce `available` for both `reserve` and `place_order`. `place_order` stays all-or-nothing against available stock. Available is on-hand minus PLACED allocations minus ACTIVE holds, floored at 0, per warehouse.
11. Reservations are **not** all-or-nothing, so this is the one real change.
    - Each line holds as many units as are available right now, up to the amount asked.
    - A line with nothing available is left out of `items` entirely, not even with 0.
    - `reserve` raises `InsufficientStock` only if no line can hold anything, and then nothing is created.
    - Bad input is validated as in `place_order`: unknown warehouse gives `UnknownWarehouse`, unknown SKU gives `UnknownSku`, and zero or negative quantity gives `InvalidQuantity`. A rejected request holds nothing, even for its valid lines.
    - For empty items or an empty key, any `InventoryError` is fine. The ID format is up to you.
12. Agreed. An expired hold reads as EXPIRED everywhere, with no sweep. Only ACTIVE holds ever expire.

Also, an unknown reservation id raises `ReservationNotFound` from `get_reservation`, `confirm_reservation` and `release_reservation`.

### [spec+build] agent

I wrote the spec to `SPEC.md` and built the feature. The full test suite passes, including the original tests, which I left unchanged.

```
$ python3 -m pytest -q
...............................................................          [100%]
63 passed in 0.04s
```

The 63 tests are the 21 that were already there plus 42 new ones in `tests/test_reservations.py`. Each new test is tagged with the number of the `SPEC.md` acceptance criterion it checks, and every criterion from 1 to 22 has at least one test.

**How the rules you set work in practice:**
- **Expiry needs no sweep.** Whether a hold still counts is decided against the injected clock every time it's read. A hold stops counting at exactly `expires_at`. A lapsed hold shows as `EXPIRED` from `get_reservation`, from `release_reservation` and from a repeated `reserve`.
- **Repeated `reserve` calls.** Each key is stored with what was *requested*. A repeat with the same key and request returns the reservation in its current status. A repeat with the same key but a different request raises `IdempotencyConflict`. A call that fails doesn't use up its key.
- **Partial holds.** Each line gets as many units as are available at that moment. Lines with nothing available are left out. `reserve` raises `InsufficientStock` only when no line gets anything.
- **Confirm** turns the hold into a placed order for exactly the held units, without checking stock again (option (a) from question 9). Confirming an already-confirmed hold returns the same order.
- **Release** of an already-released or expired hold just returns it unchanged; releasing a confirmed hold raises an error.

**Choices I made where you left it open:**
- **Hold duration:** you can override the 20-minute default with `InventoryService(..., reservation_ttl=timedelta(...))`.
- **Empty items or an empty key** raise `InvalidOrder`.
- **IDs** look like `RES-0001`.
- **Repeated `reserve` with a reused key:** it checks the key before validating the request. So reusing a key with an invalid request raises `IdempotencyConflict` rather than, say, `UnknownSku`.
- **Returned reservations are copies,** so a caller who edits one doesn't change the stored state.
- **Holds are kept separate from allocations.** There's a new `held(sku, warehouse)` method, and `StockRow` has a new last field `held: int = 0`, so existing positional construction still works. `allocated` still counts placed orders only.

I also updated `README.md` to describe holds and the reservation lifecycle. Nothing is committed.
