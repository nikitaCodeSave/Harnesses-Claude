When every copy of a title is out, members can only keep asking at the desk. Add holds: a member
joins the queue for a title; a returned copy is set aside for the first person in line, who gets a
few days to pick it up; a daily job clears holds nobody collected.

Interface (other code will call exactly this):
- On `LendingService` in `src/lending/service.py`: `place_hold(member_id: str, isbn: str) -> Hold`,
  `cancel_hold(hold_id: str) -> Hold`, `expire_holds() -> list[Hold]` (the daily job; returns the holds it
  expired), `holds_for(isbn: str) -> list[Hold]` (active holds on the title, first in line first).
  `return_copy` and `checkout` keep their signatures.
- In `src/lending/models.py`: dataclass `Hold(hold_id: str, member_id: str, isbn: str, placed_on: date, status: HoldStatus, copy_id: str | None, pickup_by: date | None)`;
  enum `HoldStatus` with `WAITING, READY, FULFILLED, CANCELLED, EXPIRED`; new member `CopyStatus.ON_HOLD_SHELF`.
- Add `HoldNotAllowed(LendingError)` and `HoldNotFound(LendingError)` to `src/lending/errors.py`; keep using the existing error classes where they already fit.
