### [F1:spec+build] operator

Late returns cost nothing today, so DVDs come back weeks late. Add overdue fines and a member
account to the lending package: a late return charges the member, staff can add a manual charge,
members can pay, and members who owe too much can't borrow.

Interface (other code will call exactly this), all on `LendingService` in `src/lending/service.py`:
- `return_copy(copy_id)` keeps its signature and return value; a late return now also charges the fine.
- `balance(member_id: str) -> Decimal` — what the member owes right now.
- `add_charge(member_id: str, amount: Decimal, reason: str) -> Decimal` — manual staff charge; returns the new balance.
- `pay(member_id: str, amount: Decimal) -> Decimal` — records a payment; returns the new balance.
- Add to `src/lending/errors.py`: `AccountBlocked(LendingError)`, raised by `checkout` when the member
  owes too much, and `InvalidAmount(LendingError)` for amounts that can't be accepted. Unknown members
  keep raising `MemberNotFound`.

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [F1:spec+build] agent

Before I write the spec I need some answers. I've read the code (`service.py`, `policy.py`, `models.py`, tests). `GLOSSARY.md` and `docs/adr/` don't exist yet, so I'll create them. Each question has a suggested default. Reply "default" to accept it, or give your own answer.

**Fines**
1. **Rate.** What is the fine per day overdue, and does it depend on material? *Default: books €0.20/day, DVDs €1.00/day.* What currency or symbol should I use in docs? The code just uses `Decimal`.
2. **Which days count.** Should the library's closed Sundays count toward days late? *Default: calendar days, the same way `overdue_report` counts them. Returning on the due date costs nothing; one day after costs one day.*
3. **Cap.** Is there a maximum fine per loan? *Default: capped at the title's `replacement_cost`, so a late DVD never costs more than buying a new one.*
4. **Children.** Are child members fined, and at the same rate? *Default: same rules for everyone.*
5. **When it's charged.** "What the member owes right now": does `balance` include fines still building up on items that are out and overdue? Or are fines charged only when the item comes back, as your request implies? *Default: only at return. An overdue DVD that hasn't come back adds nothing to the balance until it's returned.*

**Blocking**
6. **Threshold.** At what balance does `checkout` raise `AccountBlocked`? Does the block start at that amount, or only above it? *Default: blocked when the balance is €10.00 or more, for all member categories.*
7. **Scope.** Is checkout the only action that's blocked? *Default: yes. Returns, payments and charges always work for a blocked member.*

**Payments and charges**
8. **Overpayment.** If someone pays more than they owe, should that raise `InvalidAmount`, or be kept as credit? *Default: `InvalidAmount`. The balance never goes below zero.*
9. **Invalid amounts.** Which amounts get `InvalidAmount`? *Default: zero, negative, more than 2 decimal places, and anything that isn't a `Decimal`, such as a float or int. That follows the "money is always Decimal" rule.*
10. **Reason.** Must `add_charge` have a non-empty `reason`? If so, what error does a blank one raise? *Default: it's required, and a blank reason raises `InvalidAmount`… which is a poor fit. Do you prefer a plain `ValueError`, or not checking it at all?*
11. **Waivers and history.** Should staff be able to waive or refund a charge, and should there be a way to view a member's list of charges and payments? *Default: both are non-goals for now. Charges and payments are still recorded individually with date and reason, so a history view could be added later.*

### [F1:spec+build] user

1. Books 0.25 per late day, DVDs 1.00 per late day. Currency: I don't mind, use whatever you like in the docs.
2. Not the default: Sundays don't count (we're closed, nobody could return a copy that day). Late days are the days after the due date up to and including the return day, minus Sundays. Example: book due Mon 23 March, back Mon 30 March = 7 days minus Sunday the 29th = 6 late days = 1.50. Back on or before the due date: no fine.
3. Default is right: the fine for one loan never exceeds the title's replacement cost.
4. Not the default: children are never fined. Their late return is processed normally and nothing is charged.
5. Default is right: fines are charged only when the copy comes back, and each late return adds its own fine.
6. Default is right: 10.00 or more is blocked (exactly 10.00 is blocked).
7. Default is right.
8. Default is right: a payment can't exceed what they owe; partial payments are fine.
9. Default is right on zero, negative and more than 2 decimal places: a payment or charge must be positive and in whole cents. I don't mind how you treat floats/ints.
10. I don't mind, pick whatever you think is sensible.
11. Default is right, both are non-goals.

