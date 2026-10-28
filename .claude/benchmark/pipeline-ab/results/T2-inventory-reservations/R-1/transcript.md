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

I've read the package. A few things in the existing code shape my questions:

- `available = on_hand − allocated`, where allocated means PLACED orders. `adjust()` only stops on-hand from going below zero, so a write-off can already leave allocations bigger than on-hand.
- `stock_report` returns `StockRow(sku, on_hand, allocated, available)` with positional fields, and an existing test builds rows that way.
- Order IDs are sequential (`ORD-0001`), and `place_order` is all-or-nothing.

Here are my questions. Each has a suggested answer, so you can reply "yes to all except N" if that's easier.

**Expiry**
1. **Hold duration.** How long until an unconfirmed hold lapses? I suggest 15 minutes from `reserve`, as a default that can be changed through an optional constructor argument. The existing `InventoryService(repository, ledger, clock)` call keeps working.
2. **Boundary.** At exactly `expires_at`, is the hold already expired? I suggest yes: it's active only while `now < expires_at`.
3. **Extending.** Can a hold be extended or refreshed, for example by calling `reserve` again? I suggest no, and listing that as a non-goal.

**Confirm / release**
4. **Confirm.** This creates a normal PLACED order (new `ORD-` id, `placed_at` = time of confirm) with exactly the held lines, sets the reservation to CONFIRMED, and records the `order_id`. Should confirm check stock again? A write-off after the hold might have reduced on-hand. I suggest no: the hold is a promise and simply becomes an allocation, which matches how `adjust` already treats allocations.
5. **Confirming twice.** A second `confirm_reservation` on a CONFIRMED reservation: return the same Order (safe for retries) or raise `InvalidReservationState`? I suggest returning the same Order, since checkout retries too.
6. **Confirming a lapsed hold** raises `ReservationExpired`. **Confirming a RELEASED hold** raises `InvalidReservationState`. Agreed?
7. **Release.** ACTIVE becomes RELEASED and the stock is freed. What should these do?
   - Release when already RELEASED: I suggest a no-op that returns the reservation.
   - Release when EXPIRED: I suggest a no-op that returns it, still EXPIRED, because the stock is already free.
   - Release when CONFIRMED: I suggest `InvalidReservationState`. Releasing never cancels the order; that's what `cancel_order` is for.

**Idempotency**
8. **Same key, same request** (same warehouse and the same items in any order) returns the original reservation in its current status, even if it has since expired, been released or been confirmed. There's no new hold. Same key with a different warehouse or items raises `IdempotencyConflict`. Is that right? Specifically, should a retry after expiry return the expired reservation rather than make a fresh hold? I suggest returning the expired one; the cart should use a new key for a new attempt.
9. **Failed attempts.** If `reserve` fails (`InsufficientStock`, unknown SKU, and so on), nothing is recorded under the key, so a later retry with the same key can succeed. Agreed?
10. **Key scope and lifetime.** I suggest keys are global, not per warehouse, and remembered forever, since nothing is persisted beyond memory anyway. An empty key is rejected; which error should it raise?

**Availability and reporting**
11. **Validation.** Reserve is all-or-nothing and uses the same checks as `place_order`: unknown warehouse or SKU, non-positive quantity, empty items (`InvalidOrder`), and `InsufficientStock` against available, which already subtracts active holds.
12. **Reporting.** Should `allocated()` include active holds? I suggest no: allocated stays "PLACED orders", and only `available` subtracts holds. In that case, should `StockRow` get a `held` column? Adding one changes the row's shape, which affects existing callers and the current report test. I suggest leaving the report as it is (its `available` will reflect holds) and listing a `held` column as a non-goal. Or would you like it added?
13. **IDs.** Reservation IDs are sequential, `RES-0001`, like orders. Is that fine?

### [spec] user

Yes to all except 1 and 11, plus some detail on 8 and 10.

