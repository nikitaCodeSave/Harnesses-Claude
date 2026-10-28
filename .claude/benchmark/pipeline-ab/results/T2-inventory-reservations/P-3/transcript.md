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

I've read the whole package: service, repository, ledger, models, errors, reports and tests. There's no `GLOSSARY.md` or `docs/adr/` yet, so I'll create them once terms and decisions are settled. Some things in the code affect the questions below:

- `available = max(0, on_hand - allocated)`, and `allocated` counts only `PLACED` orders. `place_order` checks `available`, so holds will limit regular orders automatically once `available` subtracts them.
- `adjust` only stops on-hand from going below zero. A write-off can already drop on-hand below what's allocated, and the floor at zero hides that.
- `StockRow(sku, on_hand, allocated, available)` is built by position in `tests/test_reports.py`.

Here's round 1. These questions don't depend on each other.

---

❓ **Q1** - **What to call it**: You use "hold", "reservation" and "lapse". I'd make **Reservation** the one canonical term (it matches the API) and list "hold" as a word to avoid. Its time-based ending would be **expire** / `EXPIRED`, with "lapse" avoided. "Release" means only that a caller gave the stock back. A timeout is "expire", not "release".

➡️ Yes: Reservation and expire are canonical; hold and lapse are aliases to avoid.

---

❓ **Q2** - **How long a reservation lasts**: What exact duration? Is it one fixed value, or set by whoever builds `InventoryService`? `InventoryService(repository, ledger, clock)` has to keep working, so any setting would be an optional keyword argument with a default.

➡️ 15 minutes by default, overridable with an optional `reservation_ttl: timedelta` keyword argument on the constructor. `expires_at = now at reserve time + ttl`.

---

❓ **Q3** - **The exact expiry moment**: If `clock.now() == expires_at`, is the reservation still active or already expired?

➡️ Already expired. It's active only while `now < expires_at`. At that same instant it stops counting against `available`, and `get_reservation` reports `EXPIRED`.

---

❓ **Q4** - **All or nothing**: A cart asks for `{"MUG": 2, "TEE": 6}`, but only 5 TEE are available. Should it get a partial reservation, or nothing?

➡️ Nothing, the same as `place_order`. Raise the existing `InsufficientStock` for the first SKU that falls short and store nothing.

---

❓ **Q5** - **Retrying with the same key and same request**: The cart calls `reserve("WH1", {"MUG": 2}, "cart-42")` twice. The second call should return the **same** reservation (same `reservation_id`) and reserve no more stock. What if the original has moved on by the time the retry arrives (confirmed, released or expired)?

➡️ Yes, return the existing reservation as it is now, even if that's `CONFIRMED`, `RELEASED` or `EXPIRED`. The key stays bound to that reservation permanently and never creates a second one.

---

❓ **Q6** - **Same key, different request**: The key `cart-42` comes back with a different warehouse or different items. The quantities are compared per SKU, so the order of items in the dict doesn't matter.

➡️ Raise `IdempotencyConflict`. This applies even if the original has since been released or has expired.

---

❓ **Q7** - **A failed reserve doesn't use up the key**: If `reserve(..., "cart-42")` fails (`InsufficientStock`, `UnknownSku`, bad quantity), can a later call with `cart-42` succeed?

➡️ Yes. A key is bound only when a reservation is actually created, so the cart can retry after stock arrives. Keys are global, not per warehouse.

---

❓ **Q8** - **Confirm uses the reserved stock without checking again**: Confirm turns an `ACTIVE` reservation into a `PLACED` Order with the same lines, `placed_at = now`, from the normal `ORD-` sequence. The reservation becomes `CONFIRMED` with `order_id` set. Should confirm check `available` again? Suppose a write-off has shrunk on-hand in the meantime.

➡️ Don't check again. The stock was promised to this reservation, so confirm just moves it from "reserved" to "allocated". Write-offs keep their current behaviour, as they already do for orders.

---

❓ **Q9** - **Confirm or release when not `ACTIVE`**: What happens when someone calls:
- confirm on an `EXPIRED` reservation
- release on an `EXPIRED` reservation
- confirm or release on a `CONFIRMED` reservation
- confirm or release on a `RELEASED` reservation

