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

I've read the package (`service.py`, `models.py`, `errors.py`, `reports.py`, and the tests). These are the business-rule questions the request leaves open. Each has my recommended default, so you can answer "ok" or give your own answer.

**1. Hold lifetime**
- a) How long does a hold last? I suggest **15 minutes** from `reserve`, the same for every reservation. Should the service be able to override it through an optional constructor argument, with the current 3-argument constructor still working?
- b) The boundary: I suggest a hold counts as **expired when `now >= expires_at`**, so at exactly `expires_at` it's already gone.
- c) Can a hold be extended or refreshed (for example, when the cart retries)? I suggest **no**, and listing it as a non-goal.

**2. Idempotency key**
- a) Same key with the same warehouse and items (comparing item contents, not order): I suggest returning the **original reservation in its current state**, whether that's ACTIVE, CONFIRMED, RELEASED or EXPIRED. The retry never creates a second hold, even if the first one has lapsed.
- b) Same key with a different warehouse or items: raise `IdempotencyConflict`.
- c) If a `reserve` fails (unknown SKU, bad quantity, `InsufficientStock`), I suggest the key is **not used up**, so a later retry with the same key can succeed.
- d) Keys are global (not per warehouse) and never expire. An empty key is rejected. Which error should that raise? `InvalidOrder` is the closest existing one.

