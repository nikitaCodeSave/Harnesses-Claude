### [grill] operator

/grill-with-docs Add stock reservations to the `inventory` package. Checkout must be able to hold stock for a cart before payment, then either confirm the hold into an order or release it. Holds nobody confirms must lapse on their own after a while, and retries from the cart service must be safe (idempotency key).

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

### [grill] agent

I've read the whole package: `service.py`, `models.py`, `errors.py`, `repository.py`, `reports.py` and the tests. There's no `GLOSSARY.md` or `docs/adr/` yet, so I'll create them as decisions get made. Here is what the current code already settles:

- **Available** = on-hand − allocated, floored at zero. **Allocated** means units on `PLACED` orders only.
- `place_order` is all-or-nothing and raises `InvalidOrder`, `UnknownSku`, `UnknownWarehouse`, `InsufficientStock` and `InvalidQuantity`.
- A write-off can already push allocated above on-hand. Available is then floored at 0, but existing orders stay valid.
- Order IDs are sequential (`ORD-0001`), and time comes only from the injected `Clock`.

Round 1 below. Every question here can be answered now; none depends on another.

---

❓ **Q1** - **Naming: "held" is a separate quantity, not part of "allocated"**: You say both "hold" and "reservation", and the code already uses "allocated" for orders. I'd use these terms:
- **Reservation**: the thing the cart service creates.
- **Held**: the units sitting in ACTIVE Reservations for a (SKU, warehouse).
- **Allocated**: unchanged, units on PLACED orders.
- **Available** becomes `on_hand − allocated − held`, floored at 0.

A Reservation **expires** (no "lapses"), is **released** (no "cancelled"), and is **confirmed** into an Order. `allocated()` keeps its current meaning, and I add a `held(sku, warehouse)` query next to it.

➡️ Yes: Held is its own term, Allocated is unchanged, and the vocabulary is fixed as above.

---

❓ **Q2** - **How long does a Reservation last, and who sets it?**: `reserve()` has no TTL parameter, so the duration has to be set on the service. I'd add an optional keyword, `InventoryService(repository, ledger, clock, reservation_ttl=timedelta(minutes=15))`, so existing three-argument calls keep working. Is 15 minutes the right default, and is one TTL for every warehouse and SKU enough?

➡️ Yes: one service-wide TTL, default 15 minutes, overridable through the constructor. `expires_at = reserved_at + ttl`.

---

❓ **Q3** - **Exactly when does a Reservation expire?**: When `clock.now() == expires_at`, the Reservation could be expired or still active.

➡️ Yes: it is expired at `now >= expires_at`. At that instant the units count as available again, `get_reservation` shows `EXPIRED`, and confirming is refused.

---

❓ **Q4** - **Can a Reservation be extended?**: For example, the customer is still on the payment page at minute 14, and the cart service wants more time.

➡️ No extension. `expires_at` is fixed when the Reservation is created. If the cart needs more time, it releases and reserves again under a new key.

---

❓ **Q5** - **Confirm always succeeds on an ACTIVE Reservation, without re-checking stock**: Scenario: you hold 5 MUG, then someone writes off 3 broken mugs, so on-hand drops below what's held. Should confirm fail? I'd say no. The held units were promised, so confirm moves them straight into a PLACED Order. That matches how write-offs already treat PLACED orders (available floors at 0). The Order looks exactly like one from `place_order`: same lines, `placed_at` = confirm time, a normal `ORD-nnnn` id. The Reservation becomes `CONFIRMED` and its `order_id` is set. After that, ship and cancel work as usual, and cancelling the order does not bring the Reservation back.

➡️ Yes: no stock re-check, and confirm creates an ordinary PLACED Order.

---

❓ **Q6** - **What each call does in each state**: This is mostly about retries being safe. My proposed table:

| call ↓ / status → | ACTIVE | CONFIRMED | RELEASED | EXPIRED |
|---|---|---|---|---|
| `confirm_reservation` | → CONFIRMED, returns new Order | returns the **same** Order (safe retry) | `InvalidReservationState` | `ReservationExpired` |
| `release_reservation` | → RELEASED | `InvalidReservationState` | returns it unchanged (safe retry) | returns it unchanged, still `EXPIRED` |

