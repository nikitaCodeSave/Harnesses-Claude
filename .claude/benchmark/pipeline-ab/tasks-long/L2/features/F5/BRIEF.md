Members join once and stay on the register for ever, including people who moved away years ago.
Memberships now last a year and have to be renewed.

Interface (other code will call exactly this):
- `Member` in `src/lending/models.py` gets `expires_on: date | None` (default `None`): the last day the
  membership is valid. `register_member` keeps its signature and sets it.
- `LendingService.renew_membership(member_id: str) -> Member` in `src/lending/service.py` — renews the
  membership and returns the member.
- Add `MembershipExpired(LendingError)` and `MembershipRenewalRefused(LendingError)` to
  `src/lending/errors.py`; unknown members keep raising `MemberNotFound`.
