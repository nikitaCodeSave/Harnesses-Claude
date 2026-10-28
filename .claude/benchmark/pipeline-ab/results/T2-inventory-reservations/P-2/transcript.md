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

I've read the whole package (service, models, errors, repository, reports, tests, README). Some context from the code that shapes these questions:

- `available = on_hand − allocated`, where **allocated** means units promised to `PLACED` orders. `place_order` checks against `available()`, so once holds count toward it, direct orders automatically can't take held stock.
- The existing model already allows over-allocation: `adjust()` can write off stock below what's allocated, and `available` is floored at 0. Only `ship_order` checks physical stock.
- `StockRow` in `reports.py` has `on_hand / allocated / available`. Once holds exist, those three columns won't add up any more.

Here is the first round.

---

❓ **Q1** - **Naming: what is a "hold" called?** Your brief uses "hold", "reservation" and "lapse" for overlapping ideas. My proposal for the glossary:
- **Reservation**: a time-limited claim on stock for one cart, in one warehouse. Avoid: hold, lock, cart allocation.
- **Reserved** (quantity): units of a SKU under *active* reservations. It is separate from **Allocated**, which stays "promised to PLACED orders".
- **Available** = on-hand − allocated − reserved, floored at 0.
- **Expire** (not "lapse" or "time out"): an active reservation passing its `expires_at` with nobody acting on it. **Release**: the cart explicitly gives the reservation up. **Confirm**: the reservation turns into a PLACED Order.

➡️ Yes, use these terms, and keep "allocated" meaning orders only.

---

❓ **Q2** - **Hold duration**: How long does a reservation live? `reserve()`'s signature is fixed, so the duration can't be passed per call. Options: (a) a hard-coded constant, (b) an optional keyword-only constructor argument, `InventoryService(repo, ledger, clock, reservation_ttl=timedelta(minutes=15))`, so existing calls keep working, (c) a per-warehouse setting.

➡️ (b), with a default of **15 minutes** from the moment of reserving.

---

❓ **Q3** - **Expiry boundary**: At exactly `now == expires_at`, has the reservation expired?

➡️ Yes. A reservation is live only while `now < expires_at`. At `expires_at` it stops counting toward Reserved, `get_reservation` reports `EXPIRED`, and it can no longer be confirmed.

---

❓ **Q4** - **Confirming an expired reservation**: If the cart calls `confirm_reservation` after `expires_at` (for example, payment was slow), what happens? (a) raise `ReservationExpired` and the cart must reserve again, or (b) quietly "revive" it if the stock is still available.

➡️ (a). Raise `ReservationExpired` and don't change any state. The reservation stays `EXPIRED`.

---

❓ **Q5** - **Retrying confirm**: If `confirm_reservation` is called again on a reservation that's already `CONFIRMED` (say, the cart's network timed out on the first call), should it return the **same** Order again instead of raising?

➡️ Yes. Return the existing order (`order_id` is stored on the reservation) and never create a second one. Confirming a `RELEASED` reservation raises `InvalidReservationState`.

---

❓ **Q6** - **Releasing in each state**:
- `ACTIVE` → becomes `RELEASED` and the stock frees up immediately.
- `RELEASED` (a retry) → return it unchanged, no error.
- `EXPIRED` → return it unchanged with status still `EXPIRED`, no error. The cart wanted the stock freed and it already is.
- `CONFIRMED` → raise `InvalidReservationState`. To undo a confirmed reservation, cancel the order instead.

➡️ Yes, exactly that table. (The alternative for `EXPIRED` would be to raise `ReservationExpired`. Say so if you prefer strict.)

---

❓ **Q7** - **Idempotency key semantics**:
- **Same key, same request** (same warehouse and the same `items` dict, ignoring key order) → return the original reservation **as it is now**, even if it has since been confirmed, released or expired. No new reservation, no new stock check. A new checkout attempt needs a new key.
- **Same key, different request** → `IdempotencyConflict`.
- **Scope**: keys are global, not per warehouse, and are remembered forever (for as long as the repository lives).
- **Failed attempts don't use up the key**: if `reserve` raises (say `InsufficientStock`), nothing is recorded, so retrying the same key can succeed once stock arrives.