An unknown id raises `ReservationNotFound` everywhere, including `get_reservation`.

➡️ Yes to the table. The cells most worth checking against your rules are: confirming twice returns the same Order instead of raising, and releasing an expired Reservation is a quiet no-op instead of raising `ReservationExpired`.

---

❓ **Q7** - **What the idempotency key means**: My proposal:
- (a) The key is global, not per warehouse.
- (b) The same key with the same request (same warehouse and the same items, in any dict order) returns the original Reservation as it is now, even if it has since been confirmed, released or expired. It never creates a second hold, and it doesn't check stock again.
- (c) The same key with a different warehouse or different items raises `IdempotencyConflict`.
- (d) Keys never expire.
- (e) If the first call failed (for example with `InsufficientStock`), the key is not recorded, so a retry can still succeed.

➡️ Yes to (a) through (e).

---

❓ **Q8** - **Validating a reserve request**: I'd reuse the `place_order` rules unchanged: an empty `items` raises `InvalidOrder`, unknown SKUs or warehouses raise the existing errors, quantities that aren't positive integers raise `InvalidQuantity`, and the request is all-or-nothing, raising `InsufficientStock` against the new available. The idempotency lookup runs **first**, so a valid replay never fails validation or the stock check.

➡️ Yes.

---

❓ **Q9** - **Back-office stock report**: Once available subtracts held units, a `StockRow` reading `on_hand=10, allocated=0, available=6` no longer adds up. Should `StockRow` get a `held` column? I'd add it as the last field with a default of 0 so existing positional constructions keep working.

➡️ Yes: add `held` to `StockRow` as the last field.

---

❓ **Q10** - **Reservation IDs**: Should they follow the order format, sequential `RES-0001`, `RES-0002`, …, created by the repository?

➡️ Yes.

### [grill] user

Most of this matches what I want. Two points need correcting.

- **Q2:** The default is **20 minutes**, not 15. A service-wide TTL that you can override in the constructor is fine.
- **Q8:** Reservations are **not** all-or-nothing.
  - Each line holds as many units as are available right now, up to what was asked.
  - A line with nothing available is left out of `items` entirely, not even shown with 0.
  - `reserve` raises `InsufficientStock` only when no line can hold anything. In that case nothing is created.
  - Unknown warehouse, unknown SKU or a non-positive quantity are rejected like in `place_order`, and a rejected request holds nothing, not even for its valid lines.
  - Only `place_order` stays all-or-nothing.
  - Doing the idempotency lookup first is fine.

Here is where I stand on the rest:
- **Q1:** Agreed. Holds are per SKU per warehouse, and a hold in one warehouse doesn't touch another.
- **Q3, Q4:** Agreed.
- **Q5:** Agreed, with two additions.
  - The order covers exactly the units held, so after a partial hold that means only those.
  - Available doesn't change at confirm, because the hold simply becomes the order's allocation.
- **Q6:** The table is right. A repeated confirm on a CONFIRMED reservation returns the same order at any time, even after the 20 minutes have passed.
- **Q7:** Agreed. "Same request" means what was *asked for*, not what ended up held. A replay doesn't move `expires_at`.
- **Q9, Q10:** I don't mind either way, so go with your recommendation.

### [grill] agent

I added `GLOSSARY.md` at the repo root with the terms settled so far: **Held**, **Available**, **Reservation**, **Requested**, **Confirm**, **Release**, **Expire** and **Idempotency key**. It also defines the existing On-hand, Allocated and Order so all the vocabulary is in one place. I also noted there that quantities are per SKU per warehouse.

Allowing partial holds raised four new questions:

---

❓ **Q11** - **Details of `InsufficientStock` when nothing can be held**: `InsufficientStock(sku, warehouse, requested, available)` describes a single SKU. Suppose you request `{"MUG": 3, "TEE": 2}` and both have 0 available. Which SKU should the error report?

➡️ Yes: report the first requested line in the caller's order, with that line's requested quantity and `available=0`.

---

❓ **Q12** - **Should `Reservation` show what was requested?**: Now that `items` can be smaller than the request, the cart service can't see the shortfall without remembering its own request. I'd add two fields after the ones you specified: `requested: dict[str, int]`, which is also what the idempotency check compares against, and `reserved_at: datetime`.

