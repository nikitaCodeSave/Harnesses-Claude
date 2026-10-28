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

I've read the package (service, repository, models, errors, reports, tests). Before writing anything, here's the first round of questions. Each one has my suggested default, so you can just answer "ok" or override the ones you disagree with.

**A. Hold lifetime**
1. **How long does a hold last?** I suggest 15 minutes from `reserve`. Should it be fixed, or configurable per service through an optional constructor argument with a default (existing `InventoryService(repo, ledger, clock)` calls keep working)? Or per call?
2. **Exact boundary:** suggest a hold is expired when `now >= expires_at`, so at exactly `expires_at` it is already lapsed.
3. **No extension or renewal of a hold.** If checkout takes too long, the cart has to reserve again with a new key. Out of scope?

**B. Idempotency (`reserve` retries)**
4. **Same key, same request** (same warehouse and same items) → return the original reservation unchanged, whatever its status is now (ACTIVE, CONFIRMED, RELEASED or EXPIRED). No new hold, and stock is not re-checked. Agree? The alternative is that once the original has expired or been released, the same key creates a fresh hold.
5. **Same key, different warehouse or items** → `IdempotencyConflict`. Agree?
6. **Key scope and lifetime:** keys are global (not per warehouse) and never expire. Agree?
7. **Empty or blank idempotency key:** reject it. Which error should that be? I'd propose a new error isn't needed; maybe `InvalidOrder`? Or should any string be accepted?

**C. Confirm / release semantics**
8. **Confirm twice** (cart retries after a timeout): return the same `Order` again, or raise `InvalidReservationState`? I lean toward returning the same order, since you said retries must be safe.
9. **Release twice:** return the RELEASED reservation again (no-op), or raise `InvalidReservationState`? I lean toward the no-op.
10. **Release a CONFIRMED reservation** → `InvalidReservationState`. To undo it, the caller cancels the order. Agree?
11. **Confirm or release once the hold has lapsed:**
    - Confirm → `ReservationExpired`.
    - Release → `ReservationExpired`, or a quiet return of the EXPIRED reservation? The stock is already free either way.
12. **Confirm a RELEASED reservation** → `InvalidReservationState`. Agree?

**D. Stock accounting**
13. **Placing orders:** holds reduce `available` for everyone, including direct `place_order` calls and other `reserve` calls. `reserve` is all-or-nothing like `place_order`, raising `InsufficientStock` when any line exceeds available. Agree?
14. **Confirm while stock dropped:** suppose stock was written off while the hold was active, so on-hand is now below holds plus allocations. Should confirm still succeed (the hold is a promise), or re-check and raise `InsufficientStock`?
15. **`allocated()` and the stock report:** should `allocated()` include held units, or stay "PLACED orders only"? If it stays orders-only, the `stock_report` row no longer satisfies `available = on_hand - allocated`. Should I add a separate "held/reserved" figure (a query and/or a report column), or is changing the report out of scope?
16. **Validation of `reserve`:** same as `place_order`:
    - empty items → `InvalidOrder`
    - bad quantity → `InvalidQuantity`
    - unknown SKU → `UnknownSku`
    - unknown warehouse → `UnknownWarehouse`

    Agree? Also, does validation happen before the idempotency lookup? My suggestion is that the lookup comes first, so a retry with an identical payload always gets its original back.

**E. Resulting order and identifiers**
17. **The order created by confirm:** it's a normal PLACED order. It uses the ordinary `ORD-nnnn` sequence and has `placed_at` set to the confirm time. The reservation keeps `order_id` pointing at it. Agree?
18. **Reservation IDs:** `RES-0001`, `RES-0002`, … sequential like orders. Fine, or don't care?
19. **Missing reservation:** unknown `reservation_id` on get, confirm or release → `ReservationNotFound`.

### [spec] user

1. 20 minutes, not 15. Fixed by default is fine. A configurable constructor option is fine too, as long as the default is 20 minutes.
2. Agreed. At exactly `expires_at` the hold is expired.
3. Agreed, no extension or renewal.
4. Agreed. Same key and same request returns the existing reservation in its current state, whatever that is. No new hold, no stock re-check, and `expires_at` doesn't move. "Same request" means the same warehouse and the same requested items, not the items actually held.
5. Agreed. It raises `IdempotencyConflict`, even if the original reservation is finished.
6. Keys are global across all warehouses. One addition: a `reserve` call that fails leaves no trace, so its key can be reused.
7. I don't mind. Any `InventoryError` is fine.
8. Return the same order and create nothing new. This holds at any time, even after the 20 minutes have passed.
9. Agreed, a no-op that returns the reservation unchanged.
10. Agreed, `InvalidReservationState`.
11. Confirm of an expired reservation raises `ReservationExpired`. That includes one that has just lapsed. Release of an expired reservation is a quiet no-op that returns it unchanged, still EXPIRED, with no error.
12. Agreed, `InvalidReservationState`.
13. Holds reduce available for everyone, and `place_order` can only take available stock. `place_order` stays all-or-nothing. `reserve` is different: it holds partially.
   - Each line holds as many units as are available right now, up to what was asked.
   - A line with nothing available is left out of `items` entirely, not even with 0.
   - `reserve` fails with `InsufficientStock` only when no line can hold anything, and then nothing is created.
   - The cart compares `items` with what it asked for to show the shortfall.
