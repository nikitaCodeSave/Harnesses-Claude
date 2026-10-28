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

I've read the whole package. There's no `GLOSSARY.md`, no `docs/adr/`, and no `specs/` yet, so I'll create them. Before I write the spec I need your call on these business rules. Each one has my recommended default, so you can just reply "defaults ok" or override by number.

**Expiry**
1. **Hold length (TTL).** What should it be, and should it be configurable? *Recommended:* 15 minutes by default, with an optional keyword on the constructor (`InventoryService(repo, ledger, clock, reservation_ttl=timedelta(...))`). The existing three-argument call keeps working.
2. **Boundary.** A hold counts as expired once `clock.now() >= expires_at`. At exactly `expires_at` it no longer holds stock. *OK?*
3. **Reading an expired hold.** When a hold has lapsed but is still stored as `ACTIVE`, `get_reservation` reports it as `EXPIRED`. *Recommended:* yes, and stored state is updated to match.

**Confirm**
4. **Confirm after expiry** raises `ReservationExpired`, even if the stock happens to still be free. *OK?*
5. **What confirm creates.** Confirm makes a normal `PLACED` order through the existing order path: `placed_at` is the time of confirmation, the hold turns into an allocation, and the reservation becomes `CONFIRMED` with its `order_id` set. It does **not** re-check stock: the hold was the promise. If a write-off happened in the meantime, that shows up at `ship_order` time, the same as for orders today. *OK, or should confirm re-check and raise `InsufficientStock`?*
6. **Confirming twice.** *Recommended:* return the same `Order` again, with no second order created, since retries are the point. The alternative is `InvalidReservationState`.

**Release**
7. **Release from each state.**
   - `ACTIVE`: becomes `RELEASED`.
   - `RELEASED`: returns it unchanged (idempotent).
   - `CONFIRMED`: raises `InvalidReservationState`.
   - `EXPIRED`: *recommended* returns it unchanged with status `EXPIRED`, because the stock is already free and there's nothing for the caller to do. The alternative is raising `ReservationExpired`.

**Idempotency**
8. **Same key, same request.** The same key with the same warehouse and items returns the **original** reservation in whatever state it's in now: active, confirmed, released or expired. It doesn't create a new hold or extend the expiry. *OK? Or should a retry after the original expired or was released create a fresh hold?*
9. **Same key, different request.** A different warehouse or different items raises `IdempotencyConflict`. Keys are global, not per warehouse, and are remembered for as long as the repository lives.
10. **Failed attempts.** A `reserve` that fails (`InsufficientStock`, bad input) does not use up the key, so a retry is evaluated fresh.

**Validation, stock and reporting**
11. **Validation.** `reserve` validates exactly like `place_order`: `UnknownWarehouse`/`UnknownSku`, `InvalidQuantity`, `InvalidOrder` for empty items, and `InsufficientStock` with all-or-nothing behaviour.
12. **Available stock.** `available = on_hand − allocated − held`, floored at 0, where *held* means units in active, unexpired holds. `place_order` therefore can't take held stock. `allocated()` stays "PLACED orders only".
13. **Stock report.** Should `stock_report` gain a `held` column? *Recommended:* add it as a non-goal for now. Changing the positional `StockRow` would break existing callers, and today the report's `available` already reflects holds.
14. **Ids.** Reservation ids are sequential `RES-0001`, `RES-0002`, … like orders.

### [build] user

1. Override: TTL is 20 minutes from creation (expires_at = creation + 20 min). A configurable kwarg is fine if the default is 20 min.
2. OK: from expires_at on, that instant included, the hold is expired and units are available again.
3. OK. Expired holds stay retrievable with status EXPIRED. Only ACTIVE holds expire; CONFIRMED and RELEASED never change on their own.
4. OK: confirm of an expired hold (even one that just lapsed) raises ReservationExpired.
5. OK: ordinary PLACED order in the same warehouse for exactly the units held (after a partial hold, only those). Available doesn't change at confirm; on-hand moves only on ship.
6. Return the same order, create nothing new - at any time, even after the 20 minutes have passed.
7. OK on all. Release of EXPIRED is a no-op returning it unchanged; release of CONFIRMED -> InvalidReservationState. Also confirm of a RELEASED one -> InvalidReservationState.
8. OK: return the existing reservation in its current state, no new hold, expires_at unchanged. 'Same request' is compared on the *requested* items (what was asked), not what ended up held.
9. OK, and that applies even if the original reservation is finished.
10. OK.
11. Override: reserve is NOT all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of `items` entirely (not even with 0). InsufficientStock only when no line can hold anything, and then nothing is created. Bad input (unknown warehouse/SKU, zero/negative qty) rejects the whole request and holds nothing, even for valid lines. Empty items: any InventoryError is fine. place_order stays all-or-nothing.
12. Mostly OK: available = on-hand - units allocated to PLACED orders - units held by ACTIVE reservations, per SKU per warehouse, floored at 0; a hold in one warehouse doesn't touch others. Holds never write to the ledger or change on-hand; receive and adjust are never blocked by holds. If a write-off leaves on-hand below what's held, available shows 0 and the reservations stay as they are.
13. Fine, skip it - I don't mind how the report treats held units.
14. Fine, I don't care about id format.