➡️ Yes: add `requested` and `reserved_at` to `Reservation`.

---

❓ **Q13** - **Is an empty idempotency key rejected?**: If `""` is accepted, every caller that sends an empty key shares one Reservation and gets the same reservation back, or `IdempotencyConflict`, almost at once.

➡️ Yes: reject an empty or blank key with `InvalidOrder` (the request is malformed), before anything else happens.

---

❓ **Q14** - **Should I write an ADR on why reserve is partial but place_order is all-or-nothing?**: Without context this asymmetry looks like a bug, and someone may later try to make the two consistent. It is also part of the contract with the cart service, so it's expensive to change. The ADR would be one paragraph, and I'd need your reason. My guess: a checkout that can show "we can hold 2 of your 3 mugs" converts better than one that fails the whole cart, while a direct order is an explicit commitment for exact quantities.

➡️ Yes: write `docs/adr/0001-partial-reservations.md`. Please correct the reason if my guess is wrong.

### [grill] user

Q11–Q13 are fine, and the ADR in Q14 is fine too. I only have a small correction to the ADR reason.

- **Q11:** Which SKU the error names doesn't matter to me, so use your recommendation.
- **Q12:** Extra fields are fine. Adding `requested` and `reserved_at` is OK.
- **Q13:** Any `InventoryError` is fine for an empty key, so `InvalidOrder` works.
- **Q14:** Go ahead with the ADR. Your reason is basically right. The cart can show "only 3 left — we've held them for you", which converts better than an error. The cart shows the shortfall itself by comparing `items` with what it asked for. A direct `place_order` stays all-or-nothing.

### [grill] agent

I wrote `docs/adr/0001-partial-reservations.md` with your reason for the partial-vs-all-or-nothing split. There are no open questions left, so here is the complete design for you to check before I write any code.

## Shared understanding

**Quantities** (per SKU per warehouse; warehouses never affect each other)
- `held(sku, warehouse)` is the total units in ACTIVE, unexpired Reservations.
- `allocated()` is unchanged: units on PLACED orders.
- `available` = on-hand − allocated − held, floored at 0.
- `StockRow` gets a `held` column as its last field, with a default of 0.

**Expiry**
- The TTL is set once for the service: `InventoryService(repository, ledger, clock, reservation_ttl=timedelta(minutes=20))`. The existing three-argument calls still work.
- `expires_at = reserved_at + ttl`. It is fixed when the Reservation is created; it is never extended, and replays don't move it.
- A Reservation is expired when `clock.now() >= expires_at`. Nothing sweeps them: every read works out the status from the clock, so expired holds drop out of `held` and `get_reservation` reports `EXPIRED`.

**`reserve(warehouse, items, idempotency_key)`**, checked in this order:
1. An empty or blank key raises `InvalidOrder`.
2. If the key has been used before:
   - Same warehouse and same *requested* items: return the original Reservation in its current state. Nothing is re-checked and `expires_at` doesn't change.
   - Anything else: raise `IdempotencyConflict`.
3. Validate the request the same way `place_order` does: `UnknownWarehouse`, `InvalidOrder` for empty items, `UnknownSku`, `InvalidQuantity`. Any failure means nothing is held.
4. Hold each line up to what is available right now. Lines with nothing available are left out of `items`.
   - If no line can hold anything, raise `InsufficientStock` naming the first requested line, with `available=0`. Nothing is created and the key isn't recorded.
5. Otherwise save a Reservation `RES-nnnn`: status ACTIVE, `items` = units held, plus `requested`, `reserved_at`, `expires_at`, `order_id=None`. Then record the key.

**What each call does in each state** (an unknown id raises `ReservationNotFound`, including in `get_reservation`)

| | ACTIVE | CONFIRMED | RELEASED | EXPIRED |
|---|---|---|---|---|
| `confirm_reservation` | creates a PLACED `ORD-nnnn` for exactly the held units; status → CONFIRMED; sets `order_id`; available doesn't change | returns the same Order, even after the TTL has passed | `InvalidReservationState` | `ReservationExpired` |
| `release_reservation` | → RELEASED, units go back to available | `InvalidReservationState` | returned unchanged | returned unchanged, still EXPIRED |

