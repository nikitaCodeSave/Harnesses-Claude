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

I've read the package (`service.py`, `models.py`, `errors.py`, `reports.py`, the tests). Before writing anything, here are the business-rule questions. Each one has my proposed default, so you can answer "ok" or override.

**Hold lifetime**
1. **How long does a hold last?** I'd make it a fixed TTL measured from `reserve`, defaulting to **15 minutes**, with an optional keyword argument on the constructor so `InventoryService(repository, ledger, clock)` still works. Should it be configurable per call or per service, or fixed?
2. **Boundary.** I'd treat a hold as expired once `clock.now() >= expires_at`, so at exactly `expires_at` it's already gone. OK?
3. **Extending a hold.** Can a hold be extended or refreshed (e.g. a new `reserve` with the same key pushes `expires_at` out)? I'd make this a **non-goal**.

**Effect on stock figures**
4. `available` = on-hand − allocated − units in ACTIVE, unexpired holds. Should **`allocated()` include held units**, or stay "PLACED orders only"? I'd keep it orders-only and not add a "held" column to `stock_report`, because `StockRow` is built positionally in existing tests. Is it acceptable that the back-office report won't show holds directly?
5. **Write-offs under a hold.** `adjust` only refuses to take on-hand below zero, so a write-off can still leave on-hand below allocated + held. Should `adjust` also refuse to eat into held stock? I'd leave `adjust` unchanged.

