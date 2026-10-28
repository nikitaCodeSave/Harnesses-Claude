### [build] operator

/harness:task Add stock reservations to the `inventory` package. Checkout must be able to hold stock for a cart before payment, then either confirm the hold into an order or release it. Holds nobody confirms must lapse on their own after a while, and retries from the cart service must be safe (idempotency key).

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

Before I write the spec I need your call on some business rules. I read the code: there's no `GLOSSARY.md`, no ADRs, and no specs dir yet. For each question I've put a suggested answer in **bold**, so you can just say "defaults" or override by number.

**Hold lifetime**
1. How long does a hold last before it lapses? Is it fixed, or set per service? **15 minutes by default, overridable through an optional keyword argument (`InventoryService(repo, ledger, clock, hold_ttl=timedelta(...))`). The 3-arg constructor keeps working.**
2. Is a hold still good at exactly `expires_at`? **No: it lapses when `now >= expires_at`.**
3. Should `get_reservation` on a lapsed hold report `EXPIRED`, with the units back in `available`, without anyone calling a sweep? **Yes.**

**Confirm / release transitions**
4. `confirm_reservation` on a lapsed hold: **raise `ReservationExpired`.**
5. `confirm_reservation` on an already-CONFIRMED hold, for example when the cart retries after payment: **return the same order without creating a second one.** (Or raise `InvalidReservationState`?)
6. `release_reservation` on an already-RELEASED hold: **return it unchanged.** On a CONFIRMED hold: **raise `InvalidReservationState`.** On a lapsed hold: **return it as EXPIRED with no error, since the units are already free.** (Or raise `ReservationExpired`?)
7. Does confirm re-check stock? A write-off after the hold could leave less on hand than was held. **No: the hold is a promise. Confirm turns it into a PLACED order unconditionally, and `ship_order` already checks physical stock.**
8. The confirmed order gets `placed_at` = confirm time and a normal `ORD-nnnn` id. Cancelling or shipping that order later doesn't touch the reservation, which stays CONFIRMED. **Yes.**

**Idempotency**
9. Same key with the same warehouse and items: **return the original reservation, whatever its current status (including CONFIRMED, RELEASED or EXPIRED). It never creates a new hold.** Same key with a different warehouse or items: **raise `IdempotencyConflict`.**
10. Key scope: **global, not per warehouse, and remembered forever.** (Or should a key become reusable after its hold expires or is released?)
11. If `reserve` fails (for example `InsufficientStock`), is the key burned? **No: nothing is recorded, so a retry can succeed later.**

**Validation and stock views**
12. `reserve` is all-or-nothing and validates like `place_order`: unknown warehouse or SKU, empty items → `InvalidOrder`, bad quantity → `InvalidQuantity`, short stock → `InsufficientStock`. **Yes. An empty or non-string key raises `InvalidOrder`.**
13. Active holds reduce `available` (`on_hand − allocated − held`, floored at 0). **`allocated()` stays orders-only, and I add a `held(sku, warehouse)` query.** That leaves `stock_report`. Should I **add a `held` column to `StockRow`** (this changes one existing test), or **leave the report alone** as a non-goal?
14. Reservation ids look like **`RES-0001`, sequential like orders.**

### [build] user