- Confirm doesn't re-check stock, so a write-off after the hold doesn't block it.
- The resulting Order then ships or cancels like any other Order. Cancelling it doesn't bring the Reservation back.

**Files**
- `models.py`: `Reservation` and `ReservationStatus`.
- `errors.py`: the four new errors.
- `repository.py`: storing Reservations, `next_reservation_id`, and the key index.
- `service.py`, `reports.py`.
- `__init__.py`: export the new names.
- `README.md`: add the Held concept and the Reservation lifecycle.
- New `tests/test_reservations.py`.

Is this the design you want? If yes, I'll implement it, test-first.

### [grill] user

The design matches what I want, and I have nothing to correct. Please don't implement yet, because that's outside this step. I'll run `/to-spec`, `/to-tickets` and `/implement-spec` myself when I'm ready.

### [grill] agent

Understood, I won't implement anything. The grilling session is finished and I haven't changed any code. This session left two new files in the repo, both uncommitted:

- **`GLOSSARY.md`**: definitions for On-hand, Allocated, Held, Available, Order, Reservation, Requested, Confirm, Release, Expire and Idempotency key, with the words to avoid for each.
- **`docs/adr/0001-partial-reservations.md`**: why `reserve` holds whatever it can while `place_order` stays all-or-nothing.

The agreed design is the summary in my previous message, which `/to-spec` can use.

I tried to save a memory note so future sessions stop after the design step, but your permission settings block writes to the memory folder. So it isn't saved, and I'll need reminding next time.

### [to-spec] operator

/to-spec

### [to-spec] agent

Before I write the spec, please confirm where it should be tested. I'd add no new seams and use the two that already exist:

1. **`InventoryService`, using its public methods only.** It's built the way `tests/conftest.py` already builds it, from a real `InMemoryRepository`, a real `Ledger`, and a `FixedClock`. Time and expiry are tested only by moving the `FixedClock` forward, with no sweep and no patching. Every reservation behaviour is checked through this one seam: `reserve`, `confirm_reservation`, `release_reservation`, `get_reservation`, `held`, `available` and `allocated`, plus `ship_order`/`cancel_order` on confirmed orders. For example, idempotency is checked by calling `reserve` twice, not by looking inside the repository's key index.
2. **`stock_report`**, only to show the new `held` column. This follows the pattern of `tests/test_reports.py`.

The new tests go in one file, `tests/test_reservations.py`, written in the style of `tests/test_orders.py`.

The spec will go to `.scratch/stock-reservations/spec.md` with the `ready-for-agent` label. Are these seams right?

### [to-spec] user

Yes, those seams are right. Go ahead and write the spec as you described.

### [to-spec] agent

The spec is written and published at `.scratch/stock-reservations/spec.md` with `Status: ready-for-agent`. No code has changed.

It follows the design you confirmed and the two test seams: `InventoryService` built from the real fixtures with a `FixedClock`, and `stock_report` for the `held` column. It has 55 user stories, covering reserving, idempotent retries, confirming, releasing, expiry, lookup and stock figures. It also points to the glossary and to ADR-0001.

I filled in a few small details we never discussed. Check these before you run `/to-tickets`:

- **What the new errors carry:**
  - `ReservationNotFound` carries the reservation id.
  - `ReservationExpired` carries the id and `expires_at`.
  - `InvalidReservationState` carries the id, the status and the attempted action, the same way `InvalidOrderState` does.
  - `IdempotencyConflict` carries the key.
- **Order lines from confirm** come in the same order as the Reservation's items.
- **The repository** gets a way to list Reservations, at least by warehouse, so it can work out `held`.
- **Stored status:** the implementer can choose whether an expired Reservation's stored status is updated when it's next read, or just worked out each time. The spec only fixes what callers observe.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here's the proposed breakdown. I don't think any refactoring is needed first. `_validate_items`, the repository's sequential-id pattern and the shared test fixtures can all be reused as they are.