➡️ Both confirm and release on `EXPIRED` raise `ReservationExpired`. Every other case raises `InvalidReservationState`, including confirming twice and releasing twice. This matches how `ship_order` and `cancel_order` behave today. The idempotency key covers `reserve` only.

---

❓ **Q10** - **Validating `reserve` input**: An unknown warehouse or SKU raises `UnknownWarehouse` / `UnknownSku`, and a quantity that isn't a positive int raises `InvalidQuantity`. Which error for empty `items`? And is an empty `idempotency_key` allowed?

➡️ Empty `items` raises the existing `InvalidOrder` (it already means "the request is malformed"). An empty or blank `idempotency_key` raises `InvalidOrder` too.

---

❓ **Q11** - **Reserved stock in queries and the report**: `available` becomes `on_hand - allocated - reserved`, floored at 0. `allocated` stays orders-only, and a new `InventoryService.reserved(sku, warehouse)` query covers active reservations. Should the back-office `stock_report` show it?

➡️ Yes, add a `reserved: int = 0` field at the **end** of `StockRow`, so existing positional uses keep working.

---

❓ **Q12** - **Out of scope**: No extending or refreshing a reservation, no editing its items, and no partial confirm.

➡️ Yes, all three are out of scope for now.

### [grill] user

Answers by number:

1. Agreed. Reservation and expire are the terms to use.
2. The duration is 20 minutes, not 15. A hold lasts 20 minutes from creation, and `expires_at` is creation time plus 20 minutes. The optional `reservation_ttl` keyword argument is fine as long as the default is 20 minutes.
3. Agreed. At `expires_at` and after, the reservation is EXPIRED and its units are available again.
4. No, partial holds are what I want here. Each line holds as many units as are available right now, up to what was asked. In your example the cart gets 2 MUG and 5 TEE.
   - A line with nothing available is left out of `items` entirely, not shown with 0.
   - `reserve` fails with `InsufficientStock` only when no line can hold anything. In that case nothing is created.
   - `place_order` stays all-or-nothing as it is today.
5. Agreed. Compare the request by what was asked for, not by what ended up held. A repeat returns the existing reservation in its current state and doesn't move `expires_at`.
6. Agreed.
7. Agreed. A failed `reserve` leaves no trace, and its key can be used again.
8. Agreed that confirm doesn't re-check. The hold becomes the order's allocation, so `available` doesn't change at confirm. After a partial hold, the order covers only the units held. Confirm after a write-off can succeed or raise `InsufficientStock`; I don't mind which.
9. This is wrong in several places. The rules are:
   - Confirm on EXPIRED raises `ReservationExpired`. This includes a reservation that has just lapsed.
   - Confirm on RELEASED raises `InvalidReservationState`.
   - Confirm on an already CONFIRMED reservation is not an error. It returns the same order and creates nothing, even after the 20 minutes have passed. The payment service retries confirm.
   - Release on CONFIRMED raises `InvalidReservationState`.
   - Release on RELEASED or EXPIRED is a no-op that returns the reservation unchanged. Its status stays as it was and there is no error.
10. Unknown warehouse, unknown SKU and bad quantity are validated exactly like `place_order`. A rejected request holds nothing, not even for its valid lines. For empty `items` and an empty key, any `InventoryError` is fine, so `InvalidOrder` is OK.
11. Adding `reserved` to the report is fine. Make sure `available` is `on_hand - PLACED allocations - ACTIVE reservations`, per SKU per warehouse and never below 0. A reservation in one warehouse must not affect any other warehouse.
12. Agreed, all three are out of scope.

### [grill] agent

I've created `GLOSSARY.md` with the terms we've settled. The "Avoid" entries say not to use "hold", "lapse" or "cancel" for reservations.

Your answers raise a few new questions. Here's round 2.

---

❓ **Q13** - **Confirm on CONFIRMED after the order has changed**: Confirm is retried, then the order gets cancelled (or shipped). Later the payment service retries `confirm_reservation` again. Should it get that order back in whatever state it's in now, cancelled or shipped?

➡️ Yes, return the existing order exactly as it is now. Don't raise an error and don't create a new order. This matches how a repeated `reserve` returns the reservation as it is now.

---