1. Make it 20 minutes, not 15 (our checkout data: 95% of payments finish within 18 min). expires_at = creation + 20 min. Configurable default is fine.
2. Yes: at exactly expires_at it's already expired, and the units are available again with no sweep.
3. No extending. A repeat reserve with the same key must not move expires_at.
4. Agreed, no re-check. The hold simply becomes the order's allocation, so available doesn't change at confirm; on-hand moves only when the order ships. After a partial hold, the order covers only the units actually held.
5. Return the same Order and create nothing, even after the 20 minutes have passed.
6. Agreed.
7. Agreed on all three.
8. Yes, return the original in whatever state it's in now, including expired. The 'same request' check compares the items that were requested, not the items that ended up held. A different warehouse or different items raises IdempotencyConflict, even if the original reservation is finished.
9. Agreed; a failed reserve leaves no trace, so the key can be reused.
10. Global across all warehouses, yes. An empty key can raise any InventoryError.
11. Reserve is NOT all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of items entirely (not even shown with 0). Only if no line can hold anything does reserve fail with InsufficientStock, and then nothing is created. Validation matches place_order: UnknownWarehouse, UnknownSku, InvalidQuantity for zero or negative. A rejected request holds nothing, not even for its valid lines. Empty items can raise any InventoryError. place_order stays all-or-nothing and can only take available stock.
12. Keep allocated as PLACED orders only. Available = on-hand − PLACED allocations − active holds, per SKU per warehouse, never below 0; a hold in one warehouse doesn't touch another. I don't mind about the report, so leave it as is with no held column. Holds never write to the ledger or change on-hand. receive and adjust are never blocked by holds; if a write-off leaves on-hand below what's held, available shows 0 and the reservations stay as they are.
13. Sequential RES-0001 is fine. An unknown reservation id raises ReservationNotFound on get, confirm and release.

### [spec] agent

I've written the spec to `SPEC.md`. It contains your interface copied word for word, 33 acceptance criteria grouped by operation (reserve, idempotency, availability, confirm, release, lookup, compatibility), and a list of non-goals. I haven't written any code yet.

I filled in three small points you didn't answer directly. Please check them:

- **Order follow-up (non-goals):** cancelling or shipping an order created from a reservation doesn't change the reservation. It stays `CONFIRMED`.
- **Non-integer quantities (criterion 7):** these raise `InvalidQuantity`, the same as zero or negative ones. `place_order` already rejects them this way, so this keeps the two consistent.
- **Which error wins (criterion 14):** if a retry reuses a key with a different request that is also invalid, the spec says nothing is created but doesn't say whether `IdempotencyConflict` or the validation error is raised. Tell me if you want one of them to take priority.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote 102 failing tests under `tests/acceptance/`, covering all 33 acceptance criteria. I didn't change any source code.

**Commands and output:**

```
$ python3 -m pytest tests/acceptance -q --tb=no
102 failed, 1 passed in 0.08s

$ python3 -m pytest -q --tb=no          # full suite
102 failed, 21 passed in 0.09s          # the 20 existing tests still pass, plus 1 new one
```

Every failure is because the feature doesn't exist yet:

| Count | Reason |
|---|---|
| 93 | `AttributeError: 'InventoryService' object has no attribute 'reserve'` |
| 4 | `module 'inventory.errors' has no attribute 'ReservationNotFound'` |
| 5 | one each: `Reservation`, `ReservationStatus`, `ReservationExpired`, `InvalidReservationState`, `IdempotencyConflict` are missing |

The one passing test, `test_ac33_stock_row_keeps_its_four_columns`, checks that `StockRow` keeps its current four columns. That already holds today, and the test is there to catch it breaking.

**Layout:** one file per spec section (`test_reserve.py`, `test_idempotency.py`, `test_availability.py`, `test_confirm.py`, `test_release.py`, `test_lookup.py`, `test_compatibility.py`), plus `test_interface.py` for the new model and error names. Each test name starts with its criterion number (`test_ac19_…`). The tests reuse the existing fixtures in `tests/conftest.py`, and a small `stocked` fixture sets the starting stock. New names are looked up when each test runs, not imported at the top of the file. That way each test fails separately instead of the whole file failing to load.

**Gaps and judgement calls:**
- **Criterion 2, configurable hold length:** I only tested the 20-minute default and the three-argument constructor. The spec doesn't say how the length is configured, so testing that would mean guessing at an interface it doesn't name.
- **`True` as a quantity is rejected** with `InvalidQuantity`. The spec doesn't list it, but criterion 7 says validation must match `place_order`, which rejects it.
- **The order created by confirm is in the reservation's warehouse.** The spec implies this rather than stating it.
- **Reservation IDs after a failed reserve:** I didn't test whether a failed call uses up an ID, because the spec doesn't say. The tests only check that no reservation exists afterwards.
- **Not checked against a working implementation:** every test currently fails on the missing method or name. That proves they fail now, but not that each check would catch a wrong implementation. That will show once the feature is built.

