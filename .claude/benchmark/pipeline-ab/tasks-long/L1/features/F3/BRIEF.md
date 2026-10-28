Members ask to keep books longer, and staff do it by returning and re-checking the copy out, which
breaks the loan history. Add renewals.

Interface (other code will call exactly this):
- `LendingService.renew(loan_id: str) -> Loan` in `src/lending/service.py` — renews the open loan in
  place (same `loan_id`) and returns it.
- `Loan` in `src/lending/models.py` gets a field `renewals: int` (default `0`): how many times the
  loan has been renewed.
- Add `RenewalRefused(LendingError)` to `src/lending/errors.py` for renewals that can't be granted;
  unknown loan ids keep raising `LoanNotFound`, and keep using the other existing error classes where
  they already fit.
