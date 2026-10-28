### [spec] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim.

### [spec] agent

I've read the package. Holds will sit next to the existing `PLACED`-order allocation, and I can reuse `InvalidOrder`, `InvalidQuantity`, `UnknownSku`, `UnknownWarehouse` and `InsufficientStock` for validation. Here's the first round of business-rule questions. Each one has my suggested default, so you can just answer "ok" or correct the ones you disagree with.

**Hold lifetime**
1. **How long does a hold last?** I suggest a fixed 15 minutes from `reserve`. Should the duration be adjustable through an optional keyword argument on `InventoryService(...)`, or be a package constant? The existing 3-argument constructor has to keep working either way.
2. **When exactly does it expire?** I suggest a hold counts as expired once `clock.now() >= expires_at`. At exactly `expires_at`, confirm fails.
3. **Can holds be extended?** I suggest no: no extension or renewal, and a retry doesn't reset the timer.

**Stock accounting**
4. **Where do held units show up?** I suggest `available = on_hand − allocated − held`, still floored at 0. `allocated()` keeps meaning `PLACED` orders only, so held units don't appear in it or in `stock_report`, and the report keeps its current columns. Alternatively, holds could be folded into `allocated`. Which do you want?
5. **Do holds block other sales?** I suggest yes: `place_order` and other `reserve` calls can't take held units. Expired holds stop counting the moment they lapse.

**Confirm / release**
6. **What does confirm produce?** I suggest a normal `PLACED` order with exactly the held items, `placed_at` set to the confirm time, and `Reservation.order_id` set. Stock isn't re-checked on confirm because the units were already set aside. Or do you want a re-check that raises `InsufficientStock`, for example if a write-off dropped on-hand below what's promised?
7. **Repeated or invalid calls** (my suggestions):
   - Confirm an already-`CONFIRMED` hold: return the same order (safe retry), or raise `InvalidReservationState`?
   - Release an already-`RELEASED` hold: return it unchanged (safe retry), or raise?
   - Confirm a `RELEASED` hold, or release a `CONFIRMED` one: `InvalidReservationState`.
   - Confirm an expired hold: `ReservationExpired`.
   - Release an expired hold: return it with status `EXPIRED` and no error, or raise `ReservationExpired`?
   - Any operation on an unknown id: `ReservationNotFound`.
8. **Order lifecycle after confirm:** I suggest shipping or cancelling that order behaves like any other order and never touches the reservation again.

