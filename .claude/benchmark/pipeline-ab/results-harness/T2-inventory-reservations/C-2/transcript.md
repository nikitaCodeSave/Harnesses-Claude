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

I've read the whole package. There's no `GLOSSARY.md`, no ADRs and no `specs/` yet, so I'll create them. Your request already settles the interface. The business rules below are still open. Each has my recommendation, so you can just reply "ok", or give the number and your change:

**1. Hold length.** How long does a hold last before it lapses? I'd use **15 minutes** as the default, adjustable through an optional constructor argument (`InventoryService(repo, ledger, clock, reservation_ttl=...)`). Existing three-argument calls would keep working.

**2. When exactly it lapses.** I'd treat a hold as lapsed **at** `expires_at` (`now >= expires_at`), not one tick after. A lapsed hold stops counting against availability right away. `get_reservation` then reports it as `EXPIRED`, even though no sweep ran.

**3. Confirming.**
- (a) Confirming an `ACTIVE` hold creates a `PLACED` order for exactly the held items. The hold turns into that order's allocation, and stock is **not re-checked**. The hold was the promise, so a write-off during the hold doesn't block it. Is that right, or should confirm fail if on-hand has since dropped below what's needed?
- (b) Confirming a lapsed hold raises `ReservationExpired`.
- (c) Confirming an already `CONFIRMED` hold returns the **same order** again, since it's a safe retry. Confirming a `RELEASED` hold raises `InvalidReservationState`.

**4. Releasing.**
- Releasing an `ACTIVE` hold makes it `RELEASED`.
- Releasing an already `RELEASED` hold returns it unchanged (safe retry).
- Releasing a `CONFIRMED` hold raises `InvalidReservationState`. The order stays, and `cancel_order` is the way to undo it.
- Releasing a lapsed hold: I'd **return it as `EXPIRED`, with no error**, because the stock is already free and the caller got what they wanted. The alternative is raising `ReservationExpired`. Which do you prefer?

**5. Retries with the same idempotency key.**
- Same key with the same warehouse and items (key order ignored) returns the **original reservation in its current state**, whatever that state is. So retrying after the hold lapsed returns the `EXPIRED` one, and the cart needs a new key to try again.
- Same key with a different warehouse or different items raises `IdempotencyConflict`.
- A `reserve` call that failed (for example with `InsufficientStock`) stores nothing, so the key stays free for a retry.
- Keys are global, not per warehouse, and never expire.

**6. Validation on `reserve`.** I'd copy `place_order`: all lines or nothing, using the existing `UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, `InvalidOrder` (no items) and `InsufficientStock`. Availability here means on-hand minus allocated minus active holds.

**7. Reporting holds.** `available` will subtract active holds. What should happen to `allocated()` and the back-office `stock_report`?
- (a) **My pick:** `allocated()` keeps meaning units promised to orders only. I add a separate `held(sku, warehouse)` query, and a `held` column at the end of `StockRow` with default 0, so existing rows still build. With this, available = on_hand − allocated − held.
- (b) `allocated()` includes active holds, and the report is unchanged.

**8. Minor detail.** I'd make reservation ids `RES-0001`, `RES-0002`, … to match `ORD-0001`. Order ids would only be used when a hold is confirmed.

### [build] user

1. No: make it 20 minutes (95% of payments finish within 18 min); optional TTL arg is fine if default is 20.
2. Agreed: lapses at expires_at, instant included, no sweep needed.
3. (a) Agreed: hold becomes the order's allocation, so available doesn't change at confirm and on-hand only moves when the order ships. If a write-off pushed on-hand below the hold, either behaviour is fine. (b) Agreed. (c) Agreed: a repeated confirm returns the same order and creates nothing, at any time, even after the 20 minutes have passed. Confirm of RELEASED -> InvalidReservationState.
4. Agreed on all. Releasing an EXPIRED one is a no-op returning it unchanged (status stays EXPIRED), no error.
5. Agreed on all. The key also stays taken when the original reservation is finished; a different warehouse or items still raises IdempotencyConflict. A retry doesn't move expires_at.
6. One big change: reserve is NOT all-or-nothing on stock. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of `items` entirely (not even with 0). Only when no line can hold anything does reserve raise InsufficientStock, and then nothing is created. Validation is like place_order: UnknownWarehouse, UnknownSku, InvalidQuantity for zero or negative; a rejected request holds nothing, not even for its valid lines. Partial filling is for reservations only: place_order stays all-or-nothing, but it can only take available stock, so it competes with holds. An idempotent repeat compares the requested items, not what ended up held.
7. (a) is fine. Whether the report shows held units doesn't matter to me.
8. Fine.

### [build] agent

Stock reservations are built: checkout can hold stock, confirm the hold into an order or release it, holds lapse on their own after 20 minutes, and retries with the same key are safe. The full suite passes:

```
$ python3 -m pytest -q
.............................................................            [100%]
61 passed in 0.02s
exit=0
```

Every acceptance criterion in the spec has at least one test that failed before the code existed. Nothing is committed yet.

**How it behaves, by your rules:**
- **Holding stock:** `reserve` holds, per line, whatever is available now, up to what was asked. Lines with nothing available are left out. It raises `InsufficientStock` only when no line gets anything, and then nothing is created. `place_order` is still all-or-nothing and competes with holds for the same stock.
- **Expiry:** a hold lapses at `expires_at`, that instant included, with no sweep. Every read checks it against the clock, and `get_reservation` then reports `EXPIRED`. The hold length is set with `reservation_ttl=` on the constructor, default 20 minutes; existing three-argument calls are unchanged.
- **Confirming:** the hold becomes the order's allocation, so `available` doesn't change at confirm. A repeated confirm returns the same order, at any time.
- **Releasing:** releasing an already released or lapsed hold returns it unchanged, with no error.
- **Idempotency:** keys are global and never expire. A retry is compared against what was *requested*, not what ended up held. It returns the original reservation in whatever state it's in now and never moves `expires_at`.
- **Reporting:** there's a new `held(sku, warehouse)` query, and `StockRow` has a `held` column with default 0. `allocated()` still counts orders only.

**Review:**
- **Fresh reviewer against the spec:** no defects in the code. It did find a test that couldn't fail (it compared an object with itself), which I fixed, plus an expiry test that only partly covered its rule, which I split in two.
- **One behaviour change from that review:** a retry like `{"MUG": 2.0}` used to be treated as the same request as `{"MUG": 2}`. Input is now validated before the key lookup, so it raises `InvalidQuantity`. I added a test that failed before the fix.
- **`/code-review`:**
  - I fixed a model docstring that contradicted the expiry rule.
  - I left the rest as is, because they're design choices that match existing code or things the spec rules out:
    - Live stored objects are returned to callers, just as orders already are.
    - Holds aren't indexed for speed, which is fine for the in-memory store.
    - Reads write the `EXPIRED` status back, as ADR 0001 records.
    - The step that saves the hold and records its key isn't atomic. Concurrency is a non-goal.

**Written down:**
- The spec is in `specs/stock-reservations.md`, with your interface copied verbatim.
- New terms are in `GLOSSARY.md`.
- Three ADRs record the hard-to-reverse decisions: lapsing on read, partial fill, and key rules (`docs/adr/0001` to `0003`). ADR 0003 notes that a database-backed repository will need a rule for how long to keep keys.
- I updated the README.

There's no `.gitignore`, so the `__pycache__/` folders show up as untracked files. Leave them out when you commit.
