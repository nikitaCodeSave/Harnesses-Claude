### [spec+build] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [spec+build] agent

I've read the package (service, repository, models, errors, reports, tests; 20 passing). Before I write the spec, here are the business-rule questions. Each one has a recommended default, so you can answer "all defaults" or override by number.

**Hold lifetime**
1. **How long does a hold last?** Default: 15 minutes from creation. It's configurable via an optional keyword argument (`InventoryService(repo, ledger, clock, hold_ttl=timedelta(...))`), so the existing 3-argument constructor still works. Holds can't be extended.
2. **The boundary:** a hold is expired once `now >= expires_at`. At exactly `expires_at`, it no longer holds stock and can't be confirmed.

**Reserve**
3. **All-or-nothing:** if any SKU is short, raise `InsufficientStock` and create nothing, the same as `place_order`. Validation reuses `UnknownWarehouse`, `UnknownSku`, `InvalidQuantity`, and `InvalidOrder` (for empty items).
4. **What counts as "available":** on-hand − PLACED allocations − active holds. That means `place_order` can't take stock that's held. Should `allocated()` (and the `allocated` column in the stock report) stay orders-only? Default: yes. Holds show up only through a lower `available`, and I won't add a report column.

**Idempotency**
5. **Same key, same request** (warehouse plus identical items): return the original reservation in its *current* state, even if it has since been confirmed, released, or expired. The key never creates a second hold, so a new checkout attempt needs a new key.
6. **Same key, different warehouse or items:** raise `IdempotencyConflict`.
7. **Failed attempts:** a `reserve` that fails (e.g. `InsufficientStock`) doesn't consume the key, so a retry after restock can succeed.
8. **Key scope:** keys are global, not per warehouse. An empty key is rejected (`InvalidOrder`, or say if you want something else).

**Confirm and release**
9. **Confirming an ACTIVE hold** creates a normal PLACED order (next `ORD-xxxx` ID, `placed_at` = now). Its allocation replaces the hold, so stock isn't counted twice. The reservation becomes CONFIRMED with `order_id` set. Confirm does **not** re-check availability, because the stock was already guaranteed. Is that OK even if a write-off reduced on-hand in the meantime?
10. **Retrying `confirm` on a CONFIRMED hold:** return the same order rather than raising, so cart retries are safe.
11. **Confirming an expired hold:** raise `ReservationExpired`. Confirming a RELEASED hold raises `InvalidReservationState`.
12. **Releasing:** an ACTIVE hold becomes RELEASED and returns the reservation. Releasing an already-RELEASED hold returns it unchanged. Releasing a CONFIRMED hold raises `InvalidReservationState`.
13. **Releasing an expired hold:** raise `ReservationExpired`, or quietly return it with status EXPIRED (it's already freed)? Default: return it as EXPIRED, with no error.
14. **Unknown reservation ID:** raise `ReservationNotFound` from get, confirm, and release.

**Shape and scope**
15. **Reservation IDs:** `RES-0001`, `RES-0002`, … (same style as orders).
16. **Non-goals:** extending or renewing holds, partial confirm or release, holds spanning multiple warehouses, persisting beyond the in-memory repository, and listing or reporting reservations.

### [spec+build] user

Overrides by number:

1. The hold lasts 20 minutes, not 15. `expires_at` is the creation time plus 20 minutes. A configurable TTL is fine as long as the default is 20 minutes.
2. Agreed. At exactly `expires_at` the hold is expired.
3. This one is wrong. Reservations are partial, not all-or-nothing. Each line holds as many units as are available right now, up to what was asked. A line with nothing available is left out of `items` entirely, not shown with 0. `InsufficientStock` is raised only when no line can hold anything, and then nothing is created. `place_order` stays all-or-nothing. Validation errors are as you listed, and a rejected request holds nothing, not even for its valid lines. Empty items can raise any `InventoryError`.
4. Agreed. `allocated()` stays orders-only and there's no new report column.
5. Agreed. The comparison uses the requested items, not what ended up held.
6. Agreed. This applies even if the original reservation is finished.
7. Agreed.
8. Agreed. Keys are global. For an empty key, any `InventoryError` is fine.
9. Mostly agreed, with one correction. Confirm creates a normal PLACED order for exactly the units held. After a partial hold, that means only the held units. Available doesn't change at confirm, and on-hand moves only when the order ships. I don't mind what happens if a write-off has reduced on-hand in the meantime.
10. Agreed. A repeated confirm returns the same order and creates nothing, even after the 20 minutes have passed.
11. Agreed.
12. Agreed.
13. Agreed. Releasing an expired hold returns it unchanged as EXPIRED, with no error.
14. Agreed.
15. Any ID format is fine.
16. Agreed.

Two more points:
- Reserve, release, expire and confirm never write to the ledger or change on-hand.
- `receive` and `adjust` are never blocked by holds. If a write-off leaves on-hand below the held amount, available shows 0 and the reservations stay as they are.

### [spec+build] agent

I wrote SPEC.md and built the reservations feature. The full test suite passes: the 20 original tests are unchanged and 49 new tests in `tests/test_reservations.py` cover every acceptance criterion.

```
$ python3 -m pytest -q
.....................................................................    [100%]
69 passed in 0.04s
```

**SPEC.md** contains the interface from your request copied verbatim, your answers turned into numbered, checkable criteria, and the non-goals. Each new test is tagged with the criterion it covers (`# R2`, `# C3`, …).

**How it behaves:**
- **No sweep job:** a hold counts against `available` only while its status is `ACTIVE` and the clock is before `expires_at`. Once the clock reaches `expires_at`, the stock is free again even if nobody touches the reservation. The status itself changes to `EXPIRED` the next time the reservation is read through `get_reservation`, confirm, release, or a repeated `reserve`.
- **Idempotency:** the repository keeps each key with the warehouse and items originally *requested*, so retries match on the request even when the hold was partial. A key is only recorded once a reservation is actually created, so a failed attempt doesn't use it up.
- **Confirm:** it creates the order the same way `place_order` does, but with exactly the held units and without re-checking stock. Available doesn't change, because the units stop being held and become allocated.
- **Hold length:** 20 minutes by default. It can be changed with the optional `hold_ttl=` argument, and `InventoryService(repository, ledger, clock)` still works as before.
- **Choices you left open:**
  - Reservation IDs look like `RES-0001`.
  - An empty request or an empty idempotency key raises `InvalidOrder`.
  - When no line can be held, `InsufficientStock` names the first requested SKU.
- **Where the changes are:** `models.py`, `errors.py`, `repository.py` and `service.py`, plus the new exports in `__init__.py` and a "Held" section in the README.

**One thing to know:** `reserve` returns the stored reservation object itself, the same way orders already work. A copy the caller is still holding won't change to `EXPIRED` on its own; calling `get_reservation` returns the current status.

Nothing is committed; the changes are in the working tree.