The rest of criterion 33 ("existing behaviour and tests unchanged") is covered by the existing tests, which must keep passing without edits.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

Stock reservations are built as SPEC.md describes, and both `tests/acceptance/` and the existing suite pass. I didn't modify anything under `tests/`.

**Command and output** (`testpaths = ["tests"]` in `pyproject.toml`, so this runs both suites):
```
$ python3 -m pytest -q
........................................................................ [ 58%]
...................................................                      [100%]
123 passed in 0.05s
```

**What changed**
- **`models.py`**: added `Reservation` and `ReservationStatus`. Also added a small `IdempotencyRecord`, which remembers the requested items, warehouse and reservation id for each key.
- **`errors.py`**: added `ReservationNotFound`, `ReservationExpired`, `InvalidReservationState` and `IdempotencyConflict`, all subclasses of `InventoryError`.
- **`repository.py`**: reservations (with `RES-0001`-style ids) and idempotency records are stored in the existing in-memory repository.
- **`service.py`**:
  - **Expiry without a sweep:** a hold only counts against `available` while the reservation is `ACTIVE` and `clock.now() < expires_at`. When a lapsed reservation is read, its stored status changes to `EXPIRED`.
  - **Constructor:** it takes an optional fourth argument, `hold_duration`, which defaults to 20 minutes. The three-argument form works as before.
  - **Reserve order:** it checks the key, then validates the items exactly as `place_order` does, then checks idempotency, then computes the partial holds. Records are written only after all of that succeeds, so a failed call leaves no trace under its key.
  - **Confirm:** it turns the held quantities into a `PLACED` order with the next `ORD-` id and does not re-check stock.
- **`README.md`** and **`__init__.py`**: documented the held quantity and the reservation lifecycle, and exported the new models.

**Decisions where the spec left room**
- An empty idempotency key raises the existing `InvalidOrder`, the same error `place_order` uses for empty `items`. The spec only says "an `InventoryError`".
- Validation runs before the idempotency lookup. So a request that reuses a known key but is itself invalid (for example, an unknown SKU) raises the validation error, not `IdempotencyConflict`. Nothing is created either way.

Nothing has been committed. The working tree contains the six modified files, plus untracked `__pycache__` directories left over from the test runs.

### [review1] operator

Review the changes since commit af4184f07618cc399566a8479538adc761ec05ff (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md.

I checked the committed and uncommitted changes since `af4184f` against all 33 acceptance criteria, and the full test suite passes (123 tests). The points most likely to go wrong are handled correctly:

- **Lazy expiry (criteria 19, 25, 29, 31):** A hold stops counting once `clock.now() >= expires_at`, including the exact moment of expiry (`service.py:227`). Holds are only counted while `ACTIVE` and not lapsed (`service.py:229-234`), so nothing needs to sweep them. `get_reservation` reports a lapsed hold as `EXPIRED`, and confirm and release both use it, so a confirm at exactly `expires_at` raises `ReservationExpired`.
- **Idempotency (criteria 11–15):** Keys are global. A retry is compared on warehouse and the requested items, not what ended up held, and item order doesn't matter. A failed reserve saves nothing under its key and doesn't use up a reservation ID (`service.py:154-181`).
- **Reserve:** Each line holds what it can, and lines with nothing available are left out. If no line can hold anything, it raises `InsufficientStock` without creating anything. All validation runs before any hold is made, and holds never write to the ledger.
- **Confirm (criteria 21–24):** It doesn't re-check stock, and the order uses exactly the held quantities. The hold turns into the order's allocation, so `available` doesn't change. Confirming an already `CONFIRMED` reservation returns the same order, even after `expires_at`.
- **Compatibility:** The three-argument constructor still works, since the hold length is an optional fourth argument defaulting to 20 minutes. `on_hand` and `allocated` ignore holds, `place_order` is still all-or-nothing against `available`, and `stock_report` keeps its four columns.

One behaviour the spec doesn't settle: a retry that reuses a known key with an invalid item (say an unknown SKU) gets the validation error, not `IdempotencyConflict`, because validation runs first. That fits criterion 7, so I haven't counted it as a gap.

FINDINGS: 0
