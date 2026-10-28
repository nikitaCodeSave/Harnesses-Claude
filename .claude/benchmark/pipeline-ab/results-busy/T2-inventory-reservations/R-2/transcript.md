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

I've read the package (service, models, errors, repository, reports, tests). A few things in the code affect the questions:
- `available = on_hand − allocated`, floored at 0. `allocated` only counts PLACED orders.
- `adjust()` checks only physical stock, so a write-off can push on-hand below what's already promised.
- `stock_report` shows `on_hand / allocated / available`.

Here's the first round. Each question has my proposed answer. Reply "ok" or just the numbers you want to change.

**Hold lifetime and expiry**
1. **How long does a hold last?** I propose a 15-minute default, set when the service is built, with an optional keyword argument to change it. `InventoryService(repo, ledger, clock)` keeps working unchanged. Is there a real number from checkout?
2. **What happens at the exact second it runs out?** I propose: once the clock reaches `expires_at`, the hold is expired, so `now >= expires_at` counts as expired.
3. **Do retries or reads extend a hold?** I propose no. `expires_at` is fixed when the hold is created, and there's no "extend" operation (non-goal).

**Reserving**
4. **Does `reserve` follow the same rules as `place_order`?** I propose yes. It's all lines or nothing, and it reuses `UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, `InvalidOrder` (for empty items) and `InsufficientStock` for the same cases. Nothing is held if any line fails.
5. **Do holds reduce stock for everyone?** I propose yes. Active holds count against `available` for both new holds and direct `place_order` calls. `allocated()` still counts only orders, so the report's `available` is now `on_hand − allocated − held`. Should the report get a separate "reserved" column, or is that out of scope?

**Idempotency key**
6. **What does a retry with the same key and same request return?** I propose the original reservation, same `reservation_id`, in whatever state it's in now: active, confirmed, released or expired. It never creates a second hold. "Same request" means the same warehouse and the same per-SKU quantities, ignoring key order.
7. **What if the same key comes with a different warehouse or different items?** I propose `IdempotencyConflict`.
8. **Does a failed `reserve` (for example, out of stock) use up the key?** I propose no. Nothing is recorded, so a later retry with that key can succeed.
9. **Where do keys need to be unique?** I propose across the whole service, not per warehouse.

**Confirming**
10. **What does `confirm_reservation` produce?** I propose a normal PLACED `Order` from the reservation's warehouse and items, with an ID from the usual `ORD-` sequence. The reservation becomes CONFIRMED with `order_id` set, and its hold turns into the order's allocation. That shipping, cancelling and reporting then work as they do for any order.
11. **Does confirming re-check stock?** I propose no. The units were already set aside, so confirming an active hold always succeeds, even if a write-off has since reduced on-hand. This matches how existing orders behave after a write-off. Or should confirm fail with `InsufficientStock` in that case?
12. **What if confirm is retried on a reservation that's already CONFIRMED?** I propose it returns the same order (safe to retry), not an error.
13. **What if it's confirmed after expiry?** I propose `ReservationExpired`. Confirming a RELEASED reservation gives `InvalidReservationState`.

**Releasing**
14. **What can be released?** I propose: releasing an active hold makes it RELEASED and frees the stock. Releasing an already RELEASED one returns it unchanged. Releasing a CONFIRMED one gives `InvalidReservationState`, because you cancel the order instead.
15. **What about releasing an EXPIRED hold?** I propose returning it unchanged, still EXPIRED, since its stock is already free. Or would you rather it raise `ReservationExpired`?

**Lookup and IDs**
16. **What does `get_reservation` show for a lapsed hold?** I propose EXPIRED as soon as the clock passes `expires_at`, with no sweep needed. Unknown IDs give `ReservationNotFound`.
17. **What do reservation IDs look like?** I propose `RES-0001`, `RES-0002` and so on, in sequence like orders. Do tests or other services rely on any format?

**Non-goals (proposed):** partial confirm or release, changing a hold's items, extending a hold, holds across several warehouses, and keeping data between runs (storage stays in memory).

### [spec] user

Changes needed on 1, 4 and 11; the rest is fine.

1. The hold lasts 20 minutes, not 15 (checkout data: 95% of payments finish within 18 min). expires_at = creation time + 20 min. An optional keyword argument is fine as long as the default is 20.

2. Fine: now >= expires_at counts as expired.

4. Validation matches place_order, but holding is NOT all-or-nothing. Each line holds as many units as are available right now, up to the quantity asked. A line with nothing available is left out of `items` entirely (not even shown with 0). reserve fails with InsufficientStock only when no line can hold anything, and then nothing is created. Bad input (UnknownWarehouse, UnknownSku, InvalidQuantity) rejects the whole request and holds nothing, even for the valid lines. Partial filling applies to reservations only; place_order stays all-or-nothing.

5. Report column: I don't mind, your call.

11. Confirm turns an ACTIVE hold into a PLACED order for exactly the units held (after a partial hold, only those). If a write-off has pushed on-hand below the hold, succeeding or raising InsufficientStock are both fine with me.