❓ **Q14** - **Only ACTIVE reservations expire**: After `expires_at`, a CONFIRMED reservation stays `CONFIRMED` and a RELEASED one stays `RELEASED` when read with `get_reservation`. Only an ACTIVE reservation becomes `EXPIRED` when its time passes.

➡️ Yes, only ACTIVE reservations turn into EXPIRED.

---

❓ **Q15** - **What's in `InsufficientStock` when nothing can be reserved**: A `reserve` call gets zero units on every line, so it raises `InsufficientStock(sku, warehouse, requested, available)`. That error names one SKU. Which one?

➡️ The first line in the order the request listed them, with `available=0`.

---

❓ **Q16** - **The requested amounts aren't visible on the Reservation**: Under Q5, retries are compared against what was asked for, so the service has to remember the requested amounts. Should `Reservation` show them (for example as `requested: dict[str, int]`)? Or is `items` (what was actually reserved) enough for callers, who can work out any shortfall from their own request?

➡️ Keep them internal. `Reservation` has only the fields you listed, and callers see what was actually reserved in `items`.

---

❓ **Q17** - **Recording partial reservations in an ADR**: `reserve` reserves part of a request while `place_order` is all-or-nothing. Someone reading the code later is likely to see that as a bug and "fix" it. Undoing it would also break the cart service's contract. Should I write a short ADR, `docs/adr/0001-partial-reservations.md`, saying this is deliberate and why? If so, give me the reason in one line.

➡️ Yes, write it. The reason would be something like: "checkout would rather sell what's there and let the customer adjust the cart than fail the whole cart over one short line." Correct me if the real reason is different.

### [grill] user

Answers by number:

13. Yes. A repeated confirm returns the existing order as it is now, whether it's cancelled or shipped. It raises no error and creates no new order.
14. Yes. Only ACTIVE reservations expire. CONFIRMED and RELEASED ones never change on their own.
15. Which SKU it names doesn't matter, so your choice is fine.
16. Fine. Keep the requested amounts internal. The cart can see any shortfall by comparing `items` with what it asked for.
17. Yes, write the ADR. The reason is that "only 3 left, we've held them for you" converts better than an error. The cart shows the shortfall itself by comparing `items` with what it asked for.

### [grill] agent

I've written the ADR at `docs/adr/0001-partial-reservations.md`. Nothing is left open, so here is the whole design. Please confirm it matches what you have in mind before I write any code.

**Reserve**: `reserve(warehouse, items, idempotency_key)`
- It checks the warehouse, the SKUs and the quantities exactly like `place_order` does. If anything is invalid, it reserves nothing. Empty `items` or an empty key raises `InvalidOrder`.
- If the key is already linked to a reservation:
  - With the same warehouse and the same requested amounts, it returns that reservation as it is now, and `expires_at` doesn't move.
  - With anything else, it raises `IdempotencyConflict`.
- Otherwise each line gets `min(requested, available)`, and lines that get 0 are dropped.
  - If every line gets 0, it raises `InsufficientStock`, naming the first requested SKU. Nothing is stored and the key stays free.
  - If any line gets stock, it creates a reservation with status `ACTIVE`, `expires_at = now + reservation_ttl` (20 minutes by default, set by an optional keyword argument on the constructor), and the key linked to it.

**Expiry**: a reservation is worked out from the injected clock whenever it's read, so no sweep job is needed.
- An `ACTIVE` reservation where `now >= expires_at` is reported as `EXPIRED` and stops counting as reserved.
- `CONFIRMED` and `RELEASED` reservations never change on their own.

**Confirm**: `confirm_reservation(reservation_id)`
- **ACTIVE**: it creates a `PLACED` order containing exactly the units in `items`. The order gets the next `ORD-` number and `placed_at = now`. The reservation becomes `CONFIRMED` with `order_id` set, and `available` doesn't change. There's no fresh stock check.
- **CONFIRMED**: it returns the existing order as it is now (it may be cancelled or shipped). There's no error and nothing new is created.
- **EXPIRED**: it raises `ReservationExpired`. This includes a reservation that has only just expired.
- **RELEASED**: it raises `InvalidReservationState`.

**Release**: `release_reservation(reservation_id)`
- **ACTIVE**: the reservation becomes `RELEASED`.
- **RELEASED** or **EXPIRED**: it returns the reservation unchanged, with no error.
- **CONFIRMED**: it raises `InvalidReservationState`.

