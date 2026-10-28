# T2 — product owner's private notes (never shown to coding agents)

Answer questions from these notes only. Reveal a rule when a question touches
its topic; do not volunteer the whole list. If asked about something in the
"Don't care" list, say any sensible behaviour is fine.

## Rules

**N1. What "available" means.** Available = on-hand − units allocated to
PLACED orders − units held by ACTIVE reservations, per SKU per warehouse,
never below 0. A hold in one warehouse does not touch any other warehouse.

**N2. A hold is not a stock movement.** Reserving, releasing, expiring and
confirming never write to the ledger and never change on-hand. On-hand still
moves only by receipts, adjustments and shipments.

**N3. Partial holds, not all-or-nothing.** *(commonly guessed wrong)* Each
line holds as many units as are available right now, up to what was asked.
A line with nothing available is left out of the reservation entirely (it
does not appear in `items`, not even with 0). Only when no line can hold
anything does `reserve` fail, with the existing `InsufficientStock`, and then
nothing is created. Reason: "only 3 left — we've held them for you" converts
better than an error; the cart shows the shortfall itself by comparing
`items` with what it asked for.

**N4. Bad input.** Validated exactly like `place_order`: unknown warehouse →
`UnknownWarehouse`, unknown SKU → `UnknownSku`, zero or negative quantity →
`InvalidQuantity`. A rejected request holds nothing, not
even for its valid lines.

**N5. Expiry: 20 minutes.** *(commonly guessed wrong)*
A hold lasts 20 minutes from the moment it was created (checkout data: 95% of
payments finish within 18 minutes). `expires_at` = creation time + 20 min.
From `expires_at` on — that instant included — the reservation is EXPIRED and
its units are available again, with no sweep call. Expired reservations stay
retrievable with status EXPIRED. Only ACTIVE reservations expire; CONFIRMED
and RELEASED ones never change on their own.

**N6. Confirm = becomes a normal order; retries are safe.** *(commonly
guessed wrong)* Confirming an ACTIVE reservation places an ordinary PLACED
order in the same warehouse for exactly the units held (after a partial hold,
only those). The reservation becomes CONFIRMED and its `order_id` is that
order's id. The hold turns into the order's allocation: available does not
change at confirm, and on-hand moves only when the order ships. The payment
service retries confirm, so confirming an already-CONFIRMED reservation
returns the same order and creates nothing — at any time, even after the 20
minutes have passed.

**N7. Other transitions.** Confirm of an EXPIRED reservation (including one
that has just lapsed) → `ReservationExpired`. Confirm of a RELEASED one →
`InvalidReservationState`. Release of a CONFIRMED one →
`InvalidReservationState`. Release is retry-safe too: releasing an
already-RELEASED or an EXPIRED reservation is a no-op that returns it
unchanged (status stays RELEASED / EXPIRED, no error).

**N8. Idempotency keys.** A key is unique across the whole system, all
warehouses. A repeat `reserve` with the same key and the same request (same
warehouse and same *requested* items — what was asked for, not what ended up
held) returns the existing reservation in its current state, whatever that
state is. It creates no new hold and does not move `expires_at`. Same key with
a different warehouse or different items → `IdempotencyConflict`, even if the
original reservation is finished. A `reserve` call that fails leaves no trace:
its key can be used again.

**N9. Direct orders compete with holds.** `place_order` can only take
available stock (N1); otherwise `InsufficientStock`, all-or-nothing, as
today. Partial filling (N3) is for reservations only.

**N10. Physical stock is the truth.** `receive` and `adjust` are never blocked
by holds. If a write-off leaves on-hand below what is held, available shows 0
and the reservations stay as they are.

**N11. Unknown reservation id.** `get_reservation`, `confirm_reservation` and
`release_reservation` raise `ReservationNotFound`.

## Don't care (any sensible behaviour is fine — not tested)

- Format of reservation ids; id of the order created by confirm.
- Error messages, and which SKU an `InsufficientStock` names.
- Empty `items`, non-integer or boolean quantities, empty idempotency key —
  any `InventoryError` is fine.
- What `items` shows on a RELEASED or EXPIRED reservation.
- Confirm after a write-off has pushed on-hand below the hold (succeed or
  `InsufficientStock`, either is fine).
- What a repeated confirm returns once that order was cancelled or shipped,
  as long as it creates no new order.
- Whether expiry is stored as a status change or computed on read.
- Which error wins when a reused key also carries invalid input (validation
  error or `IdempotencyConflict`).
- Ledger reason/ref values; whether the stock report shows held units.
- Extra fields, methods or constructor options (e.g. a configurable TTL) are
  fine as long as the defaults follow these notes.