15. Fine: releasing an EXPIRED hold returns it unchanged, no error.

3, 6-10, 12-14, 16, 17: fine as proposed.

### [spec] agent

Thanks. Your change to 4 (partial fill) leaves two things open that I can't settle myself.

**A. Which quantities does a retry compare against?** Say the cart asks for `{"MUG": 5}` and only 3 are held, so `items == {"MUG": 3}`. The retry sends `{"MUG": 5}` again with the same key. I propose comparing against the **original request**, so the retry returns the existing reservation (still 3 held) rather than raising `IdempotencyConflict`. A retry is never filled again, even if more stock has arrived since.

**B. Which error wins when a reused key also has bad input?** Example: key `K` already holds `{"MUG": 2}`, and a new call with `K` sends `{"NOPE": 1}`. I propose that input validation (`UnknownWarehouse` / `UnknownSku` / `InvalidQuantity` / `InvalidOrder`) runs first, so that call raises `UnknownSku`. `IdempotencyConflict` is only for valid requests that differ from the original. The alternative is to check the key first.

I've decided two things myself, so you don't need to answer them:
- **Report:** no new column. `StockRow` stays as it is, because the existing report test compares 4-field rows. Its `available` column now reflects holds.
- **Confirm after a write-off:** confirming an active, unexpired hold always succeeds and allocates exactly the held units. It doesn't raise `InsufficientStock`, which matches how existing orders behave after a write-off.

### [spec] user

A. Your proposal is right. A retry compares against what was originally requested, not what ended up held. With the same key and the same warehouse and requested items, it returns the existing reservation in its current state. It doesn't fill again and doesn't move expires_at.

B. I don't mind which error wins in that case, so validation first is fine.

Your two decisions are fine with me.

### [spec] agent

I've written the spec to `SPEC.md` in the repo root. I haven't committed it, and I haven't started on any code.

It has:
- **Why:** checkout holds stock during payment, unconfirmed holds lapse without a background job, and cart retries are safe. It also explains the 20-minute hold from your checkout data.
- **Interface:** copied word for word from your request, plus the optional hold-lifetime keyword argument that defaults to 20 minutes.
- **Acceptance criteria:** 35 checkable statements grouped by availability, reserve, idempotency, confirm, release, lookup and general.
- **Non-goals:** partial confirm or release, changing items, extending a hold, multiple warehouses, a sweeper, a report column, persistence, and expiring idempotency keys.

Your answers are in it as follows:
- **Partial fill:** each line holds `min(requested, available)`. A line that can hold nothing is left out of `items`. `reserve` raises `InsufficientStock` only when no line can hold anything. Bad input rejects the whole request. `place_order` stays all-or-nothing.
- **Retries:** a retry is matched against the originally requested items. It returns the existing reservation in its current state, without filling again or moving `expires_at`.
- **Error order:** input validation runs before the idempotency-key check.

A few rules were never discussed, but they follow from what you decided:
- A failed `reserve` doesn't use up its key (your answer to 8 covers this).
- Confirming leaves `available` unchanged at that moment, because the held units become the order's allocation.
- Any reservation the service returns shows EXPIRED once the clock reaches its `expires_at`, not only ones fetched with `get_reservation`.

Two of the criteria are my own calls rather than yours:
- **No new report column (criterion 6):** `StockRow` keeps its current shape because the existing report test depends on it.
- **Confirm after a write-off (criterion 21):** confirming an active hold always succeeds and doesn't raise `InsufficientStock`.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote 109 acceptance tests in `tests/acceptance/`, covering all 35 criteria. 107 fail and 2 pass. Every failure is because the feature doesn't exist yet, not because a test is broken. I didn't change any package code.

**Command:**
```
python3 -m pytest tests/acceptance -q -p no:cacheprovider
```

**Output (summary line):**
```
107 failed, 2 passed in 0.35s
```

**Why they fail,** grouped by error:
```
101  AttributeError: 'InventoryService' object has no attribute 'reserve'
  1  AttributeError: module 'inventory.errors' has no attribute 'IdempotencyConflict'
  1  AttributeError: module 'inventory.errors' has no attribute 'InvalidReservationState'
  1  AttributeError: module 'inventory.errors' has no attribute 'ReservationExpired'
  1  AttributeError: module 'inventory.errors' has no attribute 'ReservationNotFound'
  1  AttributeError: module 'inventory.models' has no attribute 'Reservation'
  1  AttributeError: module 'inventory.models' has no attribute 'ReservationStatus'
```

**The 2 that pass** are checks that today's code already meets:
- `test_c34_no_package_code_reads_wall_clock` scans `src/inventory` for wall-clock calls. Criterion 34 also has behavioural tests, with the clock set to 2000 and 2100, and those fail.
- `test_c35_existing_suite_still_passes` runs the original suite in a subprocess.

Running the whole suite (`python3 -m pytest -q`) gives `107 failed, 22 passed`. The 20 original tests still pass.

