### [build] operator

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

### [build] agent

I've read the package (service, models, errors, repository, ledger, clock, reports, tests). There's no `GLOSSARY.md`, `docs/adr/` or `specs/` yet, so I'll create them. This fits in one session. Per CLAUDE.md, I'll ask you about the rules before I write the spec. Each question has my suggested answer, so "defaults ok" or a list of changes is enough.

**Hold lifetime**
1. **How long a hold lasts:** 15 minutes from `reserve`. It's fixed per service through a new optional constructor argument, `InventoryService(repo, ledger, clock, reservation_ttl=timedelta(minutes=15))`, so existing calls keep working. `reserve` has no per-call duration.
2. **When it lapses:** at `now >= expires_at`. At exactly `expires_at` the hold is already expired and its stock is free.
3. **No sweep job:** status is worked out whenever a reservation is read or used. `get_reservation` on a lapsed hold returns `EXPIRED`, and `available` ignores it.

**Reserve**
4. **Stock rules:** the same as `place_order`. All lines or nothing, checked against `on_hand − allocated − other active holds`. Not enough stock raises `InsufficientStock`. Empty items raise `InvalidOrder`. A bad quantity, SKU or warehouse raises the existing errors.
5. **Idempotency key scope:** global, not per warehouse, and kept forever (memory only).
   - Same key, same warehouse and items: return the original reservation **as it is now**. If it has since expired, been released or been confirmed, you get that back; no new hold is made. A new attempt by the cart needs a new key.
   - Same key, different warehouse or items: `IdempotencyConflict`.
   - A `reserve` that fails (for example `InsufficientStock`) does **not** use up the key, so a retry after restock can succeed.

**Confirm**
6. **Active hold:** it becomes a normal `PLACED` order (`ORD-nnnn`, `placed_at = now`), which can be shipped or cancelled as today. The reservation becomes `CONFIRMED` with `order_id` set. Stock is **not** checked again, because the hold was the promise. This matches the fact that `adjust` doesn't check allocations today.
7. **Expired hold:** `ReservationExpired`.
8. **Already `CONFIRMED`:** return the same order again, so retries are safe. (The alternative is `InvalidReservationState`.)
9. **`RELEASED`:** `InvalidReservationState`.

**Release**
10. **Active hold:** becomes `RELEASED` and its stock is free again.
11. **Already `RELEASED`:** returned unchanged, so retries are safe.
12. **`EXPIRED`:** returned unchanged with status `EXPIRED`, no error, since the stock is already free. (The alternative is `ReservationExpired`.)
13. **`CONFIRMED`:** `InvalidReservationState`. To undo it, cancel the order.

**Queries and reports**
14. **Unknown ID:** `get_reservation`, `confirm_reservation` and `release_reservation` raise `ReservationNotFound`. Reservation IDs look like `RES-0001`.
15. **`allocated()`:** stays as it is, counting placed orders only. I'd add a `held(sku, warehouse)` query, so that `available = max(0, on_hand − allocated − held)`.
16. **Stock report:** add a `held` column to `StockRow` so each row still adds up. It would go last with a default of 0, so building it positionally still works. Or leave reports out of scope?

Once you answer, I'll write `specs/stock-reservations.md`. It will copy your interface word for word and include ADRs for lazy expiry and the idempotency-key rules, plus glossary entries. Then I'll build it.

### [build] user

Going through your numbers; where I don't mention one, defaults are fine.

1. Change to 20 minutes, measured from creation: expires_at = creation time + 20 min. A configurable TTL is fine as long as the default is 20 min.
2. OK.
3. OK.
4. Two changes. Reserve is NOT all-or-nothing: each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of `items` entirely (not even with 0). Only when no line can hold anything does reserve fail with InsufficientStock, and then nothing is created. Bad input is validated like place_order: unknown warehouse -> UnknownWarehouse, unknown SKU -> UnknownSku, zero/negative quantity -> InvalidQuantity; a rejected request holds nothing, not even for its valid lines. Empty items: any InventoryError is fine.
5. OK on all three, with one clarification: 'same request' means same warehouse and same *requested* items (what was asked for, not what ended up held). Conflict applies even if the original reservation is finished.
6. OK. The order is for exactly the units held (after a partial hold, only those). Available doesn't change at confirm; on-hand moves only when the order ships.
7. OK, including a hold that has just lapsed.
8. Yes, return the same order; it must work at any time, even after the 20 minutes have passed, and create nothing new.
9. OK.
10. OK.
11. OK.
12. OK.
13. OK.
14. OK; id format doesn't matter.
15. OK. Available = on-hand - allocated to PLACED orders - held by ACTIVE reservations, per SKU per warehouse, never below 0. A hold in one warehouse doesn't touch other warehouses.
16. Don't mind, do what you think is sensible.

Also: reserve, release, expire and confirm never write to the ledger or change on-hand. place_order can only take available stock and stays all-or-nothing. receive and adjust are never blocked by holds; if a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are.

### [build] agent

Stock reservations are built to your rules, and the full suite passes:

```
$ python3 -m pytest -q
............................................................             [100%]
60 passed in 0.02s
exit=0
```

**What's in the change**
- **Spec:** `specs/stock-reservations.md` has what and why, your interface copied word for word, the rules, 21 acceptance checks, non-goals and scope limits.
- **Decision records:**
  - `docs/adr/0001`: holds lapse lazily, with no sweep job.
  - `docs/adr/0002`: idempotency keys are global and kept forever. They match on warehouse plus the *requested* items, and a failed `reserve` doesn't use up the key.
  - `docs/adr/0003`: holds can be partial, while `place_order` stays all-or-nothing.
- **Glossary and README:** `GLOSSARY.md` is new; the README now covers held units and the reservation lifecycle.
- **Code:**
  - `Reservation` and `ReservationStatus` are in `models.py`, and the four new errors are in `errors.py`.
  - The repository stores reservations and the idempotency-key records.
  - The constructor takes an optional `reservation_ttl`, defaulting to 20 minutes, so `InventoryService(repo, ledger, clock)` still works.
  - New query `held(sku, warehouse)`; `available` = on-hand − allocated − held, never below 0.
  - Expiry: whenever a reservation is read or used, an `ACTIVE` one at or past `expires_at` is switched to `EXPIRED`. That's how expiry works without a background job.
- **Additions beyond your interface:**
  - `held()` is a new public query.
  - `StockRow` gets a `held` column, added last with a default of 0, so the existing report test still works without edits.
- **Tests:** `tests/test_reservations.py` has 39 tests, written from the acceptance checks before the implementation; I watched them fail first. I also added one report test.

**Review:** `/code-review` (medium) returned 8 findings, which it didn't double-check.
- **Fixed:** a retry with an existing key skipped input validation, so `{"MUG": True}` came back as the original reservation instead of raising `InvalidQuantity`. I added a test that failed first, then fixed it by validating before the key lookup.
- **Left as is:**
  - The reservation returned to callers is the stored object itself, so changing its `items` would change what's actually held. Orders are already returned the same way.
  - When nothing can be held, `InsufficientStock` names only the first line.
  - Each line and each report row rescans all orders and reservations. That's fine in memory, but slow at scale.

**Still to do:**
- **Fresh-session review:** this touches stock invariants, so CLAUDE.md calls for a fresh session to review it against the spec. I haven't started one.
- **Nothing committed:** you didn't ask me to commit.
- **`__pycache__/` folders:** the test run created them and they show as untracked, because the repo has no `.gitignore`.
