Staff declare losses by hand, and they forget: some loans have been overdue for months. Add a daily
job that declares long-overdue loans lost.

Interface (other code will call exactly this):
- `LendingService.mark_long_overdue() -> list[Loan]` in `src/lending/service.py` — the daily job:
  declares lost every loan that has been overdue too long, and returns the loans it declared lost.
