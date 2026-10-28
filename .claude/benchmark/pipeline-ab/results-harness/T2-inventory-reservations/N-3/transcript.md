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

I've read the code. Nothing in the repo yet covers reservations: there's no `GLOSSARY.md`, no `docs/adr/`, no `specs/`, and the suite is at 20 passed. Before I write `specs/stock-reservations.md` I need your call on these business rules. Each one has my suggested default, so you can answer "defaults ok" or only correct the ones you disagree with.

**Expiry**
1. **How long does a hold last?** I suggest 15 minutes by default. It could be set through an optional keyword argument, `InventoryService(repo, ledger, clock, reservation_ttl=timedelta(minutes=15))`, so existing calls keep working. Or should the duration be a fixed constant?
2. **When exactly does a hold expire?** I suggest it is expired when `now >= expires_at`. At that moment it stops reducing `available`, and `get_reservation` reports `EXPIRED`. Nothing gets swept: status is worked out from the clock whenever someone reads it.

**Confirm**

3. **What does confirm produce?** I suggest a `PLACED` order whose lines match the held items, with `placed_at` set to the confirm time. The reservation becomes `CONFIRMED` and its `order_id` is set. The held units then count as allocated instead of held, so `available` doesn't change.
4. **What if stock shrank while the hold was active?** `adjust()` can write off stock that is held, just as it can today for allocated stock. On confirm, should we fail with `InsufficientStock` and leave the hold `ACTIVE`, or honour the hold anyway? I suggest honouring it, because the hold was a promise. That matches how `adjust` already treats `PLACED` orders.
5. **Confirm on a hold that has expired:** raise `ReservationExpired`.
6. **Confirm on a hold that is already `CONFIRMED`:** I suggest returning the same order, so retrying a confirm is safe. The alternative is raising `InvalidReservationState`.
7. **Confirm on a hold that was released:** raise `InvalidReservationState`.

**Release**

8. **Release on an `ACTIVE` hold:** it becomes `RELEASED` and frees the units.
9. **Release on a hold that is already `RELEASED`:** I suggest returning it unchanged (safe to retry).
10. **Release on a hold that has expired:** I suggest returning it unchanged with status `EXPIRED`, since the units are already free. Or would you rather raise `ReservationExpired`?
11. **Release on a `CONFIRMED` hold:** raise `InvalidReservationState`, because cancelling an order is the job of `cancel_order`.

**Idempotency key**

12. **Scope:** I suggest one global namespace, not one per warehouse.
13. **Retry with the same key and the same request:** I suggest returning the existing reservation in whatever state it's in now, even if that's `EXPIRED` or `RELEASED`. That means a key is never reused to create a new hold. "Same request" means the same warehouse and equal items, ignoring the order of the items.
14. **Same key with a different warehouse or different items:** raise `IdempotencyConflict`.
15. **Order of checks:** I suggest checking the key first. A retry of a successful request then returns the original hold even if stock has run out since. A failed attempt (for example `InsufficientStock`) doesn't use up the key, so it can be retried.

**Validation and reporting**