1. **Reserve and look up a Reservation (full holds)**
   - **Blocked by:** none
   - **Delivers:**
     - `reserve` holds every requested unit when all of them are available.
     - A request is all-or-nothing invalid: unknown warehouse, unknown SKU, empty items, a bad quantity, or a blank key raises the existing errors and holds nothing.
     - IDs are sequential `RES-nnnn`. A new Reservation is ACTIVE with `order_id=None`, and `reserved_at`/`expires_at` use the `reservation_ttl` constructor keyword (default 20 minutes).
     - `get_reservation` works, and an unknown id raises `ReservationNotFound`.
     - New `held()` query; Available subtracts Held, per warehouse; `place_order` can't take held units.
     - `Reservation` and `ReservationStatus` are exported from the package.
2. **Partial holds**
   - **Blocked by:** 1
   - **Delivers:**
     - Each line holds up to what's Available, lines with nothing Available are left out, and `requested` keeps the original request.
     - `InsufficientStock` is raised only when nothing at all can be held. It names the first requested line and creates nothing.
     - `place_order` stays all-or-nothing.
3. **Expiry by the clock**
   - **Blocked by:** 1
   - **Delivers:**
     - A Reservation is EXPIRED once `now >= expires_at`, with no sweep.
     - Its units go back to Available, and `get_reservation` reports EXPIRED.
     - The TTL can be overridden; the three-argument constructor still works.
4. **Release**
   - **Blocked by:** 3
   - **Delivers:**
     - ACTIVE → RELEASED, and its units are freed straight away.
     - Releasing a RELEASED or an EXPIRED Reservation returns it unchanged.
     - An unknown id raises `ReservationNotFound`.
5. **Confirm into an Order**
   - **Blocked by:** 4
   - **Delivers:**
     - ACTIVE becomes a PLACED Order for exactly the held units. Available doesn't change, and stock isn't re-checked after a write-off.
     - Confirming a CONFIRMED Reservation returns the same Order, even after expiry.
     - EXPIRED raises `ReservationExpired`. RELEASED raises `InvalidReservationState`, and so does releasing a CONFIRMED Reservation.
     - The resulting Order ships and cancels normally.
6. **Idempotent reserve retries**
   - **Blocked by:** 2, 3
   - **Delivers:**
     - The same key with the same requested items, in any order, returns the original Reservation as it is now. Nothing is re-checked and `expires_at` doesn't move.
     - The match is judged on what was requested, not on what was held.
     - A different warehouse or different items raise `IdempotencyConflict`.
     - A failed reserve doesn't use up its key.
7. **Held column in the stock report, plus README**
   - **Blocked by:** 1
   - **Delivers:**
     - `StockRow.held` is a new last field with a default of 0, filled by `stock_report`, so each row adds up.
     - README covers Held and the Reservation lifecycle.

Once 1 lands, tickets 2, 3 and 7 can run in parallel; 6 can start once both 2 and 3 are done. I made 4 → 5 a straight chain so the cross-checks (confirming a released Reservation, releasing a confirmed one) belong to ticket 5, where both operations already exist.

- Is the granularity right? I could merge 2 into 1, or 4 into 5.
- Are the blocking edges right?
- Should any ticket be merged or split?

### [to-tickets] user

The granularity is fine, so keep 2 and 4 as separate tickets. The blocking edges are right, and I wouldn't merge or split anything. Go ahead and write the tickets.

### [to-tickets] agent

I've written seven tickets in `.scratch/stock-reservations/issues/`, one file each, numbered so blockers come first. All are `Status: ready-for-agent`, and the spec is unchanged.

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Reserve and look up a Reservation (full holds) | — |
| 02 | Partial holds | 01 |
| 03 | Expiry by the clock | 01 |
| 04 | Release | 03 |
| 05 | Confirm into an Order | 04 |
| 06 | Idempotent reserve retries | 02, 03 |
| 07 | Held column in the stock report, plus README | 01 |

Ticket 01 can start now; after it lands, 02, 03 and 07 can run in parallel.

Ticket 01 also adds the four new error classes and the `reservation_ttl` constructor keyword, since every later ticket needs them.

### [implement-spec] operator

/implement-spec .scratch/stock-reservations/spec.md

### [implement-spec] agent

There was nothing left to merge when this check ran. Tickets 02 and 03 had both reported back, and every ticket was already merged into `stock-reservations` along with the code-review fixes.

I've stopped the fallback checks, so no more of these will fire. The branch passes all 91 tests, all tickets and the spec are marked resolved, and the worktrees are cleaned up.