➡️ Yes to all four.

---

❓ **Q8** - **Does confirm re-check stock?** Between reserve and confirm, someone could write off stock with `adjust()` so that on-hand drops below what's reserved. Should confirm (a) always succeed, because the reservation was a promise (this matches how PLACED orders already tolerate write-offs and only `ship_order` checks physical stock), or (b) re-check and raise `InsufficientStock`?

➡️ (a). Confirm moves the units from reserved to allocated without re-checking. Any shortfall comes up at shipping, the same way it does today.

---

❓ **Q9** - **What does confirm produce?** A normal `PLACED` Order with the next `ORD-` id, `placed_at` set to the confirm time, and the same lines as the reservation. After that it lives the normal order life: shipping or cancelling it never touches the reservation again, which stays `CONFIRMED`.

➡️ Yes.

---

❓ **Q10** - **Validating `reserve`**: Should it behave like `place_order` and be all or nothing? That means reusing `UnknownWarehouse`, `UnknownSku`, `InvalidQuantity` and `InsufficientStock` (measured against availability *after* other reservations), and `InvalidOrder` for empty `items`. That error name says "order", but it's the existing error for "request has no lines".

➡️ Yes. Reuse `InvalidOrder` for empty items rather than adding a new error.

---

❓ **Q11** - **Back-office stock report**: Once reservations exist, `on_hand − allocated ≠ available` in `stock_report`. Should I add a `reserved` column to `StockRow` (and a `service.reserved(sku, warehouse)` query), or leave the report as it is?

➡️ Yes. Add a `reserved` column (with `service.reserved()`) so each row still adds up.

### [grill] user

Two corrections; everything else is fine.

Q2: the hold lasts 20 minutes from creation, not 15. expires_at = creation + 20 min. A constructor option for the TTL is fine as long as the default is 20.

Q10: reserve is NOT all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of items entirely (not even with 0). InsufficientStock is raised only when no line can hold anything, and then nothing is created. The cart works out the shortfall by comparing items with what it asked for. Validation stays strict like place_order: unknown warehouse, unknown SKU, or quantity <= 0 rejects the whole request and holds nothing. place_order stays all-or-nothing as today; partial holds are for reservations only.

Related to Q7: the same-request check compares the requested items (what the cart asked for), not what was actually held, so a repeat of the same request must match even after a partial hold.

Q1, Q3, Q4, Q5, Q6, Q8, Q9, Q11: agreed.

### [grill] agent

I've noted both corrections: reservations last **20 minutes** (the TTL is a constructor option with a default of 20), and reserve holds **partially**, while `place_order` stays all-or-nothing. I've created `GLOSSARY.md` with the terms from Q1 plus **Requested quantity**, the new distinction your Q10 answer introduced. Partial holds open up a few new questions:

---

❓ **Q12** - **What `InsufficientStock` reports when nothing can be held**: The error describes a single SKU (`sku, warehouse, requested, available`), but a reservation request can have several lines that all come up empty. Which line should the error name?

➡️ The first line in the cart's request order, with that line's requested quantity and `available=0`. The cart only needs to know "nothing could be held".

---

❓ **Q13** - **Which check comes first, validation or the idempotency key?** Suppose a cart reuses a key whose earlier request succeeded, but the new request is malformed (for example `{"MUG": 0}`). Should it get `InvalidQuantity` or `IdempotencyConflict`?

➡️ Validate first. A malformed request is rejected with the validation error before the key is looked up. Only well-formed requests reach the idempotency check: same request returns the original, different request raises `IdempotencyConflict`.

---

❓ **Q14** - **What a retry returns after a partial hold**: To spell out what Q7 plus your note implies, here's an example. A cart asked for `{MUG: 5}` and got `{MUG: 2}`. Ten more MUGs arrive, and the cart retries with the same key and `{MUG: 5}`. It gets back the **original** reservation, still holding 2, with the same `expires_at`. A retry never tops up a reservation or extends its expiry.

➡️ Yes.

---