**Reserve**
6. **All or nothing,** same as `place_order`: if any line is short, raise `InsufficientStock` and create nothing. Validation reuses the existing errors: `UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, and `InvalidOrder` for empty items. OK?
7. **Reservation IDs.** I'd use their own sequence, `RES-0001`, `RES-0002`, … Fine?

**Idempotency** (the trickiest part)
8. **Retry with the same key and the same request** (same warehouse, same items in any order) returns the **existing reservation unchanged**, whatever its status. That means a retry after the hold lapsed returns the EXPIRED reservation and doesn't create a new hold. The alternative is that a key is "spent" only while its reservation is ACTIVE or CONFIRMED, so after a release or expiry the same key creates a fresh hold. Which do you want?
9. **Same key, different request** (other warehouse or other items) raises `IdempotencyConflict`. Does that check happen before validation and stock checks? I'd say yes.
10. **Failed reserves.** If `reserve` fails (e.g. `InsufficientStock`), the key is **not** consumed, and a later retry with it can succeed. OK?
11. **Key scope.** Keys are global, not per warehouse, and live forever (no key expiry). OK?

**Confirm and release**
12. **Confirming an ACTIVE, unexpired hold** creates a PLACED `Order` (normal `ORD-` sequence, `placed_at` = confirm time). The held units become allocated, with no new availability check. The reservation becomes CONFIRMED with `order_id` set. Should confirm also re-check physical stock, in case a write-off happened in between? I'd say no: a hold is a promise.
13. **Confirming a hold that has already been confirmed:** return the **same order** again (safe retry), or raise `InvalidReservationState`? I lean towards returning the same order, for the same retry-safety reason as `reserve`.
14. **Confirming an expired hold** raises `ReservationExpired`. Confirming a RELEASED one raises `InvalidReservationState`.
15. **Releasing an ACTIVE hold** makes it RELEASED and frees the stock immediately. On a RELEASED hold, release returns it unchanged (idempotent). On a CONFIRMED hold it raises `InvalidReservationState`. On an expired hold, should it raise `ReservationExpired`, or just return the EXPIRED reservation as a no-op? I'd go with the no-op, since the caller's goal (stock freed) is already met.
16. **Status after expiry.** Once a hold has lapsed, `get_reservation` reports `status == EXPIRED`, even though nothing swept it. An unknown ID raises `ReservationNotFound` on get, confirm and release.
17. **Releasing after confirmation.** If the resulting order is later cancelled through `cancel_order`, the reservation stays CONFIRMED. No link back. OK?

Answer whichever ones you want to change. Anything you don't mention I'll take as agreeing with my proposal.

### [spec] user

Changes from your proposals, by number:

1. The hold lasts 20 minutes, not 15. A default on the service is fine, and it's fixed per service, not per call.
2. OK. The hold is expired from `expires_at` on, with that instant included.
3. OK.
4. OK.
5. OK. `adjust` and `receive` are never blocked by holds. If a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are.
6. This is wrong. Reserve is partial:
   - Each line holds as many units as are available right now, up to what was asked.
   - A line with nothing available is left out of `items` entirely, not even with 0.
   - Only if no line can hold anything does `reserve` raise `InsufficientStock`, and then nothing is created.
   - Validation does reuse the existing errors, and a rejected request holds nothing, not even for its valid lines. Empty items can raise any `InventoryError`.
7. OK.
8. Return the existing reservation in its current state, whatever that state is. It creates no new hold and doesn't move `expires_at`. "Same request" means the same warehouse and the same requested items, meaning what was asked for, not what ended up held.
9. Same key with a different warehouse or items raises `IdempotencyConflict`, even if the original reservation is finished. I don't mind the order relative to validation.
10. OK. A failed `reserve` leaves no trace, so its key can be reused.
11. OK.
12. Confirming an ACTIVE hold places an ordinary PLACED order in the same warehouse for exactly the units held. After a partial hold, that means only those units. Available doesn't change at confirm, and on-hand moves only when the order ships. If a write-off pushed on-hand below the hold, I don't mind whether confirm succeeds or raises `InsufficientStock`.
13. Return the same order and create nothing. This applies at any time, even after the 20 minutes have passed.
14. OK. This includes a hold that has just lapsed.
15. OK. Releasing an EXPIRED hold is a no-op that returns it unchanged, and releasing a RELEASED hold does the same. Both are without error.
16. OK. Expired reservations stay retrievable with status EXPIRED.
17. I don't mind.

Also, `place_order` can only take available stock, so direct orders compete with holds. It stays all-or-nothing as today. Partial filling is for reservations only.

### [spec] agent

I've written the spec to `SPEC.md`. It has 37 acceptance criteria, a non-goals list, and a short list of points you said you don't mind about. Your interface section is copied in word for word.

A few rules in the spec follow from your answers but weren't stated outright. Please check them:

- **Which holds expire:** only ACTIVE holds lapse. CONFIRMED and RELEASED reservations keep their status after `expires_at` passes (criterion 4).
- **Comparing retries:** two requests with the same items in a different order count as the same request (criterion 18).
- **Retrying a partial hold:** suppose a hold asked for `{MUG: 5}` but only got 3. A retry with `{MUG: 5}` returns that reservation. A retry with `{MUG: 3}` raises `IdempotencyConflict` (criterion 19).
- **Confirmed holds:** the resulting order is an ordinary order that can be shipped or cancelled as usual (criterion 26). Releasing a confirmed hold raises `InvalidReservationState`, and the reservation and its order stay as they were (criterion 32).

I left one thing open that we didn't discuss: whether an empty idempotency key is accepted. If you want it rejected, tell me and I'll add it.

### [spec] user

All four points match what I want. On the empty idempotency key, I don't mind, so do whatever you think is sensible. Nothing else from me.

### [spec] agent

I added the empty-key question to the "Left to the implementer" section of `SPEC.md`. Whoever builds this can choose whether to accept an empty key. If they reject it, it must be an `InventoryError` and must leave no trace, the same as any other rejected request.

That closes the last open point, so `SPEC.md` is done. I haven't written any code or committed anything.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've added 137 acceptance tests under `tests/acceptance/`, covering all 37 acceptance criteria. 133 fail and 4 pass; the 4 that pass are expected to (explained below). I didn't change any package code.

**Command:**
```
python3 -m pytest tests/acceptance -q -p no:cacheprovider
```
**Output (tail):**
```
FAILED tests/acceptance/test_reserve.py::test_reservation_ids_are_sequential
FAILED tests/acceptance/test_reserve.py::test_reservation_ids_are_independent_of_order_ids
FAILED tests/acceptance/test_reserve.py::test_idempotent_retry_does_not_consume_an_id
133 failed, 4 passed in 0.43s
```

Every failure comes from the feature not existing yet, not from a broken test. Grouping the failures by error (`--tb=line`) gives:
- 126 × `AttributeError: ... has no attribute 'reserve'`
- 4 × `inventory.errors` has no `ReservationNotFound`
- 1 each for missing `models.Reservation` and missing `models.ReservationStatus`
- 1 × `AssertionError` from the check that the reservation methods exist

**The 4 that pass:**
- **Existing suite passes (36):** runs `pytest tests --ignore=tests/acceptance` in a subprocess.
- **Existing tests are unmodified (36):** uses `git diff`, and skips if the folder isn't a git checkout.
- **No wall-clock calls in package code (37):** scans `src/inventory` for things like `datetime.now(`, `utcnow`, `date.today(` and `time.time(`.
- **`StockRow` fields are unchanged (8).**

**Files** (fixtures from `tests/conftest.py`, plus a `stocked` fixture in `tests/acceptance/conftest.py`):
| File | Criteria |
|---|---|
| `test_reservation_interface.py` | Interface section: `Reservation` fields, the four `ReservationStatus` members, new errors subclass `InventoryError`, `reserve` signature |
| `test_hold_lifetime.py` | 1–5, including one microsecond before `expires_at` vs exactly at it |
| `test_availability_with_holds.py` | 6–10 |
| `test_reserve.py` | 11–17 |
| `test_reservation_idempotency.py` | 18–22, run for each of ACTIVE/CONFIRMED/RELEASED/EXPIRED |
| `test_confirm_reservation.py` | 23–29 |
| `test_release_and_lookup.py` | 30–34 |
| `test_direct_orders_vs_holds.py` | 35 |
| `test_reservation_compatibility.py` | 36–37, plus a behaviour check with clocks set to 1999 and 2199 |

**Decisions you may want to check:**
- **Errors and statuses are looked up when each test runs, not at import.** So each test fails on its own instead of the whole run stopping at collection.
- **"No trace" includes the ID sequence.** After a rejected or failed `reserve`, the next reservation must still be `RES-0001`. I read this from criteria 17 and 22 together.
- **I used two existing public methods** besides the ones the spec lists: `repo.orders()` / `repo.get_order()` and `order.quantity_of()`, to check that no order was created.
- **Criterion 2:** only the 20-minute default is tested. Choosing a different duration at construction is optional and unnamed, so I left it out. "Can't be set per call" is tested by expecting a `TypeError` when `reserve` gets a fourth positional argument.
- **Nothing in the spec's "Left to the implementer" list is asserted.** For example, which SKU `InsufficientStock` names, or whether the idempotency check runs before validation. Every conflict test sends a request that is otherwise valid.

The full suite (`python3 -m pytest -q`) gives 133 failed, 24 passed: the 20 existing tests plus the 4 above.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

Stock reservations are built as SPEC.md describes, and both the acceptance tests and the existing suite pass:

```
$ python3 -m pytest -q -p no:cacheprovider
........................................................................ [ 45%]
........................................................................ [ 91%]
.............                                                            [100%]
157 passed in 0.16s
```

That's 137 acceptance tests and 20 existing ones. Nothing under `tests/` was changed. I haven't committed anything.

**How it works**
- **Code:** the four new methods are in `src/inventory/service.py`. `models.py` gets `Reservation` and `ReservationStatus`, `errors.py` gets the four new errors, and `repository.py` now stores reservations, their ID sequence (`RES-0001`, …) and idempotency keys. The key records go in the repository, so a future database-backed version would keep them too.
- **Expiry:** there is no background job. Whenever a reservation is read, or `available` is calculated, an ACTIVE reservation whose `expires_at` has passed (by the injected clock) is marked EXPIRED and saved. Only ACTIVE, unexpired reservations count against `available`. `allocated`, `on_hand` and `stock_report` are unchanged.
- **Hold duration:** 20 minutes by default. It can be set when the service is created with `InventoryService(repo, ledger, clock, hold_duration=...)`, but not per call.

**Choices on the points SPEC.md left open**
- A request is validated before its idempotency key is checked. So a bad request always gets its validation error, even if the key was used before.
- An empty or non-string idempotency key is rejected with `InvalidOrder` and leaves no trace.
- When nothing can be held, `InsufficientStock` names the first requested SKU.
- If a write-off has taken stock below what a reservation holds, `confirm_reservation` still succeeds: the order takes over the held units without checking stock again. Shipping that order will fail with `InsufficientStock` until stock is restored.
- A reservation stays CONFIRMED after its order ships or is cancelled.
- The methods return copies of reservations, so changing a returned object doesn't change what's stored. Orders, by contrast, are still returned as the stored objects, as before.

I also added a short section on holds and how reservations move between states to `README.md`.

### [review1] operator

Review the changes since commit 8bbb0e616cf6047ac588921ff1b534ae2728df96 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md. Nothing needs fixing.

I compared the diff against all 37 acceptance criteria and the "Left to the implementer" choices. The full suite (`python3 -m pytest`) passes: 157 tests, including the existing tests and `tests/acceptance/`.

The points most likely to go wrong are all handled correctly:

- **Expiry at the exact instant (3, 28, 33):** the check uses `now >= expires_at` (`src/inventory/service.py:242`). It runs when a reservation is loaded and inside `_held`, so `get_reservation`, `available`, `confirm_reservation` and `release_reservation` all see expiry without a sweep. Only ACTIVE reservations expire, so CONFIRMED and RELEASED keep their status.
- **Idempotency (18–22):** a key is bound to the requested items, not the held ones. It is saved only after a reservation is actually created (`service.py:186`). A retry returns the current state and never changes `expires_at`. A different warehouse or different items raises `IdempotencyConflict`, whatever the original's status.
- **Failed `reserve` calls leave no trace (14, 16, 22):** validation and the "nothing to hold" check both run before a reservation ID is taken or anything is saved. The ID sequence and the key stay untouched.
- **Availability (6–10, 25, 35):** `available` subtracts held units on top of allocated ones. `allocated`, `on_hand`, `adjust` and the stock report path are otherwise unchanged. Confirming moves the units from held to allocated, so the net is zero. `place_order` stays all-or-nothing against the new `available`.
- **Confirm and release states (23, 24, 26–32, 34):** confirming twice returns the same order, even after expiry. Confirming an expired reservation raises `ReservationExpired`, and a released one raises `InvalidReservationState`. Releasing a CONFIRMED reservation raises, releasing a RELEASED or EXPIRED one does nothing, and unknown IDs raise `ReservationNotFound`.
- **Clock and hold duration (1, 2, 5, 37):** the hold lasts 20 minutes by default and can only be changed when the service is built. Nothing in the package reads the wall clock.

FINDINGS: 0
