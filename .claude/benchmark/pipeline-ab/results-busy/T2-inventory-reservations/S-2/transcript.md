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

I've read the package (orders allocate stock, `available = on_hand − allocated`, all time from `Clock`, 20 tests passing). Before writing the spec I need your call on these business rules. Each one has my recommended default, so you can just reply "defaults OK" or override by number.

**Hold lifetime**
1. **How long does a hold last?** I suggest a fixed 15 minutes from `reserve`, optionally overridable through an `InventoryService` constructor kwarg (the 3-arg constructor keeps working).
2. **Boundary.** I suggest a hold counts as expired once `now >= expires_at`. At exactly `expires_at` it no longer holds stock and can't be confirmed.

**Idempotency**
3. **Same key, same request** (same warehouse, same items, line order ignored): return the original reservation unchanged, whatever its status is now (active, confirmed, released or expired). No new hold, and the expiry isn't pushed back. So a retry after expiry gets the EXPIRED reservation back, and the cart has to use a new key to try again.
4. **Same key, different request** → `IdempotencyConflict`.
5. **A reserve that fails** (e.g. `InsufficientStock`) doesn't use up the key, so a retry with the same key can succeed after a restock.
6. **Key scope.** I suggest keys are global, not per warehouse.

**Transitions** (`ACTIVE → CONFIRMED | RELEASED | EXPIRED`, all final)
7. **Confirm.**
   - An active hold becomes a PLACED `Order` (placed_at = confirm time), and the reservation's `order_id` is set to it.
   - Confirming again returns the same order instead of raising, so payment-callback retries are safe.
   - Confirming an expired hold → `ReservationExpired`. Confirming a released one → `InvalidReservationState`.
8. **Confirm doesn't re-check stock.** The hold already reserved the units. If a write-off (`adjust`) has since cut on-hand, the order is still placed and the shortage shows up at `ship_order`. That matches how PLACED orders already behave today.
9. **Release.**
   - An active hold becomes RELEASED.
   - Releasing an already-released hold just returns it (safe retry).
   - Releasing a confirmed hold → `InvalidReservationState`.
   - Releasing an expired hold → returns it unchanged as EXPIRED, since the stock is already free. The alternative is raising `ReservationExpired`. Which do you want?
10. **Unknown id** → `ReservationNotFound` for get, confirm and release.

**Stock figures**
11. **`available`** = on_hand − allocated − units in active holds, floored at 0. `allocated()` stays orders-only. The back-office `stock_report` keeps its 4 columns, so its `available` reflects holds but holds don't get their own column. Do you want a `held` column, or a `held(sku, warehouse)` query?
12. **Validation matches `place_order`:**
    - unknown warehouse or SKU → `UnknownWarehouse` / `UnknownSku`
    - bad quantity → `InvalidQuantity`
    - empty items → `InvalidOrder`
    - not enough stock → `InsufficientStock`, and nothing is held for any line
13. **IDs** look like `RES-0001`, numbered in sequence like orders.

What would you like to change?

### [spec+build] user

Overrides:

1. The hold lasts 20 minutes, not 15 (most payments finish within 18). A constructor option is fine.

Missing from your list: reserve is partial, not all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of `items` entirely (not even with 0). `reserve` fails with `InsufficientStock` only when no line can hold anything, and then nothing is created. This changes item 12 ("nothing is held for any line") for the not-enough-stock case only. A rejected request, such as an unknown SKU or a bad quantity, still holds nothing at all, not even for its valid lines. `place_order` stays all-or-nothing, but it can only take available stock (net of holds).

7. Confirming again returns the same order, even after the 20 minutes have passed. Confirm creates a PLACED order for exactly the units held (after a partial hold, only those). `available` doesn't change at confirm, because the hold becomes the order's allocation.

Also: reserve, release, expire and confirm never write to the ledger or change on-hand. `receive` and `adjust` are never blocked by holds. If a write-off drops on-hand below what is held, `available` shows 0 and the reservations stay as they are.

Defaults OK on 2-6, 8, 9 (expired release returns it unchanged), 10, 11, 13, and 12 apart from the change above. Empty items raising `InvalidOrder` is fine.

### [spec+build] agent

Stock reservations are built and the full test suite passes: 20 existing tests plus 40 new ones in `tests/test_reservations.py`. Each new test is named after the spec criterion it covers (`test_01_…` through `test_25_…`), so every one of the 25 criteria has at least one test.

```
$ python3 -m pytest -q
............................................................             [100%]
60 passed in 0.04s
```

**Spec.** `SPEC.md` has the interface copied verbatim from your request, the lifecycle, the 25 acceptance criteria and the non-goals. Your overrides are in it: the 20-minute hold, partial reserve, confirm-again returning the same order, and the rules on the ledger and write-offs.

**Two decisions I made myself (noted in the spec):**
- **Retries are matched on the request as sent**, not on the units actually held. If a retry comes in after a restock, it still gets back the original partial hold rather than a new, larger one.
- **When nothing can be held**, `InsufficientStock` names the first requested line, with `available == 0`.

**How expiry works without a background job.** Whenever a reservation is read — through `get_reservation`, confirm, release, an idempotent retry or the `available` calculation — it is checked against the injected clock. If `now >= expires_at`, it is marked `EXPIRED` and its units are free again. No sweep call is needed.

**What changed:**
- `models.py`: the `Reservation` dataclass and the `ReservationStatus` enum, both also exported from the `inventory` package.
- `errors.py`: the four new errors, all subclasses of `InventoryError`.
- `repository.py`: storage for reservations, `RES-0001`-style IDs, and the idempotency-key index. A key is only recorded once a reserve succeeds, so a failed reserve doesn't use it up.
- `service.py`:
  - `reserve`, `confirm_reservation`, `release_reservation` and `get_reservation`.
  - `available` now subtracts active holds, so `place_order` and `stock_report` take holds into account without any change of their own.
  - The hold length can be set with `InventoryService(repo, ledger, clock, reservation_ttl=timedelta(...))`; it defaults to 20 minutes, and the 3-argument constructor still works.
- `README.md`: describes held stock and the reservation lifecycle.

I haven't committed anything.
