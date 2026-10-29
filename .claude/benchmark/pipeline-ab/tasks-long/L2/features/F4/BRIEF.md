Copies that never come back stay on a member's record as open loans for ever, and nobody pays for
them. Add declaring a loan lost, and taking back a lost copy that turns up after all.

Interface (other code will call exactly this):
- On `LendingService` in `src/lending/service.py`: `declare_lost(loan_id: str) -> Loan` — staff declare
  the loan's copy lost; returns the loan. `found_copy(copy_id: str) -> Copy` — a copy declared lost has
  turned up; returns the copy.
- In `src/lending/models.py`: `Loan` gets `lost_on: date | None` (default `None`), the day the loan was
  declared lost; new member `CopyStatus.LOST`.
- Add `NotLost(LendingError)` to `src/lending/errors.py` for `found_copy` on a copy that isn't lost;
  unknown ids keep raising `LoanNotFound` / `CopyNotFound`, and keep using the existing error classes
  where they already fit.