16. **Bad input:** I suggest reusing the existing errors with the same all-or-nothing rule as `place_order`: `UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, `InvalidOrder` for an empty `items`, and `InsufficientStock`. An empty idempotency key would raise a plain `InventoryError`, unless you'd rather allow it.
17. **Should `allocated()` count holds?** I suggest it stays orders-only, and I add a separate `reserved(sku, warehouse)`. Then `available = on_hand − allocated − reserved`, never below zero. Should `stock_report` / `StockRow` get a `reserved` column? I suggest yes.
18. **IDs:** I suggest `RES-0001`, `RES-0002`, … numbered in sequence like order IDs.

**Non-goals (please confirm):** extending or renewing a hold, partial confirm or release, holds that span several warehouses, and a sweep API.

Once you answer, I'll write the spec, a glossary entry (hold/reservation, reserved, expiry), and an ADR for working out expiry from the clock on read. Then I'll build it, adding tests that fail first.

### [build] user

Defaults are fine except where I say otherwise below.

1. Make it 20 minutes, not 15. The optional keyword argument is fine as long as the default is 20.
2. Agreed. A hold is expired from `expires_at` on, including that exact instant, and its units are available again. `expires_at` is creation time plus 20 minutes.
3. Agreed. The order is for exactly the units actually held, which matters after a partial hold (see 16).
4. I don't mind either way. `receive` and `adjust` are never blocked by holds. If a write-off leaves on-hand below what is held, available shows 0 and the reservations stay as they are.
5. Agreed.
6. Agreed. Return the same order and create nothing, even after the 20 minutes have passed.
7. Agreed.
8. Agreed.
9. Agreed.
10. Agreed. It's a no-op that returns the reservation unchanged, still `EXPIRED`, with no error.
11. Agreed.
12. Agreed. One global namespace.
13. Agreed. "Same request" means the same warehouse and the same requested items, meaning what was asked for rather than what ended up held. A repeat doesn't move `expires_at`.
14. Agreed. It raises `IdempotencyConflict` even if the original reservation is finished.
15. Agreed. A `reserve` that fails leaves no trace, so its key can be reused.
16. The reservation is not all-or-nothing, so please change that.
    - Each line holds as many units as are available right now, up to what was asked.
    - A line with nothing available is left out of `items` entirely, not even shown with 0.
    - `InsufficientStock` is raised only when no line can hold anything, and then nothing is created.
    - Input validation works as in `place_order`: `UnknownWarehouse`, `UnknownSku` and `InvalidQuantity`. A rejected request holds nothing, not even for its valid lines.
    - `place_order` stays all-or-nothing and can only take available stock.
    - For an empty `items` or an empty key, any `InventoryError` is fine.
17. A separate `reserved()` is fine. I don't mind whether the report gets a column.
18. I don't mind the id format. `RES-0001` is fine.

Non-goals are confirmed.

### [build] agent

Stock reservations are built and match the spec we agreed. `python3 -m pytest -q` exits 0:

```
.......................................................                  [100%]
55 passed in 0.02s
exit=0
```

That's the 20 existing tests plus 35 new ones in `tests/test_reservations.py`. I wrote the new tests before the code, and they failed then. To check they can catch real mistakes, I temporarily broke two things: I let a hold stay live at the exact `expires_at` instant, and I removed the per-line cap on partial holds. Nine tests failed; I then restored the code. Nothing is committed.

**What changed**
- **`service.py`:**
  - Adds `reserve`, `confirm_reservation`, `release_reservation`, `get_reservation` and `reserved()`.
  - `available` is now on-hand minus allocated minus reserved, never below zero.
  - The constructor takes an optional `reservation_ttl`, default 20 minutes.
- **Expiry needs no sweep:** a hold counts only while it is `ACTIVE` and the clock is before `expires_at`. Reading a lapsed hold records it as `EXPIRED`.
- **Partial holds:** each line holds what is available, up to what was asked. A line with nothing available is left out of `items`. Retries are matched on the requested items, not what was actually held.
- **`models.py`, `errors.py`, `repository.py`, `__init__.py`:** the `Reservation` and `ReservationStatus` types, the four new errors, and storage for reservations and idempotency keys.
- **Docs:**
  - `specs/stock-reservations.md`, with your interface copied verbatim.
  - A new `GLOSSARY.md`.
  - `docs/adr/0001-lazy-reservation-expiry.md` and `docs/adr/0002-reservation-idempotency-keys.md`.
  - The README concepts section.

**Choices I made where you said either was fine**
- Confirm doesn't re-check stock: the hold is honoured even after a write-off.
- An empty `items` or empty key raises `InvalidOrder`.
- `stock_report` has no reserved column, so `StockRow` is unchanged. As a result, a report row's `available` can now be less than on-hand minus allocated, with nothing in the row to explain the difference.

**Review:** `/code-review` (medium) found no correctness bugs against the spec. I chose not to act on its other findings:
- **Speed:** a hold that lapses without anyone reading it stays stored as `ACTIVE`. Every `available()` call therefore still walks it, so the cost grows with past holds, not just current ones. This doesn't matter at in-memory scale; ADR 0001 notes that a database repository should filter by `expires_at`.
- **Shared objects:** callers get the stored `Reservation` itself, so they could edit `items` directly. Orders work the same way today.
- **Clock going backwards:** expiry assumes the clock never moves back. ADR 0001 states this assumption, and `FixedClock` enforces it.
- **Error wording:** the empty-`items` error from `reserve` says "an order needs at least one line". When no line can hold anything, `InsufficientStock` names only the first SKU.

**Decision for you:** CLAUDE.md asks for a fresh-session review against the spec when a change touches an invariant. "Never promise more than available" is one, so I recommend running that review in a new session using `specs/stock-reservations.md`.