**Queries**
- `get_reservation` raises `ReservationNotFound` for an unknown ID.
- `reserved(sku, warehouse)` is the total of `ACTIVE` reservations that haven't expired.
- `available` is `max(0, on_hand - allocated - reserved)`, worked out per SKU per warehouse. Because `place_order` already checks `available`, it automatically respects reservations.
- `StockRow` gets a `reserved: int = 0` field added at the end.

**Models and errors**
- `Reservation` and `ReservationStatus` go in `models.py`, with exactly the fields you listed. The requested amounts and the key are kept in the repository and aren't visible to callers.
- The four new errors go in `errors.py`, all subclassing `InventoryError`.
- The README's concepts section will be updated to match.

**Out of scope**: extending a reservation, editing its items, and confirming only part of it.

One small choice of mine: if a retry reuses a key with an invalid request (for example an unknown SKU), the validation error comes first, ahead of `IdempotencyConflict`. Both are `InventoryError`s.

Is this our shared understanding? If so, I'll write it up as `.scratch/stock-reservations/spec.md`, then implement it with tests.

### [grill] user

The design matches what I have in mind. Don't write the spec file or any code yet. I'll run /to-spec, /to-tickets and /implement-spec myself, in that order.

### [grill] agent

Understood. I'll stop here, and I haven't written a spec file or any code. Nothing has been committed either.

The grilling session left two new files for `/to-spec` to build on:
- `GLOSSARY.md`: the agreed terms. It uses Reservation, Reserved, Confirm, Release, Expire and Idempotency key, and lists the words to avoid (hold, lapse, cancel).
- `docs/adr/0001-partial-reservations.md`: records that reservations take whatever stock is available while orders stay all-or-nothing, and why.

The rest of the agreed design is only in the summary in my previous message, so `/to-spec` will need to work from that.

I tried to save a note that you run the spec, tickets and implementation steps yourself after a grilling session. Your permission settings block my memory folder, so I'll only remember it for this conversation.

### [to-spec] operator

/to-spec

### [to-spec] agent

Before I write the spec, please check the test seams.

**Proposed seam: the public `InventoryService` API, and nothing else.**

There's one primary seam, and it already exists. Every reservation test goes through the same `InventoryService(repo, ledger, clock)` built by the fixtures in `tests/conftest.py`, using only public calls:
- `reserve`, `confirm_reservation`, `release_reservation` and `get_reservation`
- the stock queries `on_hand`, `allocated`, `reserved` and `available`
- the existing order calls `place_order`, `ship_order` and `cancel_order`, used to check how reservations and orders interact

**Time is controlled with the existing `FixedClock`.** To test expiry, a test calls `clock.advance(minutes=20)` and then checks `get_reservation`, `available`, `confirm_reservation` and so on. No new time seam is needed, and no tests call a sweep or private helper.

**One secondary check through `stock_report`.** It's already a public read model with its own test file, so the new `reserved` column gets a single test there. That isn't a new seam.

**Not tested directly:**
- the repository's reservation storage and key lookup
- the internal record of requested amounts
- how expiry is worked out from the clock when a reservation is read

These are implementation details reached through the service. The repository can still be swapped out, but tests don't depend on how it stores reservations.

Tests will follow the style of `tests/test_orders.py`: a `stocked` fixture and one behaviour per test. They'll go in a new file of reservation tests.

Do these seams match what you expect? Once you confirm, I'll write `.scratch/stock-reservations/spec.md` and mark it `ready-for-agent`.

### [to-spec] user

Yes, those seams match what I expect. Go ahead and write the spec.

### [to-spec] agent

I've written the spec to `.scratch/stock-reservations/spec.md`, marked `Status: ready-for-agent`. No code has been written or committed.

It records the whole design we agreed. A few points worth knowing before `/to-tickets`:

- **User stories:** there are 64, grouped into reserving, safe retries, expiry, confirming, releasing, lookup, stock figures, and what happens to orders after confirmation.
- **Confirm and release:** a table in Implementation Decisions gives the outcome for each status, so it can be checked line by line.
- **Testing:** tests go through the public `InventoryService` API using the existing fixtures and `FixedClock`. There's also one test for the new `reserved` column in `stock_report`. It lists exactly what to cover, points to `test_orders.py` as the example to follow, and says existing tests must keep passing unchanged.