**Idempotency key**
9. **Same key and same request** (same warehouse, and items equal as a dict, so line order doesn't matter): return the original reservation exactly as it is now, even if it has since been confirmed, released or expired. No new hold, and no stock re-check.
   **Same key, different warehouse or items:** `IdempotencyConflict`.
   **A failed call** (for example `InsufficientStock`) doesn't use up the key, so a later retry can succeed.
   **Scope:** keys are global, not per warehouse, and are remembered for the service's lifetime.
10. **Bad keys:** should an empty or blank `idempotency_key` be rejected? If so, which error? I'd use `InvalidOrder`.

**Smaller points**
11. **Validation:** I suggest all-or-nothing, like `place_order`. Empty items raise `InvalidOrder`; bad quantity, SKU or warehouse raise the existing errors. Shortfalls raise `InsufficientStock`, with `available` already net of holds.
12. **Reservation id format:** I suggest `RES-0001`, `RES-0002`, … numbered sequentially like orders. Does anyone downstream depend on a particular format?

### [spec] user

Most of your defaults are fine, but 1 and 11 need correcting, and 6, 7 and 9 each need a small addition.

1. Make it 20 minutes, not 15. `expires_at` is the creation time plus 20 minutes. A configurable keyword argument is fine as long as the default is 20 minutes.
2. Agreed. From `expires_at` on, that instant included, the hold is EXPIRED and its units are available again. There is no sweep. Expired reservations stay retrievable with status EXPIRED. Only ACTIVE holds expire. CONFIRMED and RELEASED ones never change on their own.
3. Agreed. There is no extension, and a retry never moves `expires_at`.
4. Agreed. Available is on-hand minus units allocated to PLACED orders minus units held by ACTIVE reservations, per SKU per warehouse, never below 0. A hold in one warehouse doesn't touch any other warehouse. I don't mind what the stock report shows.
5. Agreed. `place_order` can only take available stock, and otherwise raises `InsufficientStock`, all-or-nothing as today. Holds never write to the ledger and never change on-hand. Reserve, release, expire and confirm all leave on-hand alone. `receive` and `adjust` are never blocked by holds. If a write-off drops on-hand below what is held, available shows 0 and the reservations stay as they are.
6. Mostly agreed, with two additions.
   - Confirm creates a normal PLACED order in the same warehouse for exactly the units held. After a partial hold, that means only the held units.
   - The hold becomes the order's allocation. Available doesn't change at confirm, and on-hand moves only when the order ships.
   - I don't mind whether confirm re-checks stock after a write-off.
7. Mostly agreed.
   - Confirming an already-CONFIRMED hold returns the same order and creates nothing. This holds at any time, even after the 20 minutes.
   - Releasing an already-RELEASED hold returns it unchanged.
   - Releasing an EXPIRED hold is a no-op that returns it as EXPIRED, with no error.
   - Confirming a RELEASED hold, or releasing a CONFIRMED one, raises `InvalidReservationState`.
   - Confirming an EXPIRED hold, including one that has just lapsed, raises `ReservationExpired`.
   - An unknown id raises `ReservationNotFound` for get, confirm and release.
8. I don't mind. Any sensible behaviour is fine, as long as a repeated confirm creates no new order.
9. Agreed, with these clarifications.
   - "Same request" means the same warehouse and the same requested items, meaning what was asked for, not what ended up held.
   - A repeat returns the existing reservation in whatever state it's in, with no new hold.
   - A different warehouse or different items raises `IdempotencyConflict`, even if the original reservation is finished.
   - Keys are unique across the whole system, all warehouses.
   - A failed `reserve` leaves no trace, so its key can be reused.
10. I don't mind. Any `InventoryError` is fine.
11. This is not all-or-nothing, so please change it. Reservations hold partially.
    - Each line holds as many units as are available right now, up to what was asked.
    - A line with nothing available is left out of `items` entirely, not even shown with 0.
    - `reserve` raises `InsufficientStock` only when no line can hold anything, and then nothing is created.
    - The cart compares `items` with what it asked for to show the shortfall.
    - Bad input is validated exactly like `place_order`. An unknown warehouse raises `UnknownWarehouse`, an unknown SKU raises `UnknownSku`, and a zero or negative quantity raises `InvalidQuantity`. A rejected request holds nothing, not even for its valid lines.
    - I don't mind about empty items.
12. I don't mind. `RES-0001` is fine.

### [spec] agent

I've written `SPEC.md` with the interface copied word for word from your request, 40 numbered acceptance criteria, and a list of non-goals. It isn't committed.

Your answers are in it, including these:
- **Hold lifetime:** 20 minutes by default, changeable through an optional keyword argument; the 3-argument constructor still works.
- **Partial holds:** each line holds what's available, up to what was asked. Lines with nothing available are left out of `items`, and `InsufficientStock` is raised only when no line can hold anything. Bad input holds nothing at all.
- **Expiry:** a hold is `EXPIRED` from `expires_at`, that instant included, with no sweep. Only `ACTIVE` holds expire.
- **Repeated calls:** confirming twice returns the same order, even after the 20 minutes. Releasing an `EXPIRED` hold returns it unchanged, with no error.
- **Idempotency:** requests are compared on what was *requested*, not what was held. A conflict is raised even if the original hold is finished. A failed `reserve` leaves no trace, so its key can be used again.

I added three things you didn't state outright; tell me if any is wrong:
- A confirmed order's `placed_at` is the confirm time. You agreed to my question 6 suggestion without objecting to this part.
- Idempotency keys are kept for the service's lifetime, and forgetting them is listed as a non-goal.
- Concurrency and thread-safety are non-goals, as are partial confirm and partial release.

The points you said you don't mind about are marked as left to the implementation and won't be tested:
- which error an empty cart or blank key raises;
- the reservation id format (`RES-0001` is suggested, not required);
- whether confirm re-checks stock after a write-off;
- what the stock report shows;
- whether cancelling or shipping the order affects the reservation.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

Stock reservations are built as the spec describes, and the full test suite passes. The 20 original tests are unchanged and still pass, and the 63 new ones cover acceptance criteria 1–40.

```
$ python3 -m pytest -q
........................................................................ [ 86%]
...........                                                              [100%]
83 passed in 0.05s
```

**What changed**
- **`inventory.models`**: added `Reservation` with the specified fields, plus a few extra ones that have defaults (`idempotency_key`, `requested`, `created_at`), and the `ReservationStatus` enum. Both are also importable from `inventory`.
- **`inventory.errors`**: added `ReservationNotFound`, `ReservationExpired`, `InvalidReservationState` and `IdempotencyConflict`, all subclassing `InventoryError`.
- **`InMemoryRepository`**: now stores reservations and keeps a global index from idempotency key to reservation. IDs run `RES-0001`, `RES-0002`, …
- **`InventoryService`**:
  - Optional keyword argument `hold_lifetime` (a `timedelta`, default 20 minutes); a zero or negative value raises `ValueError`.
  - `reserve`, `confirm_reservation`, `release_reservation` and `get_reservation` as specified.
  - A new `held()` query, and `available()` is now on-hand minus allocated minus held, never below 0. Because `place_order` already goes through `available()`, it now respects holds too.
- **Expiry** happens with no background job: whenever a reservation is read (looked up, or counted towards availability), it switches from `ACTIVE` to `EXPIRED` if `clock.now() >= expires_at`.
- **README** now describes held units and how reservations move through their states.

**Choices where the spec left room**
- `reserve` checks the input (blank key, empty items, unknown warehouse or SKU, bad quantities) before it looks up the idempotency key. So reusing a key with an invalid request raises the validation error, not `IdempotencyConflict`. This also stops `{"MUG": 2.0}` from counting as the same request as `{"MUG": 2}`.
- An empty or blank idempotency key raises the existing `InvalidOrder`.
- Confirming a hold does not re-check physical stock (criterion 29 allows this).

Nothing is committed. The changes are in the working tree, including the new `tests/test_reservations.py`.
