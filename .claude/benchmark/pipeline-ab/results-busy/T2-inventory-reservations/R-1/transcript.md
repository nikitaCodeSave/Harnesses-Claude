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

I've read the package. It has a ledger, allocations from `PLACED` orders, `available = on_hand - allocated` floored at 0, and all-or-nothing `place_order`. Below are the business rules I can't infer from the code. Each one has my suggested default, so you can answer with "defaults OK except N".

**Hold lifetime**
1. **How long does a hold last?** Your interface has no TTL parameter. Default: a fixed 15 minutes, set by an optional keyword argument on the constructor (`InventoryService(repo, ledger, clock, reservation_ttl=...)`), so existing callers still work. Is 15 minutes right, and should the duration be configurable at all?
2. **What happens at the exact expiry moment?** Default: a hold is expired when `now >= expires_at`, so it's already dead at that instant.
3. **Can a hold be extended?** Default: no. Extending or refreshing a hold is a non-goal.

**Reserve**
4. **All or nothing?** Default: yes, like `place_order`. If any SKU is short, the call raises `InsufficientStock` and nothing is held.
5. **Validation:** Default: reuse the existing errors. Empty `items` raises `InvalidOrder`, a bad quantity raises `InvalidQuantity`, and unknown SKUs or warehouses raise `UnknownSku`/`UnknownWarehouse`. Is an empty-string `idempotency_key` allowed, or should it be rejected (and with which error)?

**Idempotency**
6. **What scope does a key have, and how long does it live?** Default: keys are global (not per warehouse) and remembered forever.
7. **Same key, same request (same warehouse and same items):** Default: return the original reservation as it is now, whatever its status. If it has expired, released or confirmed, the caller gets that back. No new hold is created and the clock isn't reset.
8. **Same key, different warehouse or items:** raise `IdempotencyConflict`. Default: item order doesn't matter, so `{"A":1,"B":2}` counts as the same request as `{"B":2,"A":1}`.
9. **Does a failed reserve use up its key?** For example, it fails with `InsufficientStock` and the cart retries later with the same key once stock exists. Default: no, failed attempts leave no trace.

**Confirm / release**
10. **Confirming a held reservation:** Default: it creates a normal `PLACED` order with the same lines, `placed_at` set to the confirm time and a normal `ORD-` id. The reservation becomes `CONFIRMED` with `order_id` set, and the stock moves from "held" to "allocated" with no gap. Is that right?
11. **Can a confirm fail because on-hand stock dropped?** On-hand can fall below the held quantity through `adjust()`, for example a write-off. Default: the hold is a guarantee against other orders but not against physical loss. Confirm raises `InsufficientStock` and the reservation stays `ACTIVE`. The alternative is to confirm anyway and over-allocate.
12. **Repeated calls:** These are what you'd see from cart retries.
    - Confirming an already-`CONFIRMED` reservation: default is to return the same order without creating a new one. Or would you rather it raise `InvalidReservationState`?
    - Releasing an already-`RELEASED` reservation: default is to return it unchanged without an error.
13. **Invalid transitions:** Default:
    - Confirming an expired hold raises `ReservationExpired`.
    - Releasing an expired hold returns it with status `EXPIRED`, no error.
    - Releasing a confirmed hold raises `InvalidReservationState`.
    - Confirming a released hold raises `InvalidReservationState`.
14. **Order cancelled after confirm:** If the order created by a confirm is later cancelled, the reservation stays `CONFIRMED`. It isn't revived.

**Visibility**
15. **Does `allocated()` include holds?** Default: no. `allocated()` still means orders only, and holds are subtracted separately in `available = on_hand - allocated - held` (floored at 0). Do you want a public `held(sku, warehouse)` query and a "held" column in `stock_report`, or is that out of scope?
16. **Status of a lapsed hold that nobody has touched:** Default: `get_reservation` reports `EXPIRED`, and the units count as free in `available()` from that moment.
17. **Reservation ids:** Default: `RES-0001`, `RES-0002`, … numbered in sequence the same way order ids are. Do you want that format fixed in the spec?

Concurrency and multi-process safety would be a non-goal, since this is an in-memory, single-threaded package. Tell me if you see it differently.

### [spec] user

Going through your points by number:

1. No, the hold lasts 20 minutes, not 15 (95% of payments finish within 18 minutes). A configurable TTL as an optional argument is fine, as long as the default is 20 minutes.
2. Agreed. expires_at = creation time + 20 min. From expires_at on, that instant included, the hold is expired and its units are available again.
3. Agreed, no extending.
4. No, partial holds. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of items entirely, not shown with 0. reserve raises InsufficientStock only when no line can hold anything, and then nothing is created. The cart compares items with what it asked for to show the shortfall.
5. Your validation defaults for unknown warehouse, unknown SKU and bad quantity match place_order, and I'm fine with them. A rejected request holds nothing, not even for its valid lines. I don't mind how you handle empty items or an empty key; any InventoryError is fine.
6. Agreed. Keys are global across all warehouses and remembered forever.
7. Agreed. Compare against the items that were requested, not the items that ended up held. The repeat doesn't move expires_at.
8. Agreed, including that item order doesn't matter. The conflict applies even if the original reservation is finished.
9. Agreed. A failed reserve leaves no trace, so its key can be reused.
10. Agreed, with one addition: if the hold was partial, the order covers only the units actually held.
11. I don't mind. Either confirming or raising InsufficientStock is fine.
12. Confirming an already-CONFIRMED reservation returns the same order and creates nothing. That holds at any time, even after the 20 minutes have passed, because the payment service retries confirm. Releasing an already-RELEASED reservation returns it unchanged, as you suggest.
13. Agreed on all four. Releasing an expired reservation is a no-op that returns it with status EXPIRED.
14. Fine. I don't mind what a repeated confirm returns after the order is cancelled or shipped, as long as it creates no new order.
15. I don't mind whether you add a public held query or a stock report column. Just keep allocated() as orders only.
16. Agreed. Expiry takes effect without a sweep, and expired reservations stay retrievable with status EXPIRED.
17. I don't mind the id format.

I agree that concurrency is a non-goal.

### [spec] agent

I wrote the spec to `SPEC.md` in the repo root. It isn't committed yet. It has the fixed interface copied word for word, plus the default 20-minute hold, 33 acceptance criteria, the non-goals, and a short list of things you said you don't mind about, left to whoever implements it.

Three criteria aren't your literal words, so check they match what you mean:

- **#5:** a released or expired hold frees its units immediately, and `available()` reflects expiry the moment the clock reaches `expires_at`.
- **#23:** confirming a hold doesn't change `available()`. The units go straight from held to allocated, so nobody can grab them in between.
- **#28:** when on-hand stock has dropped below what's held, you said either outcome is fine. I added one condition: confirm must never end half-done. Either there's an order and the reservation is `CONFIRMED`, or there's no order and the reservation is unchanged.

Tell me if you want any of those changed, or if I should start implementing against the spec.

### [spec] user

All three match what I mean, so keep them as written. Don't start implementing. I'll kick off that step myself later.

### [spec] agent

Okay, `SPEC.md` stays as written, uncommitted, and I won't start on the code. When you're ready to implement, I'll work from that file.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've written tests for all 33 acceptance criteria in `tests/acceptance/`, and the feature is still unimplemented. 110 tests fail and 4 pass.

**Command:**
```
python3 -m pytest tests/acceptance -q
```

**Output (tail):**
```
FAILED tests/acceptance/test_reserve.py::test_c13_rejected_request_key_can_be_reused[nothing-available]
FAILED tests/acceptance/test_reserve.py::test_c14_each_reservation_gets_a_unique_id
110 failed, 4 passed in 0.32s
```

**Why they fail:** I grouped the failures by exception. All of them come from the missing feature, not from mistakes in the tests:
```
106 AttributeError: 'InventoryService' object has no attribute 'reserve'
  1 AttributeError: module 'inventory.errors' has no attribute 'ReservationNotFound'
  1 AttributeError: module 'inventory.models' has no attribute 'Reservation'
  1 AttributeError: module 'inventory.models' has no attribute 'ReservationStatus'
  1 AssertionError: reserve   (the service doesn't have the reservation methods yet)
```

**The 4 passing tests** are for criterion 33 (compatibility). That criterion requires existing behaviour to stay the same, so these should already pass. They:
- run the original test suite in a subprocess;
- check that the three-argument constructor still works;
- run the order flow with no reservations;
- run `stock_report` with no reservations.

**Files:** each test name starts with the criterion it covers (`test_c1_…` to `test_c33_…`).
- `test_reservation_availability.py`: criteria 1–5
- `test_reserve.py`: 6–14
- `test_reservation_idempotency.py`: 15–18
- `test_get_reservation.py`: 19–21
- `test_confirm_reservation.py`: 22–28
- `test_release_reservation.py`: 29–32
- `test_reservation_compatibility.py`: 33
- `test_reservation_interface.py`: checks the models, errors and methods named in the spec's Interface section
- `conftest.py`: adds one fixture, `stocked`, which puts stock in place. It builds on the existing fixtures in `tests/conftest.py`.