Also, for later, where the service is heading:
- Holds: a member who owes 5.00 or more can't place a hold; refuse it with AccountBlocked. That bar is lower than the 10.00 borrowing bar on purpose: a hold ties up a copy for someone who already owes us.
- No-show fee: when a copy is set aside for a member's hold and they don't collect it within the pickup time, they get a 1.00 fee on the same balance as fines. It counts toward the blocks like any fine, and children never pay it.
- Renewals will come after holds. Renewing a loan that is already overdue must charge the late fine accrued so far as part of the renewal, counted exactly as if the copy had been returned on the renewal day, with the usual rates, cap and child exemption. After the renewal, lateness is counted against the new due date. Lateness before a renewal must never just disappear.

### [F1:spec+build] agent

Overdue fines and member accounts are built, and the full test suite passes.

```
$ python3 -m pytest -q
........................................................................ [ 94%]
....                                                                     [100%]
76 passed in 0.04s
```

That's 19 existing tests plus 57 new ones in `tests/test_accounts.py`. Each new test's name cites the spec criterion it covers (A1–A3, F1–F7, B1–B4, C1–C3, P1–P3, M1–M2, K1–K6). Your example is a test: book due Mon 23 March, returned Mon 30 March, gives 6 late days and €1.50.

**What changed**
- **`SPEC.md`**: what and why, the acceptance criteria and non-goals. Your interface is copied in word for word.
- **`src/lending/service.py`**:
  - `balance`, `add_charge` and `pay` are new.
  - `return_copy` now charges the fine for a late return. Its signature and return value are unchanged.
  - `checkout` raises `AccountBlocked` when the balance is €10.00 or more.
- **`src/lending/errors.py`**: adds `AccountBlocked` and `InvalidAmount`, plus `InvalidReason` (see below).
- **`src/lending/policy.py`**: the rates, the €10.00 borrowing threshold, and the late-day and fine calculations.
- **`src/lending/models.py` and `src/lending/repository.py`**: each charge, fine and payment is stored as its own record, linked to its loan where there is one. The balance is worked out from these records.
- **`GLOSSARY.md`** and **`docs/adr/0001`–`0005`** are new, as `CLAUDE.md` asks. ADRs 0003–0005 record your "for later" rules:
  - the €5.00 threshold for placing holds;
  - the €1.00 no-show fee, which children don't pay;
  - renewing an overdue loan charges the fine so far, counted as if it had been returned that day.

  The fine calculation takes a "count up to this day" date, so renewals can reuse it unchanged.

**Choices I made where you left it open**
- A blank or whitespace-only `reason` raises the new `InvalidReason(LendingError)`. That keeps every refusal under `LendingError`.
- Floats, strings and NaN/infinity raise `InvalidAmount`. Whole numbers are accepted as whole euros, so `3` means €3.00.
- Manual staff charges apply to children too; only fines skip them. Tell me if staff shouldn't be able to charge children at all.

**One open question for when renewals are built** (written up in ADR 0005): is the replacement-cost cap per charge, or across all fines on the same loan? Today a loan gets at most one fine, so both readings give the same result.

Nothing is committed; the changes are in the working tree.

### [F2:spec+build] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [F2:spec+build] agent

I've read the glossary, the five ADRs, the existing SPEC and the code. Several hold rules are already settled. I'll follow them without asking again:

- **Hold bar** (ADR 0003): `place_hold` raises `AccountBlocked` when the balance is 5.00 or more.
- **No-show fee** (ADR 0004): 1.00, an account entry of kind `no_show`, charged when expiry is detected (that's `expire_holds`). Children never pay it. It counts toward both bars.

Some things are still open. Each question has my suggested answer, so you can just reply "all defaults" or change the ones you disagree with.

**Pickup time**
1. How long is the pickup time? *Default: 7 calendar days from the day the copy is set aside. If that lands on a Sunday, it moves to Monday (same as due dates). The member can still collect on the `pickup_by` day, and the hold expires from the next day.*
2. If the daily job runs late (say it skipped a day), when does the next person's pickup time start? *Default: on the day the copy is handed on to them, not the day the previous hold should have expired.*

**Placing a hold — when is it refused with `HoldNotAllowed`?**
3. If a copy of the title is on the shelf: *refuse. Holds are only for titles with every copy out.* (Copies set aside for someone else's hold count as out.)
4. If the member already has an active (waiting or ready) hold on the same title: *refuse.*
5. If the member already has a copy of that title on loan: *refuse.*
6. If the title has no copies that can circulate (none, or all withdrawn): *refuse, since nothing will ever come back.*
7. Should there be a cap on active holds per member? *Default: no cap for now.*
8. Can children place holds? *Default: yes, the same as adults, just never charged the fee.*

**Collecting**
9. If someone else tries to check out a copy set aside for a hold: *`CopyNotAvailable` (existing error).* When the hold's member checks it out, the hold becomes `FULFILLED`. The normal checkout rules still apply (borrowing bar, loan limit). If one of them refuses the checkout, the hold stays `READY`.
10. Suppose the member checks out a different copy of the same title while their hold is `READY`. *Default: the hold is still FULFILLED, and the set-aside copy goes to the next person in line, or back to the shelf.*

**Cancelling and expiry**
11. Cancelling a `READY` hold: *no fee. The copy goes straight to the next person in line, or back to the shelf.* Cancelling a hold that is already fulfilled, cancelled or expired: *`HoldNotAllowed`.*
12. Can a `WAITING` hold ever expire, e.g. after months in the queue? *Default: no. Only ready holds that nobody collected expire. Waiting holds stay until cancelled.*

**Queries**
13. For `holds_for(isbn)`, "active" means `WAITING` plus `READY`, in the order they were placed. An unknown ISBN raises `TitleNotFound`. An unknown member in `place_hold` raises `MemberNotFound`. *Agree?*

### [F2:spec+build] user

All defaults are fine. Your answers match how we run things.

Also, for later: renewals are next on our list. While anyone is still waiting in the queue for a title, loans of that title can't be renewed. A hold that is already ready on the hold shelf doesn't count, because that person already has their copy. Renewals are also only for members who are paid up. If the balance shows anything at all owed when they ask, they can't renew until they've paid.

### [F2:spec+build] agent

Holds are built, and the test suite passes.

```
$ python3 -m pytest -q
........................................................................ [ 54%]
...........................................................              [100%]
131 passed in 0.09s
```

That's the 76 tests that were already there plus 55 new ones in `tests/test_holds.py`. Each new test is named after the spec criterion it covers (HP, HQ, HC, HX, HE, HU), and every criterion in `SPEC.md` has at least one test.

**What I wrote**
- **`SPEC.md`**: the holds spec, with your interface copied in word for word, the acceptance criteria and the non-goals. It replaces the fines spec, which I moved to `docs/specs/overdue-fines.md` because `tests/test_accounts.py` cites its criteria. I updated that pointer and the one in the README.
- **Code**: the four new methods on `LendingService`, plus `Hold`, `HoldStatus`, `CopyStatus.ON_HOLD_SHELF`, `HoldNotAllowed` and `HoldNotFound`. `checkout` and `return_copy` keep their signatures. The new numbers (pickup time of 7 days, no-show fee of 1.00, hold bar of 5.00) are in `policy.py`. I also added `EntryKind.NO_SHOW` for the fee, as ADR 0004 says.
- **ADR 0006**: the holds rules you confirmed.
- **ADR 0007**: your renewal rules, for later. Renewal is refused while anyone is waiting in the queue; holds already on the hold shelf don't count. Renewal is also refused if the member owes anything at all.
- **Glossary and README**: new terms (hold queue, ready and waiting holds, hold shelf, pickup time, paid up), and "planned" removed from the terms that now exist.

**Decisions to check**
1. **New copies go to the queue.** You didn't ask about this. A copy added with `add_copy` while people are waiting is set aside for the first in line, the same as a returned copy. Otherwise someone walking in could borrow it ahead of the queue. It's criterion HQ5, and easy to drop if you'd rather not.
2. **Paid-up rule versus overdue fines (ADR 0007).** "Owes anything when they ask" is checked before the renewal charges the fine for days already late. A paid-up member can therefore renew an overdue loan, leaves owing that fine, and can't renew again until it's paid. Also, this rule refuses any balance above 0.00. It can't use the usual "balance at or above the bar" check with a bar of 0.00, because that would block everyone. Please confirm this reading before renewals are built.

Nothing is committed. Running the tests also changed the `__pycache__/*.pyc` files, which are tracked in git, so they show as modified in `git status`.

### [F3:spec+build] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [F3:spec+build] agent

I've read the glossary, all seven ADRs, the earlier specs and the code. The suite is green (131 passed). ADRs 0005 and 0007 already decide a lot about renewals, so I won't ask about these:

- **Already decided:** a waiting hold on the title blocks a renewal, but a ready hold doesn't. Only a member whose balance is exactly 0.00 may renew. Renewing an overdue loan charges the fine so far, counted as if the copy came back that day, with children exempt. Every late day is fined exactly once. All checks happen before anything changes, so a refused renewal changes nothing.

These are still open. Each has my recommendation:

**1. New due date.** What is it counted from?
   - (a) *Recommended:* the renewal day, i.e. one full loan period (book 21 days, DVD 7) from today, moved past a Sunday, the same as a fresh checkout. This fits the overdue-fine rule: lateness up to today is fined now, and later lateness counts against the new date.
   - (b) The old due date plus one loan period. Renewing early gives the member more time, but a loan overdue by more than one period would still be overdue after the renewal.

**2. Limit on renewals.** Is there a maximum number per loan? If so, how many? (Is 2 a common choice?) Or no limit, since the queue rule already protects other members?

**3. How early can a member renew?** With (1a), renewing on the day they borrow does almost nothing. Is that fine, or is there a window, e.g. only in the last N days before the due date?

**4. Replacement-cost cap.** ADR 0005 left this open: is the cap per charge, or across all fines on one loan (renewal fines plus the return fine)?
   - *Recommended:* across the whole loan, so a loan never costs more in fines than replacing the copy.

**5. Error classes.**
   - Paid-up rule: ADR 0007 says `AccountBlocked` fits. Should I use it with `bar = 0.00`? Or should every refusal be `RenewalRefused`?
   - Waiting hold, renewal limit reached, and loan already returned: I'd use `RenewalRefused` for all three. `NoOpenLoan` is about a copy id, not a loan id. Agree?

**6. Children.** Same rules as adults? Since they're never fined, an overdue child's loan renews without a charge.

**7. Anything else:** other limits by material (e.g. no DVD renewals), and should the desk see when a loan was last renewed? The interface only adds `renewals`, so I'd leave everything else out unless you want it.

### [F3:spec+build] user

1. Go with (a). A renewal gives a fresh full loan period counted from the renewal day, exactly like a checkout made that day. For example, a book due Mon 23 March and renewed Thu 19 March is due Thu 9 April.
2. Yes, at most 2 renewals per loan. The third request is refused with RenewalRefused.
3. There is a window. A loan can be renewed from 5 days before its due date onwards. If it's due Mon 23 March, it's renewable from Wed 18 March, and on 17 March it's refused with RenewalRefused.
4. I don't mind, so take your recommendation of a cap across the whole loan.
5. For the paid-up rule, follow what ADR 0007 settled and use AccountBlocked. I agree with RenewalRefused for the waiting hold, the renewal limit and a loan that has already been returned. An unknown loan id stays LoanNotFound.
6. I don't mind, so take your recommendation that children follow the same rules as adults.
7. DVDs can't be renewed, and they are refused with RenewalRefused. Books can be renewed. I don't need a 'last renewed' date for the desk, so leave everything else out.

### [F3:spec+build] agent

Renewals are built and the full suite passes.

```
$ python3 -m pytest -q
........................................................................ [ 42%]
........................................................................ [ 84%]
..........................                                               [100%]
170 passed in 0.07s
```

That's the 131 existing tests, unchanged, plus 39 new ones in `tests/test_renewals.py`. Each new test is named after the criterion it checks. Every criterion in `SPEC.md` has at least one test except U1 ("existing behaviour unchanged"), which the 131 existing tests cover.

**Spec.** `SPEC.md` copies your interface word for word. It has acceptance criteria for a successful renewal, the limit and window, refusals, overdue loans and the fine cap, plus a non-goals list. The previous holds spec moved to `docs/specs/holds.md`, the same way the fines spec was archived last time.

**How it behaves**
- `renew(loan_id)` updates the same loan rather than creating a new one. The due date becomes whatever a checkout that day would get, and `renewals` goes up by one.
- Refusals:
  - `LoanNotFound` for an unknown loan id.
  - `AccountBlocked` if the member owes anything at all; it reports a bar of 0.00.
  - `RenewalRefused` for a loan already returned, a DVD, a third renewal, more than 5 days before the due date, or anyone waiting for the title.
- A refused renewal changes nothing: due date, renewal count, holds and balance all stay as they were.
- Renewing an overdue loan charges the fine so far as one fine entry linked to the loan. After that, lateness counts from the new due date, so each late day is fined once.
- The cap: all fines on one loan together never exceed the replacement cost. The fine calculation now takes into account what the loan has already been fined. Loans that are never renewed are fined exactly as before.

**Project knowledge**
- Your answers are recorded in `docs/adr/0008-renewal-terms.md`.
- I added a one-line note to ADRs 0005 and 0007 saying where their open questions were answered.
- `GLOSSARY.md` now defines Renewal, Renewal limit and Renewal window, and the Replacement cost entry describes the per-loan cap.
- `README.md` has a short Renewal section.

**Worth knowing**
- If several refusals apply at once, the spec doesn't say which error wins. In practice the order is: returned, DVD, limit, window, waiting hold, then balance.
- Renewal days aren't restricted to open days, so a renewal on a Sunday works and its due date moves to the Monday.
- The `__pycache__/*.pyc` files are committed to git, so running the tests rewrote them and they now show as modified.
- Nothing is committed yet.