Answers by number:
1. 20 minutes, not 15. A configurable TTL is fine as long as the default is 20 min. `expires_at` = creation time + 20 min.
2. Not good at exactly `expires_at`. From that instant on it is EXPIRED, so `now >= expires_at` is right.
3. Yes. It reports EXPIRED and the units are available again, with no sweep.
4. `ReservationExpired`. Agreed.
5. Return the same order and create nothing. This holds at any time, even after the 20 minutes have passed.
6. All three are right. RELEASED returns unchanged. CONFIRMED raises `InvalidReservationState`. EXPIRED is a no-op that returns it as EXPIRED, with no error.
7. I don't mind either way. Do whatever is simplest.
8. Fine. Placing the order at confirm time with a normal id is OK. One more point: the hold becomes that order's allocation, so `available` doesn't change at confirm. On-hand only moves when the order ships.
9. Agreed.
10. Global across all warehouses, and a key is never reused for a different request. Agreed.
11. Agreed. A failed `reserve` leaves no trace, so the key can be used again.
12. Not all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of `items` entirely. Only if no line can hold anything does `reserve` fail with `InsufficientStock`, and then nothing is created. Validation is as you listed: unknown warehouse is `UnknownWarehouse`, unknown SKU is `UnknownSku`, zero or negative quantity is `InvalidQuantity`. A rejected request holds nothing, not even for its valid lines. I don't mind about empty items or an empty key.
13. Agreed on available = on-hand − allocated − held, floored at 0, and a hold in one warehouse doesn't affect others. `place_order` can only take what's available, and it stays all-or-nothing. I don't mind about the report or `held()`, so leave the report alone.
14. Any id format is fine. Also, holds never write to the ledger or change on-hand. `receive` and `adjust` are never blocked by holds. If a write-off drops on-hand below what is held, available shows 0 and the reservations stay as they are. Unknown reservation id raises `ReservationNotFound` for get, confirm and release.

### [build] agent

Stock reservations are built to your rules and the full test suite passes:

```
$ python3 -m pytest -q
..............................................................           [100%]
62 passed in 0.02s
```

The spec is at `specs/stock-reservations.md`. It includes your interface word for word, the acceptance criteria as checkboxes, and the non-goals. `tests/test_reservations.py` covers every criterion. To make sure the expiry tests can actually fail, I briefly changed the cut-off from `now >= expires_at` to `>`: four tests failed, then I put it back.

**How it works**
- **Holds:** a hold reduces `available` (on-hand − allocated − held) but never writes to the ledger or changes on-hand.
- **Partial holds:** `reserve` holds as much as is available on each line, up to what was asked, and leaves out lines with nothing available. It raises `InsufficientStock` only when it can hold nothing at all.
- **Expiry:** a hold lapses when `now >= expires_at`, worked out from the clock whenever someone reads it, so no sweep is needed. The 20-minute default can be changed with an optional `hold_ttl=` keyword; the three-argument constructor still works.
- **Confirm:** it creates a normal PLACED order with `placed_at` = confirm time, and `available` doesn't change. Confirming twice returns the same order, even after the 20 minutes. Confirming a lapsed hold raises `ReservationExpired`, and confirming a released one raises `InvalidReservationState`.
- **Release:** releasing an already-released or lapsed hold returns it as it is. Releasing a confirmed one raises `InvalidReservationState`.
- **Idempotency keys:** each key is recorded with the original request (warehouse plus the requested items, not what was actually held). It is shared across warehouses and never expires. A failed `reserve` records nothing, so the key can be reused.
- **Ids:** reservations are numbered `RES-0001`, `RES-0002`, and so on. `stock_report` is unchanged.

**From the `/code-review` pass**
- **Fixed:** a retry with an invalid quantity like `{"MUG": True}` matched an earlier `{"MUG": 1}` (Python treats `True` as 1) and returned the old reservation. I added a test that failed, then fixed it by validating the request before looking up the key.
  - This adds one rule you didn't state: an invalid request gets its validation error (say `UnknownWarehouse`) even if its key was used before, rather than `IdempotencyConflict`. I've recorded it in the spec.
- **Fixed:** saving a new hold and saving its key were two separate repository calls. A database-backed repository failing between them could hold stock twice on retry. It's now a single `add_reservation` call.
- **Not changed:**
  - `get_reservation` returns the stored object, so a caller who edits its `items` changes the hold itself. Orders already work this way.
  - Availability is worked out by scanning every order and hold, and holds that lapse unread are still scanned. That's fine in memory but will slow down as abandoned holds pile up.
  - A bad `hold_ttl` raises a plain `ValueError`, as `FixedClock` does.

**Project docs**
- I created `GLOSSARY.md`, which covers the existing stock terms plus reservations.
- I added two decision records under `docs/adr/`: `0001-lazy-reservation-expiry.md` and `0002-reservation-idempotency-keys.md`.
- I updated `README.md`.

Nothing is committed yet.