**Choices worth checking:**
- **Expected values come from the spec.** The tests use the default 20-minute TTL, `expires_at` boundaries at exactly `now >= expires_at` (checked one microsecond either side), and `available = max(0, on_hand − allocated − held)`.
- **Only public interfaces are used:** the four new service methods, existing service methods, `repo.orders()` / `repo.get_order()`, `len(ledger)` and `stock_report`. The new errors and models are looked up when each test runs, so a missing name fails that one test instead of breaking collection for the whole suite.
- **The custom TTL isn't tested.** The spec doesn't name the constructor parameter, so only the default is covered.
- **Criterion 28 accepts either outcome**, as the spec allows: either the order is created, or `InsufficientStock` is raised. In both cases it checks that nothing is left half-done. It uses a two-line reservation, so a partly created order would be caught.
- **Criterion 12** only checks that the error is some `InventoryError`, since the spec leaves the exact subclass open.

Nothing is committed: `tests/acceptance/` and `SPEC.md` are both untracked. I deleted the `__pycache__` folders my test runs created.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

Stock reservations are in, and both the acceptance tests and the existing suite pass. I didn't modify `tests/acceptance/`.

**Command:** `python3 -m pytest -q` (run from the repo root; this runs both the existing tests and `tests/acceptance/`)
```
........................................................................ [ 53%]
..............................................................           [100%]
134 passed in 0.21s
```
Of those, 114 are acceptance tests (`python3 -m pytest -q tests/acceptance` → `114 passed in 0.20s`) and 20 are existing tests. Acceptance test c33 also runs the existing suite separately, and that passes too.

**What was built**
- **Data model (`models.py`):**
  - `ReservationStatus` and a `Reservation` dataclass with the fields the spec names.
  - A small `IdempotentRequest` record that stores what a key was first used for (warehouse and requested items).
- **Errors (`errors.py`):** the four new errors, all subclasses of `InventoryError`.
- **Storage (`repository.py`):** reservations with ids like `RSV-0001`, plus a map of idempotency keys that is never cleared.
- **Service (`service.py`):**
  - The constructor takes an optional `hold_ttl`, defaulting to 20 minutes. Three-argument calls behave as before.
  - New public `held(sku, warehouse)` query. `available` is now on-hand minus allocated minus held, never below zero.
  - `reserve`, `confirm_reservation`, `release_reservation` and `get_reservation` as the spec describes.
- **Expiry:** whether a hold counts is worked out from the injected clock each time it's read. A hold stops counting the moment the clock reaches `expires_at`, with no sweep needed.
- **README:** added the "held" concept and the reservation lifecycle.

**Choices the spec left to me**
- **Criterion 28 (on-hand drops below a hold before confirm):** confirm succeeds. The units were already promised to that cart. The codebase already lets `adjust` push on-hand below allocated, and the shortage is caught at `ship_order`, so a hold turning into an order follows the same rule. If you'd rather confirm raise `InsufficientStock` in this case, it's a small change.
- **Empty `items` or an empty idempotency key:** both raise the existing `InvalidOrder`, with messages specific to reservations.
- **Stock report:** I added the public `held()` query but didn't add a held column to `stock_report`, so the report's columns are unchanged.

Nothing is committed. The changes are in the working tree alongside the untracked `SPEC.md` and `tests/acceptance/`.

### [review1] operator

Review the changes since commit 910b87b87468e02f9ec8acedf2837075f641f1a9 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md, so there is nothing to fix.

I read the diff from 910b87b, which covers the committed and uncommitted changes in `models.py`, `errors.py`, `repository.py`, `service.py` and `__init__.py`. I checked it against all 33 acceptance criteria. The full test suite passes: 134 tests, including the existing tests and `tests/acceptance/`.

The parts most likely to go wrong are handled correctly:

- **Expiry without a sweep:** a hold counts as held only while the clock is before `expires_at` (`models.py:98`), so it stops reducing `available` at exactly `expires_at` with no other call (criteria 5 and 19). `get_reservation` reports a lapsed `ACTIVE` hold as `EXPIRED`, and confirm and release both go through it. That gives `ReservationExpired` on confirm and a no-op returning `EXPIRED` on release (criteria 26 and 31).
- **Validation order in `reserve`:** the key, empty `items`, warehouse, SKUs and quantities are all checked before the idempotency lookup and before anything is held (criteria 11–13). A replay is answered before the stock check, so it returns the original reservation even when stock is gone now. The comparison uses a copy of the requested items, not the held ones (criteria 16 and 17).
- **Rejected requests leave no trace:** when no line can hold anything, `InsufficientStock` is raised before an id is taken, anything is saved or the key is recorded (criterion 9).
- **Holds block other takers:** `place_order` and `reserve` both go through `available()`, which now subtracts held units, so neither can take them (criterion 4). `stock_report` also picks this up.
- **Confirm hands over cleanly:** held units become allocated in one step, so `available` is the same before and after (criterion 23). It doesn't re-check on-hand stock, so it never leaves a half-done state (criterion 28). Confirming again returns the stored order whatever state that order is in (criterion 25).
- **Compatibility:** the hold duration is an optional fourth argument defaulting to 20 minutes, so three-argument calls behave as before.

FINDINGS: 0
