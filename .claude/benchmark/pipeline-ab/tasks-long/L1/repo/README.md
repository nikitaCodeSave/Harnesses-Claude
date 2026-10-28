# lending

Circulation desk for the Elm Street public library: members, the catalogue of
titles and physical copies, and loans. Pure Python, no I/O; persistence is an
in-memory repository behind a small interface.

## Concepts

- **Title** — a catalogue entry (ISBN, material, replacement cost).
- **Copy** — one physical item of a title, identified by its barcode.
  `AVAILABLE` on the shelf, `ON_LOAN`, or `WITHDRAWN` for good.
- **Loan** — a copy lent to a member, from `borrowed_on` to `due_on`.
  Books go out for 21 days, DVDs for 7. The library is closed on Sundays, so a
  due date that would land on a Sunday moves to the Monday.
- **Members** are adults (up to 8 open loans) or children (up to 4).

## Conventions

- All time comes from an injected `Clock` (`FixedClock` in tests). Never call
  `date.today()` in package code.
- Money is `Decimal`, never float.
- Domain failures raise subclasses of `lending.errors.LendingError`.
- `LendingService` is the only thing that mutates state; circulation numbers
  live in `lending.policy`.

## Layout

```
src/lending/   clock, errors, models, policy, repository, service, reports
tests/         pytest suite (shared fixtures in conftest.py)
```

## Tests

```bash
python3 -m pytest -q
```