### [build] agent

Reservations are built as specified, and the full test suite passes:

```
$ python3 -m pytest -q
................................................................         [100%]
64 passed in 0.04s
```

**What I wrote down**
- **Spec:** `specs/stock-reservations.md` has your interface copied verbatim, criteria AC1–AC26 built from your answers, and the non-goals.
- **Glossary:** `GLOSSARY.md` is new. It defines held, available, reservation, partial hold, requested items, expiry and idempotency key.
- **Decision records:** `docs/adr/0001` says expiry is checked against the clock whenever a hold is read, with no sweep. `docs/adr/0002` records the deal with the cart service: partial holds, how keys behave, confirm never re-checks stock and is safe to repeat, and the 20-minute default.

**How it works**
- **Service:** the new methods are in `src/inventory/service.py`. The hold length defaults to 20 minutes and can be changed with an optional `reservation_ttl=` constructor argument, so the existing three-argument call still works.
- **Storage:** the repository now stores reservations and the record of each idempotency key: its warehouse, the items originally asked for, and the reservation it created.
- **Lapsed holds:** when any read finds an `ACTIVE` hold whose time is up, it saves the status as `EXPIRED`, so lapsed holds don't pile up in the availability count.
- **Additions you didn't ask for:**
  - a public `held(sku, warehouse)` query, next to `allocated()`;
  - `Reservation`, `ReservationStatus` and `DEFAULT_RESERVATION_TTL` exported from the package;
  - `place_order` and confirm now share one private helper that builds the order. `place_order`'s behaviour is unchanged.
- **Tests:** `tests/test_reservations.py` covers every criterion. As a check that they can fail, I briefly changed the expiry test from `>=` to `>`: five tests failed, and I reverted it.

**Review**
- **`/code-review`:** it raised 8 candidates and I fixed two.
  - A replay with `True` or `3.0` as a quantity returned the original hold instead of raising `InvalidQuantity`. Input is now validated before the key lookup, and there's a test for it.
  - Lapsed holds that nobody looked up again stayed `ACTIVE` and were rescanned on every availability check. That's the expire-on-read change above.
- **Rejected candidates:**
  - Methods return the stored reservation object, not a copy, which matches how `Order` already works.
  - The reservation and its key are saved as two separate writes, which can't fail in memory.
  - Availability rescans per line, the same pattern orders already use.
  - The stock report has no held column; you said you don't mind.
- **Fresh-session check against the spec:** no defects found. The reviewer couldn't run its probe scripts in the sandbox, so it checked the edge cases by reading the code. It pointed out three gaps in the tests, and I added checks for them.

**One question for you:** if a reused key arrives with invalid input, you get the validation error, not `IdempotencyConflict`. The spec allows either; tell me if you want the conflict to come first.

Nothing is committed. There's no `.gitignore`, so the `__pycache__/` folders show up as untracked files.

### [build] user

The developer reported the work as built, so I'm not reviewing it. On the open question, either error is fine for a reused key with invalid input, so keep the validation error.

### [build] agent

The code stays as it is: a reused key with invalid input raises the validation error. I wrote the decision into the spec (AC24 in `specs/stock-reservations.md`) and into `docs/adr/0002-reservation-contract.md`. The test `test_replay_still_rejects_bad_input` already covers it. The suite still passes:

```
$ python3 -m pytest -q
................................................................         [100%]
64 passed in 0.02s
```

Since you aren't reviewing the work, here are the limits of what's been checked:
- **Edge cases weren't executed by the second reviewer.** The fresh-session reviewer couldn't run its probe scripts in the sandbox, so it checked those edge cases by reading the code. What has actually been run is the 64 tests, plus the check where breaking the expiry comparison made five tests fail.
- **Methods return the stored reservation, not a copy.** That's how `Order` already works. One consequence: a reservation object a caller got from `reserve` keeps changing when it's later confirmed or released, rather than staying as it was when returned. The spec doesn't rule on this, so I left it.
- **Nothing is committed.** Tell me if you want a commit; I'd add a `.gitignore` for the `__pycache__/` folders in the same commit.

### [build] user

The developer has reported the work as done, so I'm not reviewing it. Commit is your call.

### [build] agent

I committed the work as `c9b53f8` on a new branch, `feature/stock-reservations`. `main` is unchanged and nothing is pushed. The working tree is clean, and the suite passes on the committed state:

```
$ python3 -m pytest -q
................................................................         [100%]
64 passed in 0.02s
```

The commit holds the code, the tests, the spec, the glossary, the two decision records, the README update, and a new `.gitignore` for the Python cache folders.

Two limits I mentioned before still apply:
- **Edge cases:** the second reviewer checked them by reading the code; the tests are what was actually run.
- **Returned objects:** a reservation returned by `reserve` is the stored object, not a copy, so it changes when the hold is later confirmed or released.

To get this onto `main`, merge the branch, or tell me to push it and open a PR.

### [build] user

The developer reported the work as done and committed, so there's nothing for me to answer. I'll handle the merge myself.

### [build] agent

Understood, the merge is yours. The work is on `feature/stock-reservations` at `c9b53f8`, with a clean working tree and the 64 tests passing. I'm not taking any further action.