**Layout:**
- One file per spec section: `test_acc_availability.py` (criteria 1–6), `test_acc_reserve.py` (7–13), `test_acc_idempotency.py` (14–18), `test_acc_confirm.py` (19–25), `test_acc_release.py` (26–29), `test_acc_lookup.py` (30–32), `test_acc_general.py` (33–35 plus the model and enum shapes).
- Each test name starts with its criterion number, e.g. `test_c23_…`.
- The tests only use the public interface the spec names: the service methods, `stock_report`, `models` and `errors`. A few also check the repository's order list to confirm nothing was created.
- The new names are looked up when each test runs rather than imported at the top of the file. So each test fails on its own instead of the whole file failing to load.
- The expected values come from the spec, e.g. a 20-minute hold, `RES-0001` and `ORD-0002`.

**Gaps and choices:**
- **Custom hold lifetime isn't tested.** The spec says the lifetime can be set by an optional keyword on the constructor but doesn't name it. Only the 20-minute default is tested. Once the name is fixed, a test is easy to add.
- **Some ambiguous points are left alone:**
  - whether a failed `reserve` uses up a `RES-` number;
  - which error wins when a request has several validation problems;
  - whether a `Reservation` object you're already holding updates itself as the clock moves.

  For "creates nothing", the tests only check that no reservation can be found and that availability hasn't changed.

The earlier pytest runs also created `tests/__pycache__/`; it's untracked. I haven't committed anything.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

I've added stock reservations as SPEC.md describes, and both the acceptance tests and the existing suite pass.

**Command and output** (from the repo root; `python` isn't installed here, so it's `python3`):

```
$ python3 -m pytest -q -p no:cacheprovider
........................................................................ [ 55%]
.........................................................                [100%]
129 passed in 0.15s
```

That's 109 acceptance tests plus the 20 existing ones; run separately they give `109 passed` and `20 passed`. Nothing under `tests/` was edited.

**How it works**
- **Expiry without a background job:** a hold counts as held only while it is ACTIVE and the injected clock is before `expires_at`. This is checked every time stock is counted, so freed units show up in `available` as soon as the clock passes `expires_at`. When a reservation is returned, an ACTIVE one whose time is up is marked EXPIRED and saved that way.
- **Availability:** a new `held(sku, warehouse)` method counts the units under live holds, and `available` is now `on_hand − allocated − held`, never below zero. `allocated` and the `stock_report` columns are unchanged.
- **Reserve:** the request is checked the same way `place_order` checks it, then the idempotency key is checked, then each line takes as much as is available.
  - Lines that get nothing are left out, and if no line gets anything you get `InsufficientStock` and nothing is created.
  - The original request is saved with the reservation, so a repeat with the same key is compared against what was asked for, not what was held.
  - A key is only recorded when a reservation is actually created, so failed calls don't use it up.
- **Confirm** creates a normal PLACED order from the held items using the usual `ORD-` numbers. It doesn't re-check stock, so it still works after a write-off. Confirming twice returns the same order.
- **Hold length:** set it with the `hold_lifetime=` keyword on the constructor; the default is 20 minutes.

**Files changed:** `models.py` (new `Reservation` and `ReservationStatus`), `errors.py` (the four new errors), `repository.py` (stores reservations and idempotency keys alongside orders), `service.py`, `__init__.py` (exports), and `README.md` (explains held stock and the reservation lifecycle).

**Two choices to review:**
- `Reservation` has two fields the spec doesn't list, `requested` and `idempotency_key`; the replay comparison needs them.
- When nothing at all can be held, `InsufficientStock` names the first requested line and reports 0 available.

Nothing is committed.

### [review1] operator

Review the changes since commit 3e4f99bd88b9ffa71c32d60caf1c4617a5484389 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md, so there is nothing to fix.

I read the full diff since `3e4f99b` and checked it against all 35 acceptance criteria. I also ran the suite: 129 tests pass, covering both the original tests and `tests/acceptance/`.

The criteria most likely to break all hold:

- **Expiry without a sweep (4, 23, 30, 31):** `held()` checks each hold against the clock every time it runs, so freed units show up as soon as the clock passes `expires_at`. Lookups, confirm, release and repeated `reserve` calls mark an overdue hold as `EXPIRED` (`service.py` `_refresh`). The cutoff uses `now >= expires_at`, so confirming exactly at `expires_at` raises `ReservationExpired`.
- **Idempotency (14–18):** Inputs are validated before the key is looked up. Requests are compared against the original request in any key order, not against what ended up held. The key is saved only when a reservation is saved, so failed calls don't record it. They don't use up a `RES-` ID either.
- **Partial fill (8–10):** Each line holds `min(requested, available)`. Lines that hold nothing are left out, and if no line holds anything, `InsufficientStock` is raised before anything is created.
- **Confirm (19–22):** Confirming does no stock check, so it still succeeds after a write-off. The order gets its ID from the normal `ORD-` sequence, and `available` is the same before and after.
- **Release (26–29):** Releasing an expired hold returns it as `EXPIRED`, releasing an already released one is a no-op, and releasing a confirmed one raises `InvalidReservationState`.
- **Clock (34):** No package code reads the wall clock; everything uses the injected clock.

FINDINGS: 0