**3. Reserve rules**
I suggest the same rules as `place_order`: all lines or nothing, checked against `available` (which now subtracts active holds), and the same errors (`UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, `InvalidOrder` for empty items, `InsufficientStock`).

**4. Confirm**
- a) Confirm creates a normal `PLACED` order (with the usual `ORD-` id and `placed_at` set to the confirm time). The held units become allocated. Should it **re-check stock**? Holds can end up exceeding on-hand if someone writes stock off in the meantime. I suggest **no re-check**: payment has already been taken, so the hold is honoured. The existing ship-time check still applies.
- b) Confirming an already CONFIRMED reservation: I suggest **returning the same order** so payment-callback retries are safe, rather than raising.
- c) Confirming an expired hold raises `ReservationExpired`. Confirming a RELEASED one raises `InvalidReservationState`.

**5. Release**
- a) Releasing an already RELEASED reservation: I suggest **returning it unchanged** (no error).
- b) Releasing an EXPIRED one: should it return the reservation still showing **EXPIRED** with no error (my suggestion), or raise `ReservationExpired`?
- c) Releasing a CONFIRMED one raises `InvalidReservationState`. To undo it after that, the caller cancels the order.

**6. After confirm**
If the resulting order is later cancelled or shipped, I suggest the reservation **stays CONFIRMED**. It's a record of what happened, and the order now owns the stock.

**7. Reporting**
Today `allocated` counts only placed orders.
- a) Should holds stay out of `allocated()`?
- b) Should `stock_report` get a separate **`held`** column, so `available = on_hand − allocated − held` still adds up for the back office? I suggest yes to both.

**8. Anything else**
Any rule I haven't asked about? For example: a cap on holds per cart, limits on quantity per hold, or whether you need to look up a reservation by idempotency key.

### [spec] user

1a) No, 20 minutes, not 15. A configurable constructor option is fine as long as the default is 20 and the 3-arg constructor still works. 1b) Agreed: expired when now >= expires_at. 1c) Agreed, no extending. A repeat reserve with the same key must not move expires_at.

2a) Agreed, return the existing reservation in its current state, whatever that is. Compare the requested items, i.e. what was asked for, not what ended up held. 2b) Agreed, IdempotencyConflict, even if the original reservation is finished. 2c) Agreed, a failed reserve leaves no trace and the key can be reused. 2d) Global keys, agreed. For an empty key any InventoryError is fine.

3) Not the same as place_order on one point: reserve is NOT all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of items entirely (not even with 0). Only if no line can hold anything does reserve fail with InsufficientStock, and then nothing is created. Validation is exactly like place_order: UnknownWarehouse, UnknownSku, InvalidQuantity. A rejected request holds nothing, not even for its valid lines. Empty items: any InventoryError. place_order stays all-or-nothing and can only take available stock (on-hand minus placed orders minus active holds, never below 0).

4a) Confirm creates a normal PLACED order in the same warehouse for exactly the units held (after a partial hold, only those). The reservation becomes CONFIRMED with order_id set to that order's id. Available does not change at confirm, and on-hand moves only when the order ships. No re-check: if a write-off pushed on-hand below the hold, either succeeding or InsufficientStock is fine. 4b) Agreed, return the same order and create nothing, at any time, even after 20 minutes. 4c) Agreed on both.

5a) Agreed. 5b) Agreed: return it unchanged, still EXPIRED, no error. Releasing an already RELEASED one is the same. 5c) Agreed, InvalidReservationState.

6) Fine. If the order is later cancelled or shipped, a repeated confirm just must not create a new order.

7) I don't mind about reporting. Do what's sensible, but holds must reduce available as in the rule above.

8) One more point: holds are not stock movements. Reserve, release, expire and confirm never write to the ledger or change on-hand. receive and adjust are never blocked by holds. If a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are. A hold in one warehouse doesn't affect any other. Expired holds free their units again with no sweep call, and expired reservations stay retrievable with status EXPIRED. Only ACTIVE reservations expire. Unknown reservation id on get, confirm or release raises ReservationNotFound. No caps or limits on holds, and no lookup by key is needed.

### [spec] agent

I wrote the spec to `SPEC.md` (it isn't committed). It has 36 checkable acceptance criteria and a non-goals list, and it copies the interface from your request word for word. Your answers are in it as you gave them: 20-minute default hold, partial holds, idempotency compared on what was requested, no re-check at confirm, and holds never touching the ledger.

A few points you left open, where I decided. Tell me if any are wrong:

- **Reporting (criteria 33–34):** `allocated()` still counts only placed orders. `stock_report` rows also show held units, so `available` falling below `on_hand − allocated` is explained.
- **Exports (criterion 35):** `Reservation` and `ReservationStatus` are also importable from the top-level `inventory` package, not just from `inventory.models`.
- **Non-goals:** thread safety and storage beyond the in-memory repository are out of scope, the same as today. An order doesn't record which reservation it came from; only the reservation stores its `order_id`.
- **Not pinned down:** the format of `reservation_id` (only that it's unique), and validation rules for the hold-lifetime constructor setting.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote 106 acceptance tests under `tests/acceptance/`, covering all 36 criteria in SPEC.md. 105 fail, all because the feature isn't built yet. The one that passes is criterion 36 ("all existing tests keep passing"), which is true today.

**Command run:**
```
python3 -m pytest tests/acceptance -q
```
**Output (last line):**
```
105 failed, 1 passed in 0.37s
```
I grouped the failures by cause (`--tb=line`). Every one is a missing piece of the feature, not a broken test:
```
101  AttributeError: 'InventoryService' object has no attribute 'reserve'. Did you mean: 'receive'?
  1  AttributeError: module 'inventory.models' has no attribute 'ReservationStatus'
  1  AttributeError: module 'inventory.models' has no attribute 'Reservation'
  1  AttributeError: module 'inventory.errors' has no attribute 'ReservationNotFound'
  1  AttributeError: module 'inventory' has no attribute 'Reservation'
```
The passing test is `test_36_existing_test_suite_passes`. Running the whole suite with `python3 -m pytest -q` gives `105 failed, 21 passed`: the 20 existing tests plus that one.

**Files:**
- `conftest.py`: one `stocked` fixture (WH1: MUG 10, TEE 5, CAP 0; WH2: MUG 7). It reuses the existing `clock`, `repo`, `ledger` and `service` fixtures.
- `test_acc_interface.py`: the fixed interface, the 3-argument constructor with the 20-minute default, and criterion 35.
- `test_acc_reserve.py`: criteria 1–8.
- `test_acc_idempotency.py`: criteria 9–12.
- `test_acc_expiry.py`: criteria 13–17.
- `test_acc_confirm_release.py`: criteria 18–27.
- `test_acc_stock_interaction.py`: criteria 28–34 and 36.

**How the tests are written:**
- They only call what the spec names: `InventoryService` methods, `inventory.models`, `inventory.errors`, `stock_report`, plus the existing `repo.orders()` and `ledger` to check that no order or ledger entry was created.
- New names are looked up when each test runs, not at import time. That way each test fails on its own instead of the whole file failing to load.
- Expected values come from the spec. Examples: the 20-minute lifetime, a hold counting as expired at exactly `expires_at`, each line holding `min(requested, available)`, and dict equality on the requested items for retries.

**Gaps where the spec doesn't name the interface:**
- **Configurable hold lifetime:** the spec doesn't name the optional constructor argument or its type. I only test the default and the 3-argument constructor. A test for a custom lifetime can be added once the argument is named.
- **Held units in `stock_report` (criterion 34):** the spec doesn't name the new `StockRow` field. The test checks that the four existing fields keep their meaning and that some extra field equals the units held per SKU (and falls back to 0 after expiry).
- **Order id format:** "usual order id sequence" (criteria 18 and 21) is checked against the `ORD-0001…` format the existing tests use.
- **Criterion 20** allows either outcome, so that test accepts a successful confirm or `InsufficientStock`. Either way it checks that the ledger and on-hand are untouched.
- **Criterion 36** runs the existing suite in a subprocess, skipping `tests/acceptance`.

I didn't change any source code.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

Stock reservations are built as SPEC.md describes, and both the acceptance tests and the existing tests pass. I didn't change anything under `tests/`.

**Command** (from the repo root):
```
python3 -m pytest -q -p no:cacheprovider
```
**Output:**
```
........................................................................ [ 57%]
......................................................                   [100%]
126 passed in 0.16s
```
That is 106 acceptance tests plus 20 existing ones. Running `tests/acceptance` alone gives `106 passed in 0.15s`. One acceptance test (criterion 36) also runs the existing suite separately and requires it to pass.

**What changed:**
- **Reservations and errors:** `Reservation` and `ReservationStatus` are in `models.py` and exported from the top-level `inventory` package. The four new errors are in `errors.py`, all subclassing `InventoryError`.
- **Storage:** reservations are stored in the in-memory repository under ids `RES-0001`, `RES-0002`, … It also keeps an idempotency-key table holding the warehouse and the *requested* items, so a retry is compared against what was asked for, not what was held.
- **Service:**
  - `InventoryService` takes an optional `hold_lifetime`, default 20 minutes; the 3-argument constructor still works.
  - It has a new `held(sku, warehouse)` method, and `available` is now `on_hand − allocated − held`, floored at 0.
  - `reserve`, `confirm_reservation`, `release_reservation` and `get_reservation` are added. A reservation is a single hold for one cart.
- **Expiry without a sweep:** whenever a reservation is read, an `ACTIVE` one is switched to `EXPIRED` once `clock.now() >= expires_at`. That covers every query, including `available`.
- **Report:** `StockRow` has a new `held` column. It defaults to 0 because the existing tests build `StockRow` with four arguments.
- **Docs:** the README now describes holds and the reservation lifecycle.

**Choices the spec left open:**
- **Empty idempotency key:** raises the existing `InvalidOrder`, following the spec's instruction to reuse errors where they fit.
- **Confirm after a write-off:** if on-hand has dropped below the held units, confirm still succeeds rather than raising `InsufficientStock`; the spec allows either.
- **Returned reservations are copies,** so a caller editing `items` can't change the stored hold.
- **Expiry is permanent:** a reservation stays `EXPIRED` once it's been seen that way. This is safe because the injected clock never moves backwards.

Nothing is committed yet; the changes are in the working tree.

### [review1] operator

Review the changes since commit 56d1505726aa93a8ed4c6287d4790924b7777c03 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md.

I checked all 36 acceptance criteria against the diff in `service.py`, `repository.py`, `models.py`, `errors.py`, `reports.py` and `__init__.py`. The full suite passes: 126 passed, which includes the existing tests and the files in `tests/acceptance/`.

Specific points I checked:
- **Rejected requests leave nothing behind (2, 12):** input is checked before anything is held, and the reservation id and idempotency key are only recorded after a hold succeeds.
- **Partial holds (3–5):** each line holds what's available, lines with nothing available are left out, and if nothing can be held you get `InsufficientStock`.
- **Idempotency (9–11):** the comparison uses the requested items and the warehouse, not what was actually held. A retry returns the reservation in its current state without changing `expires_at`.
- **Expiry (13–16):** it's checked on every read, and a hold counts as expired at exactly `expires_at`. Only `ACTIVE` reservations expire. Writing the `EXPIRED` status back when it's read is safe because `FixedClock` can't go backwards.
- **Confirm and release (18–26):** the status transitions and errors match the spec. A second confirm returns the same order. The order is built from the held items and uses the normal order id sequence.
- **Stock and orders (28–31, 33):** holds never write to the ledger. `available` subtracts holds and never goes below 0. `receive` and `adjust` aren't blocked by holds, and `allocated` still counts only `PLACED` orders.
- **Report and exports (34–35):** `StockRow` gains a `held` field, and `Reservation` and `ReservationStatus` are exported from the top-level `inventory` package.
- **Constructor:** it still works with three arguments, and the hold lifetime defaults to 20 minutes.

FINDINGS: 0