❓ **Q15** - **Two ADRs**: Both of these decisions would surprise a future reader, involved a real trade-off, and would affect the cart's contract if reversed. Should I write them up in `docs/adr/`?
- **0001 – Reservations expire lazily.** There's no sweeper job. A reservation counts as expired whenever the clock reads at or past `expires_at`, and every query reflects that. A sweeper was rejected because the package has no scheduler and all time comes from the injected clock.
- **0002 – Reservations hold partially, orders don't.** `reserve` holds what it can and the cart works out the shortfall, while `place_order` stays all-or-nothing.

➡️ Yes, write both.

### [to-spec] operator

/to-spec

### [to-spec] agent

I've written the spec to `.scratch/stock-reservations/spec.md` and marked it `ready-for-agent`, but it rests on answers you haven't given yet. You moved on before answering Q12–Q15, so for Q12–Q14 I used my recommended answers. The spec's Further Notes lists them as not yet confirmed.

**Testing seam:** there's just one, the public `InventoryService` API plus `stock_report`. Tests use the existing pytest fixtures and move time only with `FixedClock.advance`. No new seam is needed; the existing order, stock and report tests show the style to follow. Tell me if you expected tests anywhere else.

**Choices I made that change existing code:**
- **Report column:** the new `reserved` column goes **last** in `StockRow` and defaults to 0. The existing report test builds rows positionally as `StockRow("TEE", 8, 3, 5)`, so putting the column in the middle would break that test and any hidden test written the same way.
- **Confirm is idempotent even after expiry:** confirming an already-confirmed reservation returns its existing order even after `expires_at`, because expiry only applies to active reservations.
- **Expiry needs no particular call order:** a reservation counts as expired wherever it's read (lookup, confirm, release, retry, the `reserved` total) as soon as the clock reaches `expires_at`.

**Your corrections are built in:** reservations last 20 minutes (adjustable through an optional constructor setting), reserve holds partially, `place_order` stays all-or-nothing, and a retry is matched on what the cart *asked for*, not on what was held.

**Still open (a "yes" to each confirms the spec as written):**
- **Q12:** when nothing at all can be held, `InsufficientStock` names the first line of the request, with available = 0.
- **Q13:** a malformed request fails validation before its idempotency key is looked up.
- **Q14:** a retry never tops up a partial reservation or extends its expiry.
- **Q15:** I haven't written the two decision records (ADRs) yet: "reservations expire lazily, with no background sweeper" and "reservations hold partially, orders don't". Say yes and I'll add them to `docs/adr/`.

### [to-spec] user

Yes to Q12, Q13, Q14 and Q15, so write both ADRs. Your testing seam, the reserved column placed last, and the other choices are fine.

### [to-spec] agent

I wrote both decision records, and the spec now has no open questions. Nothing has been implemented or committed yet.

- **`docs/adr/0001-reservations-expire-lazily.md`**: a reservation counts as expired as soon as the clock reaches `expires_at`, with no background sweeper. It also notes that a stored `ACTIVE` status can't be trusted without comparing `expires_at` to the clock, and that expiry only applies to active reservations.
- **`docs/adr/0002-reservations-hold-partially-orders-do-not.md`**: reserve holds whatever is available, while `place_order` stays all-or-nothing. It also notes that a retry is matched on what the cart *asked for*, and warns against later making the two behave the same without asking you.
- **`.scratch/stock-reservations/spec.md`**: your answers to Q12–Q14 are now recorded as confirmed, with links to both decision records. The status stays `ready-for-agent`.
- **`GLOSSARY.md`**: unchanged since the grilling round.

Next step is implementing from the spec. I'd do it test-first through the public `InventoryService` API.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here's the proposed breakdown. I haven't written any ticket files yet; I'll publish once you approve it.

1. **Reserve stock and look up a Reservation**
   - **Blocked by:** none (can start immediately)
   - **Delivers:** `reserve` creates an ACTIVE Reservation with a `RES-` id and `expires_at` = now + TTL (constructor option, default 20 min). `get_reservation` returns it, or raises `ReservationNotFound`. Holds are partial (min of requested and Available, zero lines left out), and `InsufficientStock` names the first line when nothing can be held. Validation is strict and holds nothing on failure. Adds `reserved()`; `available` now subtracts it, so other reserves and `place_order` can't take reserved units. Adds the new models and errors and exports them. The idempotency key is accepted but replay isn't handled yet, so a retry creates a second Reservation until ticket 5.

