Members who move away ask us to close their accounts; today staff just stop using them, and they stay
on the register. Add closing an account.

Interface (other code will call exactly this):
- `LendingService.close_account(member_id: str) -> Member` in `src/lending/service.py` — closes the
  account and returns the member.
- `Member` in `src/lending/models.py` gets `closed_on: date | None` (default `None`).
- Add `AccountClosed(LendingError)` and `CannotClose(LendingError)` to `src/lending/errors.py`;
  unknown members keep raising `MemberNotFound`.
