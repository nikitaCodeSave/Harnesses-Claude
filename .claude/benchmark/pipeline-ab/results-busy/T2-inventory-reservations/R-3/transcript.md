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

I've read the package (`service.py`, `models.py`, `errors.py`, `reports.py`, tests). Some things are already settled by the code, so I'll treat them as given unless you object: reserve is all-or-nothing like `place_order`, the same validation errors get reused (`UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, `InsufficientStock`, `InvalidOrder` for empty items), and confirming produces a normal `PLACED` order with the usual `ORD-` id.

These are the business rules I need from you. Each has my recommendation, so "agree" is a fine answer.

**Expiry**
1. **How long does a hold last?** `reserve` has no TTL parameter, so it has to be a service-wide setting. My suggestion is 15 minutes by default, with an optional constructor keyword so the existing three-argument constructor still works. Is that right, and what value do you want?
2. **What happens exactly at `expires_at`?** I suggest the hold counts as expired at that instant (`now >= expires_at`), not one tick later.

**Idempotency**
3. **Retry with the same key and the same request** (same warehouse and items): return the original reservation unchanged, even if it has since been confirmed, released or expired. It would not create a new hold. Agree? The alternative is "if the original is dead, make a new one".
4. **Same key with a different warehouse or different items:** raise `IdempotencyConflict`. Item order doesn't matter (`{"A":1,"B":2}` matches `{"B":2,"A":1}`).
5. **A reserve that fails** (for example `InsufficientStock`): it doesn't use up the key, so a later retry with that key can succeed. Agree?
6. **Key scope and lifetime:** keys are global across warehouses and are remembered forever (no key expiry). Should an empty-string key be rejected? I suggest yes, but tell me which error you want.

**Confirm / release transitions**
7. **Confirming an expired hold:** raise `ReservationExpired`. Confirming a released hold: raise `InvalidReservationState`.
8. **Confirming twice:** should the second call return the same order (idempotent) or raise `InvalidReservationState`? I lean toward returning the same order, because the cart service retries.
9. **Release:**
   - Releasing a confirmed hold raises `InvalidReservationState`.
   - Releasing an already-released hold returns it unchanged (idempotent).
   - Releasing an expired hold: return it as `EXPIRED`, raise `ReservationExpired`, or something else?
10. **Unknown id:** `confirm`, `release` and `get_reservation` all raise `ReservationNotFound`.

**Stock interaction**
11. **Do holds block other orders?** I suggest held units come out of `available`, so plain `place_order` calls and other reservations can't take them. The rule becomes `available = on_hand − allocated − held by active holds`, floored at 0. Expired holds stop counting the moment they expire.
12. **`allocated()` and the stock report:** I suggest `allocated()` keeps meaning "promised to `PLACED` orders" and doesn't include holds. The report's `available` column reflects holds automatically, and I'd add no "held" column. Adding one would change `StockRow`, and today's tests build it positionally. OK?
13. **Stock written off while a hold is active:** `adjust` lets on-hand drop below what's promised. Say a hold covers 5 MUG and a write-off leaves 3 on hand. When the cart confirms, should it:
    - (a) succeed anyway, because the hold was a promise, or
    - (b) fail with `InsufficientStock` and leave the hold active?

    Separately, should `adjust` itself be blocked from eating into held stock? I suggest (a) and no new block on `adjust`, since that matches how orders behave today.

**Scope**
14. These would be non-goals unless you say otherwise:
    - extending or renewing a hold
    - confirming or releasing only part of a hold
    - changing the items on a hold
    - listing reservations
    - showing holds in the report
    - persistence beyond the in-memory repository
    - concurrency or locking

    Anything here you actually need?
15. **Reservation id format:** I suggest `RES-0001`, sequential like orders. Do you care?

### [spec] user

Preamble correction: reserve is NOT all-or-nothing. Each line holds as many units as are available now, up to what was asked; lines with nothing available are left out of `items` entirely (not even 0). Only if no line can hold anything does reserve fail with InsufficientStock, and then nothing is created. This is for reservations only; place_order stays all-or-nothing. Validation as you listed (reject = hold nothing, even for valid lines). Confirm creates a normal PLACED order for exactly the units held.

1. 20 minutes, not 15. Optional constructor keyword is fine as long as the default is 20.
2. Agree: expired from expires_at on, that instant included.
3. Agree: return the existing reservation in its current state, no new hold, expires_at not moved. 'Same request' = same warehouse and same *requested* items (not what ended up held).
4. Agree, even if the original reservation is finished.
5. Agree: a failed reserve leaves no trace.
6. Agree on global keys, no key expiry. Empty key: any InventoryError is fine.
7. Agree.
8. Return the same order, create nothing, at any time, even after the 20 minutes have passed.
9. Agree on the first two. Releasing an expired hold is a no-op: return it unchanged as EXPIRED, no error.
10. Agree.
11. Agree.
12. Agree; no held column. Whether the report shows held units is up to you.
13. Either (a) or (b) is fine for confirm. Don't block adjust or receive; if a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are.
14. All non-goals.
15. Don't mind; RES-0001 is fine.

### [spec] agent

I've written the spec to `SPEC.md`. Your interface is copied in verbatim, followed by 39 numbered, checkable acceptance criteria (R1–R39), a non-goals list, and a short "left unspecified" section. Your answers above are all in it, including the partial-hold rule.

I made three decisions you didn't explicitly answer:
- **Hold-duration setting:** the name isn't fixed. I proposed `hold_duration: timedelta = timedelta(minutes=20)`. The spec marks it as not fixed by you, and your three-argument constructor still works unchanged (R38).
- **Report:** you left showing held units up to me, so I chose not to. `stock_report` keeps its four columns, and its `available` column already accounts for holds (R24).
- **Error precedence:** if a call has a known key, a different request and invalid input all at once, either `IdempotencyConflict` or the validation error is acceptable. It's listed under "left unspecified", alongside your "(a) or (b)" choice for confirming after a write-off (R30).

Tell me if any of those should be pinned down. Otherwise the spec is ready to build from.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote acceptance tests for all 39 criteria, R1–R39, in `tests/acceptance/`. They fail as expected: **90 fail and 3 pass.** I didn't touch any package code.

**Command:**
```
python3 -m pytest tests/acceptance -q --tb=no -p no:cacheprovider
```
**Output (last lines):**
```
FAILED tests/acceptance/test_reserve_validation.py::test_r6_failed_validation_holds_nothing_and_keeps_key_free[WH1-items3-UnknownSku]
FAILED tests/acceptance/test_reserve_validation.py::test_r6_failed_validation_holds_nothing_and_keeps_key_free[NOPE-items4-UnknownWarehouse]
FAILED tests/acceptance/test_reserve_validation.py::test_r6_empty_items_holds_nothing_and_keeps_key_free
90 failed, 3 passed in 0.17s
```
The existing suite still passes on its own: `python3 -m pytest tests --ignore=tests/acceptance -q` gives `20 passed`.

**Why they fail.** I grouped the errors from a full run, and every failure is a missing piece of the spec's interface, not a mistake in a test:
- `InventoryService` has no `reserve` method (82 failures).
- The four new error classes are missing from `inventory.errors` (7).
- The `hold_duration` keyword is not accepted (1).

I import the new names through their modules inside each test. That way a missing name fails one test, not the whole file at collection.

**Why 3 pass.** They check things the current code already does:
- **R12, first test:** `place_order` stays all-or-nothing. A second R12 test, which combines it with holds, fails.
- **R37, source scan:** no wall-clock calls in the package. A second R37 test, which checks expiry against a clock set in 2001 or 2150, fails.
- **R39:** runs the existing suite in a subprocess and expects it to pass.

**Files:** `conftest.py` sets up shared stock: MUG 10, TEE 5, CAP 0 in WH1, and nothing in WH2. The tests are split into `test_reserve_validation.py`, `test_reserve_partial.py`, `test_reserve_idempotency.py`, `test_expiry.py`, `test_availability.py`, `test_confirm.py`, `test_release.py`, `test_lookup_errors.py` and `test_compatibility.py`. Each test name starts with the criterion it covers, for example `test_r28_...`.

**Choices you may want to check:**
- **Custom hold duration:** the spec doesn't fix the keyword's name, so `test_r38_hold_duration_is_configurable_by_keyword` uses the proposed `hold_duration`. If you pick a different name, change that one test.
- **R30 allows two outcomes:** the test passes if the confirm succeeds as in R25, or if it raises `InsufficientStock`, creates no order and leaves the reservation `ACTIVE`.
- **Interface beyond the service:** to check "no order created" I use `repo.orders()` and `repo.get_order()`, as the existing tests already do. The repository is the constructor's first argument.
- **"Nothing created" checks:** after a failed `reserve`, I check that `get_reservation("RES-0001")` raises `ReservationNotFound`.

Nothing is committed.

### [check] user

One correction: the tests check 'nothing created' with get_reservation("RES-0001"). I don't mind what format reservation ids take, so the tests shouldn't depend on that one. Please make that check work with any id format. The rest is fine.

### [check] agent

The "nothing created" checks no longer depend on the id format. Each one now uses behaviour you can see through the public interface:

- **R6 (validation failure) and R9 (nothing holdable):** I removed the `get_reservation("RES-0001")` check. After the failure the test advances the clock and calls `reserve` again with the same key. That call must return a brand-new `ACTIVE` hold with `expires_at == clock.now() + 20min`. If the failed call had left a record tied to the key, the new call would hit `IdempotencyConflict` or return the old record. The existing checks that `available` is unchanged still catch any units held by mistake.
- **R13 (retry) and R14 (conflict):** I removed the `get_reservation("RES-0002")` checks. The R13 retry test already asserts the same reservation comes back and `available` is unchanged. R14 now also checks that, after the conflict, the key still returns the original reservation unchanged.
- **R35 (unknown id while others exist):** this test used `"RES-0002"` as an id that shouldn't exist, which also assumes the format. It now uses the real id with `"-unknown"` appended.

**Command:**
```
python3 -m pytest tests/acceptance -q --tb=no -p no:cacheprovider
```
**Output:**
```
90 failed, 3 passed in 0.19s
```
The counts and causes are the same as before: every failure is a missing `reserve` method, error class or `hold_duration` keyword. The existing suite still passes (`20 passed`).

**Decision for you:** R11 in SPEC.md still requires ids like `RES-0001`, `RES-0002`, and the two R11 tests in `test_reserve_partial.py` check exactly that. I left them alone because you only asked about the "nothing created" checks. If the format really doesn't matter, R11 should be reworded, and I can cut those tests down to checking that ids are unique.

### [check] user

The id format doesn't matter. Please reword R11 to require only that ids are unique, and cut the two R11 tests down to checking uniqueness.

### [check] agent

I reworded R11 and cut both R11 tests down to uniqueness checks.

**SPEC.md:** R11 now reads:
> R11. Reservation ids are unique. Their format is not specified.

**`tests/acceptance/test_reserve_partial.py`:**
- `test_r11_two_reservations_get_different_ids` checks only that two reservations get different ids. It used to require exactly `RES-0001` and `RES-0002`.
- `test_r11_reservation_ids_are_unique` still checks that six reservations get six distinct ids. I removed its `RES-\d{4}` format check, and the `import re` that only that check used.

**Command:**
```
python3 -m pytest tests/acceptance -q --tb=no -p no:cacheprovider
```
**Output:**
```
90 failed, 3 passed in 0.19s
```
Both R11 tests fail only because `InventoryService` has no `reserve` yet. The existing suite still passes (`20 passed`).

`RES-` now appears only in the R35 lookup test, which passes `"RES-9999"` as an id that doesn't exist. It works with any id format unless an implementation happens to issue that exact id.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

Stock reservations are built as SPEC.md describes, and all tests pass: the 93 acceptance tests and the 20 existing ones. I didn't edit anything under `tests/`.

**Command:**
```
python3 -m pytest -q -p no:cacheprovider tests
```
**Output:**
```
........................................................................ [ 63%]
.........................................                                [100%]
113 passed in 0.15s
```
Run separately, `tests/acceptance` gives `93 passed in 0.14s` and the existing suite (`--ignore tests/acceptance`) gives `20 passed in 0.01s`.

**What changed**
- **`models.py`**: adds the `ReservationStatus` enum (`ACTIVE`, `CONFIRMED`, `RELEASED`, `EXPIRED`) and a `Reservation` dataclass with the fields in the spec. Both are exported from `inventory`.
- **`errors.py`**: adds `ReservationNotFound`, `ReservationExpired`, `InvalidReservationState` and `IdempotencyConflict`, all subclasses of `InventoryError`.
- **`repository.py`**: stores reservations in memory with `RES-0001`-style ids. It also maps each idempotency key to the warehouse and items originally requested, plus the reservation id. A key is only recorded after a reservation is successfully created, so a failed call leaves nothing behind.
- **`service.py`**:
  - **Constructor:** gains a keyword-only `hold_duration=timedelta(minutes=20)`, so the three-argument form still works.
  - **`reserve`:** checks the input first, then the idempotency key. A repeat call with the same warehouse and items returns the existing reservation as it is now; a different request raises `IdempotencyConflict`. Otherwise it holds `min(requested, available)` for each line and leaves out lines with nothing available.
  - **`available`:** now subtracts units held by active reservations.

**Behaviour where I made a choice**
- **Expiry:** an `ACTIVE` reservation is switched to `EXPIRED` the next time anything reads it (`get_reservation`, `available`, `confirm`, `release` or a repeat `reserve`), once `clock.now() >= expires_at`. There is no background job, and the status change is saved.
- **Confirm after a write-off (R30):** I chose outcome (a). Confirming always creates the order for the held items, even if on-hand has fallen below them, so `available` shows 0 in that case.
- **Conflicting key plus invalid input:** the validation error is raised before `IdempotencyConflict`. The spec allows either.

Running the tests created an untracked `src/inventory/__pycache__/`. Nothing is committed.

### [review1] operator

Review the changes since commit 06115b9a251718514c97a1b9da4fa67e8ed6b5d2 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found nothing that needs fixing. The changes meet every acceptance criterion in SPEC.md (R1–R39) that I checked against the code in `src/inventory/service.py`, `repository.py`, `models.py` and `errors.py`. The full test suite passes (113 tests, including the existing suite and `tests/acceptance/`).

- **Validation and leaving no trace (R1–R6, R16):** all validation runs, through `_validate_items`, before anything is changed. The reservation id is only allocated, and the key only bound, after a hold has succeeded.
- **Partial holds (R7–R10):** each line holds `min(requested, available)`, and lines with nothing available are left out. If nothing can be held, it raises `InsufficientStock` without creating anything. `expires_at` is `clock.now() + hold_duration`.
- **Idempotency (R13–R15):** a retry is matched on warehouse and the *requested* items (stored as a copy), not the held ones. It returns the stored reservation after expiry is applied, and a mismatch raises `IdempotencyConflict` even when the original is finished. Keys are global and never expire.
- **Expiry (R17–R19):** expiry is applied when a reservation is next read, by `get_reservation` or by `_held` inside `available`. The comparison is `>=`, so a reservation counts as expired at exactly `expires_at`. Only `ACTIVE` reservations expire.
- **Availability (R20–R24):** `available` is `on_hand − allocated − held`, floored at 0. `allocated` is unchanged, `place_order` and `reserve` both go through `available`, `receive` and `adjust` ignore holds, and `stock_report` picks up the change through `available`.
- **Confirm (R25–R30):** an active hold becomes an `ORD-` order for the held items, with `placed_at` from the clock. Confirming an already confirmed reservation returns the same order. An expired one raises `ReservationExpired`, a released one raises `InvalidReservationState`, and for R30 the code takes option (a), which the spec allows.
- **Release (R31–R34):** releasing an active hold sets it to `RELEASED`. Released and expired reservations come back unchanged, and a confirmed one raises `InvalidReservationState`.
- **Lookup, errors and clock (R35–R38):** an unknown id raises `ReservationNotFound` from the repository. The four new errors subclass `InventoryError`, nothing in the package reads the wall clock, and `hold_duration` is an optional keyword argument defaulting to 20 minutes.

FINDINGS: 0