2. **Reservations expire on their own**
   - **Blocked by:** 1
   - **Delivers:** at `now >= expires_at` an ACTIVE Reservation stops counting as Reserved and `get_reservation` reports EXPIRED, without any sweep call. Not expired one second before. A custom TTL is respected.

3. **Release a Reservation**
   - **Blocked by:** 2
   - **Delivers:** releasing an ACTIVE Reservation makes it RELEASED and frees its units immediately. RELEASED and EXPIRED come back unchanged. Releasing a CONFIRMED one raises `InvalidReservationState`; that last case is tested once ticket 4 lands, or in whichever of the two lands second.

4. **Confirm a Reservation into an Order**
   - **Blocked by:** 2
   - **Delivers:** confirming creates a PLACED Order for exactly the held units, and the units move from Reserved to Allocated with no stock re-check. Confirming again returns the same Order, even after `expires_at`. Confirming an expired Reservation raises `ReservationExpired`; a released one raises `InvalidReservationState`. Shipping or cancelling the Order leaves the Reservation CONFIRMED.

5. **Idempotent reserve**
   - **Blocked by:** 2
   - **Delivers:** the same key with the same request (warehouse plus requested items, ignoring key order) returns the original Reservation as it is now. That holds after a partial hold, after more stock arrives, and after expiry, with no top-up and no new expiry. The same key with a different request raises `IdempotencyConflict`. Validation runs before the key lookup, and a failed reserve doesn't use up its key.

6. **Reserved column in the stock report, plus README**
   - **Blocked by:** 1
   - **Delivers:** `StockRow` gets `reserved` as its last field, defaulting to 0, so every row adds up and the existing positional rows still compare equal. The README's Concepts section covers Reserved and the Reservation lifecycle.

Once 2 is done, tickets 3, 4 and 5 can run in parallel, and 6 can run any time after 1. I don't see any refactoring that needs to happen first: `place_order` already checks against `available()`, so it respects Reservations without changes.

Questions for you:
- **Granularity:** ticket 1 is the largest (models, errors, storage, reserve, availability). Is that size OK, or should partial holds and `InsufficientStock` become their own ticket after a full-hold-only ticket 1?
- **Blocking edges:** is it right to make 3, 4 and 5 all wait on expiry (2) so each can test its expired case from the start? The alternative is to block them only on 1 and add the expired cases later.
- **Merges:** should 6 fold into 1? It's small.

### [to-tickets] user

I'm approving the breakdown as proposed. It doesn't contradict anything I've told you.

- Granularity: keep ticket 1 as one piece. Partial holds are part of what reserve means.
- Blocking edges: yes, 3, 4 and 5 should all wait on 2.
- Merges: keep 6 separate.

Any sensible choice on these three is fine with me. Go ahead and write the tickets.

### [to-tickets] agent

I've written the six tickets as one file each under `.scratch/stock-reservations/issues/`, all marked `ready-for-agent`:

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Reserve stock and look up a Reservation | none (can start now) |
| 02 | Reservations expire on their own | 01 |
| 03 | Release a Reservation | 02 |
| 04 | Confirm a Reservation into an Order | 02 |
| 05 | Idempotent reserve | 02 |
| 06 | Reserved column in the stock report, plus README | 01 |

Once 02 is done, 03, 04 and 05 can be worked in parallel, and 06 can start any time after 01. The test that releasing a confirmed Reservation raises `InvalidReservationState` needs both 03 and 04. Both tickets say that whichever lands second adds it.

Nothing is implemented or committed yet. The spec, `GLOSSARY.md` and the two ADRs are new and uncommitted too. Next step is ticket 01.

### [implement-spec] operator

/implement-spec .scratch/stock-reservations/spec.md

### [implement-spec] agent

The stock reservations spec was already finished before this check fired, so there was nothing left to do. I've stopped the background check that was scheduled.

I confirmed the final state just now:
- `stock-reservations` is at `eb8d25c`, the working tree is clean, and all 87 tests pass.
- All six tickets and the spec are marked resolved.
- All implementer worktrees and ticket branches have been removed.

Nothing has been merged into `main`. The branch is ready for you to review and merge.