You should check a few things I added on my own:

- **Out of scope:** we never discussed these explicitly, so I inferred them from your answers:
  - no idempotency key on `place_order`, confirm or release
  - no guard stopping write-offs from dropping on-hand below what's promised
  - idempotency keys never expire
- **Small implementation choices:**
  - `Reservation` is a mutable dataclass, like `Order`.
  - It's exported from the package root.
  - The README's Concepts section gets updated.
  - The implementer decides whether the expired status is written back to storage, as long as behaviour is the same.
- **Confirm after a write-off:** the spec says the intended implementation doesn't re-check stock, so confirm succeeds. You said either outcome was fine.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here is how I'd split the spec, `.scratch/stock-reservations/spec.md`, into tickets. Nothing needs restructuring first: `_validate_items` and the `available` calculation can already be reused, so there's no preparatory refactor ticket.

**1. Reserve stock and look up a reservation**
- **Blocked by:** none.
- **What it delivers:**
  - `reserve` creates an `ACTIVE` reservation. Each line gets up to what's available, and lines with nothing available are dropped.
  - It raises `InsufficientStock` with nothing stored when no line gets any stock.
  - It validates like `place_order`, and a rejected request reserves nothing. Empty items or an empty key raise `InvalidOrder`.
  - `get_reservation` works, with `ReservationNotFound` for unknown identifiers.
  - `reserved(sku, warehouse)` is added, and `available` subtracts reserved units, so `place_order` respects them. Warehouses and SKUs stay independent.
  - `expires_at` is set to creation time plus 20 minutes, but nothing acts on it yet.
  - It adds the `Reservation` and `ReservationStatus` models (exported from the package), all four new errors, and reservation storage in the repository.

**2. Safe retries with an idempotency key**
- **Blocked by:** 1.
- **What it delivers:**
  - A repeated `reserve` with the same key and the same request returns the same reservation. It reserves no more stock and leaves `expires_at` unchanged.
  - The match compares what was requested, regardless of item order.
  - The same key with a different warehouse or items raises `IdempotencyConflict`.
  - A failed `reserve` leaves its key free for another attempt. Keys are global across warehouses.

**3. Reservations expire on their own**
- **Blocked by:** 2.
- **What it delivers:**
  - At or after `expires_at`, an `ACTIVE` reservation reads as `EXPIRED`, stops counting as reserved, and its units are available again. No sweep is involved.
  - The optional `reservation_ttl` constructor argument is added, defaulting to 20 minutes, and the old three-argument constructor still works.
  - A repeated `reserve` returns the reservation as `EXPIRED`, and a different request with the same key still conflicts.
- **Why blocked by 2:** it includes that last check, which needs idempotency.

**4. Confirm a reservation into an order**
- **Blocked by:** 3.
- **What it delivers:**
  - Confirming an `ACTIVE` reservation creates a `PLACED` order containing exactly the reserved units. It gets the next `ORD-` number and `placed_at = now`.
  - The reservation becomes `CONFIRMED` with `order_id` set, and `available` doesn't change.
  - Confirming again returns the same order as it is now, even after 20 minutes or after the order was cancelled or shipped.
  - Confirming an `EXPIRED` reservation raises `ReservationExpired`, including at exactly `expires_at`.
  - A `CONFIRMED` reservation never expires.
  - A repeated `reserve` returns the reservation as `CONFIRMED`.
  - Orders created this way ship and cancel normally, and cancelling the order leaves the reservation `CONFIRMED`.
- **Why blocked by 3:** it needs the expired state.

**5. Release a reservation**
- **Blocked by:** 4.
- **What it delivers:**
  - Releasing an `ACTIVE` reservation makes it `RELEASED`, and its units are available immediately.
  - Releasing a `RELEASED` or `EXPIRED` reservation returns it unchanged.
  - Releasing a `CONFIRMED` reservation raises `InvalidReservationState`, and so does confirming a `RELEASED` one.
  - A `RELEASED` reservation stays released after its expiry time.
  - A repeated `reserve` returns the reservation as `RELEASED`.
  - The README gets the Reserved concept and the reservation lifecycle.