14. I don't mind whether it succeeds or raises `InsufficientStock`.
15. Available is on-hand minus units allocated to PLACED orders minus units held by ACTIVE reservations, per SKU per warehouse, never below 0. A hold in one warehouse doesn't affect any other warehouse. I don't mind whether `allocated()` includes holds or whether the report shows held units, so use your judgment. Holds never write to the ledger and never change on-hand, so reserve, release, expire and confirm are not stock movements. `receive` and `adjust` are never blocked by holds. If a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are.
16. Validation is the same as `place_order`: unknown warehouse gives `UnknownWarehouse`, unknown SKU gives `UnknownSku`, and zero or negative quantity gives `InvalidQuantity`. A rejected request holds nothing, not even for its valid lines. I don't mind about empty items. I don't mind about the order of validation versus the idempotency lookup either.
17. Agreed, with one addition. Confirm places an ordinary PLACED order in the same warehouse for exactly the units held, which after a partial hold means only those. The reservation becomes CONFIRMED and its `order_id` is that order's id. Available doesn't change at confirm, and on-hand moves only when the order ships.
18. I don't mind the id format.
19. Agreed, `ReservationNotFound` for get, confirm and release.

### [spec] agent

The spec is in `SPEC.md`: 37 numbered, checkable acceptance criteria plus a list of non-goals. The interface you fixed is copied in word for word. Nothing is implemented yet.

You said you didn't mind on these points, so I made the call and wrote it into the spec. Tell me if you want any of them changed:

- **Confirm after a write-off** (criterion 26): confirm still succeeds and doesn't re-check stock. The hold was a promise, and this matches your rule that reservations stay as they are after a write-off.
- **`allocated()`** (criterion 22): it keeps its current meaning, units in PLACED orders only. Held units aren't added to it.
- **Stock report:** its layout doesn't change (listed as a non-goal). Its `available` column will reflect holds, so in that report `on_hand - allocated` won't equal `available` while holds exist. If the back office needs to see held units, I'd add a column for them.
- **Empty items or a blank idempotency key** (criterion 7): rejected with some `InventoryError`, and nothing is created.
- **Validation vs. idempotency lookup:** left open on purpose. Either order meets the spec.
- **Hold length** (criterion 1): 20 minutes by default, which may be made configurable through an optional constructor argument.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

Stock reservations are built as SPEC.md describes, and the full test suite passes. I haven't committed anything.

```
$ python3 -m pytest -q
........................................................................ [ 87%]
..........                                                               [100%]
82 passed in 0.05s
```

That's the 20 existing tests, which I didn't change (criterion 37), plus 62 new ones in `tests/test_reservations.py`. The new tests cover every acceptance criterion from 1 to 36.

**How it works**
- **Storage:** reservations live in the existing in-memory repository, alongside a record of each idempotency key and the request it was used with.
- **Expiry needs no sweep:** every read checks the clock. Holds count only while the clock is before `expires_at`, and any read of an ACTIVE reservation that has reached `expires_at` marks it EXPIRED. So `available`, `place_order`, `reserve` and `get_reservation` all see the expiry the moment it happens, exactly at `expires_at` included.
- **Available:** now subtracts a new `held(sku, warehouse)` figure. `allocated` and `on_hand` mean what they did before, and nothing reservation-related writes to the ledger.
- **Retries:** the request is validated before the key is looked up. That stops a retry sending `True` or `1.0` from counting as the same request as an earlier one with `1`, since Python treats them as equal. Nothing is stored until a call succeeds, so a call that fails leaves its key unused.
- **Holding time:** the 20 minutes can be changed with an optional `hold_duration` constructor argument.

**Choices the spec left open**
- **Blank idempotency key:** raises the existing `InvalidOrder` (as an empty `items` already does). I didn't add a fifth new error class.
- **Live objects:** reservations are returned as the stored objects, the same way orders already are. A copy you're holding updates when you confirm or release through the service. But if you're holding one when it lapses, it only shows EXPIRED once you read it again through the service, so re-fetch with `get_reservation` rather than trusting an old copy.
- **Ids:** reservation ids follow the pattern `RES-0001`, `RES-0002`, … The spec only requires them to be unique.

I also exported `Reservation` and `ReservationStatus` from the package and added the reservation flow to the README.