- **Why blocked by 4:** it needs the confirmed state.

**6. Show reserved stock in the stock report**
- **Blocked by:** 1.
- **What it delivers:**
  - `StockRow` gains a `reserved` field (default 0) after the existing fields, filled in by `stock_report`.
  - Positional `StockRow` construction and the existing report test keep working.

Tickets 1 to 5 form a chain because each one tests how its new state interacts with the earlier ones. The alternative was to collect every "repeated reserve after confirm, release or expiry" check into a final idempotency ticket. That would let expiry and idempotency proceed in parallel, but the retry rules would end up split across two tickets. I chose the chain. Ticket 6 can run alongside anything after ticket 1.

Please check three things:
- Is the size about right? I could merge ticket 6 into ticket 1, or split ticket 1 so that `available`/`reserved` is its own ticket.
- Are the dependencies right, or do you prefer the parallel option described above?
- Should any tickets be merged or split?

### [to-tickets] user

The split and the dependency chain look fine to me, so keep the chain. I don't want any merges or splits. Go ahead and write the tickets.

### [to-tickets] agent

I've written the six tickets to `.scratch/stock-reservations/issues/`, all marked `ready-for-agent`, with the chain as you approved it:

| # | Ticket | Blocked by |
|---|--------|------------|
| 01 | Reserve stock and look up a reservation | none |
| 02 | Safe retries with an idempotency key | 01 |
| 03 | Reservations expire on their own | 02 |
| 04 | Confirm a reservation into an order | 03 |
| 05 | Release a reservation | 04 |
| 06 | Show reserved stock in the stock report | 01 |

Ticket 01 can start now. Ticket 06 can run alongside 02 to 05 once 01 is done.

Each ticket describes the behaviour to build and lists checkable acceptance criteria. Following the spec, there are no file paths or code snippets.

The criteria include a few points we agreed during the design that you might not expect to find there:
- **02:** if a retry reuses a key with an invalid request, the validation error is reported rather than the conflict.
- **04:** cancelling an order created by confirm leaves the reservation `CONFIRMED`.
- **05:** this ticket also updates the README.

Nothing has been committed. You can run `/implement-spec` next.

### [implement-spec] operator

/implement-spec .scratch/stock-reservations/spec.md

### [implement-spec] agent

The whole stock reservations spec is implemented on the integration branch `stock-reservations`, and all 112 tests pass. The 20 original tests are unchanged; the rest are new.

**Tickets:** each was built test-first in its own worktree, then merged. 01 went first, then 02 and 06 in parallel, then 03, 04 and 05 in order.

| Ticket | Commit |
|---|---|
| 01 Reserve stock and look up a reservation | `c3b0b2e` |
| 06 Reserved column in the stock report | `83753ec` |
| 02 Safe retries with an idempotency key | `7998020` |
| 03 Reservations expire on their own | `81d28a9` |
| 04 Confirm a reservation into an order | `5b28ec1` |
| 05 Release a reservation, plus README | `be199a5` |

**Code review:**
- **Spec:** no missing or wrong behaviour. The method names, fields, error types, every state transition, and expiry being applied on every read all match the spec.
- **Standards:** no rule violations, only judgement calls. In `6e7a7c4` I fixed four:
  - Confirming a reservation and placing an order now build the order through one shared helper.
  - The repository stores each idempotency key as a small named record instead of a bare tuple.
  - An empty reservation request no longer gets the message "an order needs at least one line".
  - The code no longer uses "held", which the glossary says to avoid.
- **Left as is:**
  - Confirm and release still check the status separately, because merging them read worse.
  - Looking up a reservation still saves its expired status back to storage, which the spec allows.

**Tracker:** the spec and all six tickets are set to `Status: resolved`, with their checkboxes ticked and a comment naming the commit (`c792421`). There's no git remote, so I didn't open a PR. `main` is unchanged.

**Cleanup:** all implementer worktrees and their branches are removed.

**Two small things for you:**
- `GLOSSARY.md` itself still uses "held" in its definitions of Reserved and Confirm. I left it alone because it's your domain document.
- The repo has no `.gitignore`, so `__pycache__/` shows up as untracked.
