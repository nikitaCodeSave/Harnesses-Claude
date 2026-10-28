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

I've read the package (no `GLOSSARY.md` or `docs/adr/` exist yet; baseline is 18 tests passing). The interface is fixed. What's left are the business rules, and only you can decide those. I've put a default after each question, so you can answer "default" or give your own value.

**Fine amount**
1. **Rate per day.** Is it per material? I'd suggest **books $0.25/day and DVDs $1.00/day**.
2. **Children.** Same rates as adults, a lower rate, or no fines at all? Default: **same rates**.
3. **Which days count.** All calendar days late, or only days the library is open (skip Sundays)? Default: **calendar days**, which matches how the overdue report counts. Is there a grace period? Default: **none**, so returning one day late means one day's fine.
4. **Cap.** Is the fine for a single loan capped? Default: **capped at the title's replacement cost**, which the catalogue already stores.

**What "owes" means**
5. **When the fine is charged.** You said a late return charges the fine. While an overdue DVD is still out, should `balance` already include the fine that's building up, or only include it once the DVD comes back? Default: **only on return**. The overdue report already covers items still out. The catch is that someone who keeps a DVD forever is never blocked by its fine; they're only held back by their loan limit.
6. **Block threshold.** How much can a member owe before `checkout` raises `AccountBlocked`? Default: **blocked when the balance is $10.00 or more**. Is it the same for children?

**Amounts and payments**
7. **Overpayment.** If someone owes $3 and pays $5, should I refuse it with `InvalidAmount`, or keep a $2 credit (negative balance)? Default: **refuse**. The front desk gives change; the account doesn't hold credit.
8. **What counts as an invalid amount.** For both `pay` and `add_charge`, I'd raise `InvalidAmount` for zero, negative amounts, and anything with more than 2 decimal places (e.g. `0.005`). Should a non-`Decimal` value such as a float also be rejected? Default: **yes**. Should a manual charge require a non-blank `reason`? Default: **yes**, rejected with `InvalidAmount`.
9. **Records.** Should charges and payments be kept as an itemised ledger internally, so a statement could be added later, even though nothing in the interface reads them yet? Default: **yes, store a ledger. Showing a statement is a non-goal for now.**

**Scope**
10. Default **non-goals**: waiving or reversing charges, refunds, lost-item charges, fines on renewals (renewals don't exist yet), and rate changes over time. Is anything on that list something you actually want now?

### [F1:spec+build] user

1. Yes, per material: books 0.25/day, DVDs 1.00/day.
2. Children are never fined; their late return is processed normally, nothing charged.
3. Don't count Sundays (we're closed, nobody could return it) — this differs from the overdue report. Late days = days after the due date up to and including the return day. No grace period; on or before the due date = no fine. Example: book due Mon 23 March, back Mon 30 March = 7 days minus Sunday the 29th = 6 late days = 1.50.
4. Yes, capped per loan at the title's replacement cost.
5. Only on return. A loan overdue but still out adds nothing yet; each late return adds its own fine and they add up.
6. Blocked at 10.00 or more (exactly 10.00 is blocked). I haven't set a separate threshold for children, so use the same. Returning and paying always work even while blocked.
7. Refuse with InvalidAmount; we don't keep credit. A payment must be positive, whole cents, and not more than what's owed; pay returns what is still owed.
8. Positive and whole cents, otherwise InvalidAmount, for both pay and add_charge. Manual charges go on the same balance as fines and count toward the block. I don't mind about floats or a blank reason — use your defaults. A refused payment/charge leaves the balance unchanged, and a refused checkout creates no loan and leaves the copy on the shelf.
9. Don't mind how you store it; a ledger is fine.
10. Those non-goals are fine for now.

Also, for later, where the service is heading:
- Holds: a member who owes 5.00 or more can't place a hold — refuse with AccountBlocked. That bar is lower than the 10.00 borrowing bar on purpose: a hold ties up a copy for someone who already owes us.
- No-show fee: if a copy is set aside for a member's hold and they don't collect it within the pickup time, they get a 1.00 fee on the same balance as fines (counts toward the blocks like any fine). Children never pay it.
- Renewals will come after holds. Renewing a loan that is already overdue must charge the late fine accrued so far as part of the renewal — counted exactly as if the copy had been returned on the renewal day, with the usual rates, cap and child exemption. After the renewal, lateness is counted against the new due date. Lateness before a renewal must never just disappear.

### [F1:spec+build] agent

Overdue fines and member accounts are built, and the full test suite passes. The spec is in `SPEC.md`, with your interface copied in word for word.

```
$ python3 -m pytest -q
........................................................................ [ 97%]
..                                                                       [100%]
74 passed in 0.02s
```

That's the original 18 tests, 55 new ones in `tests/test_accounts.py` (named after the spec criterion each one checks, e.g. `test_17_exactly_ten_blocks_borrowing`), and one new test of the late-day count in `tests/test_loans.py`.

**What it does now**
- **Late returns:** an adult's late return charges 0.25 per late day for books and 1.00 for DVDs. Sundays don't count, and one loan's fine never exceeds the title's replacement cost. Your example (due Mon 23 March, back Mon 30 March) comes to 1.50. Children are never fined.
- **Charges and payments:** `balance`, `add_charge` and `pay` work as you specified. Amounts must be positive and in whole cents. A payment can't be more than what's owed, and a refused charge or payment leaves the balance unchanged. Floats, ints and blank reasons are refused with `InvalidAmount`, as in my defaults.
- **Blocking:** `checkout` raises `AccountBlocked` once a member owes 10.00 or more, leaving no loan and the copy still on the shelf. Returning and paying still work while blocked.

The fine rules live in one function, `late_fine` in `src/lending/policy.py`, so renewals can charge through the same rules later.

**Project docs**
- `GLOSSARY.md` is new and includes "late day" (open days only) as separate from the overdue report's calendar-day count.
- I added a short Account entry to the README.
- New ADRs in `docs/adr/`:
  - **0001** – fine rules.
  - **0002** – the single balance, no credit, and the 10.00 borrowing block.
  - **0003** – your "for later" hold rules: holds refused at 5.00 or more, and the 1.00 no-show fee that children don't pay.
  - **0004** – your "for later" renewal rule: an overdue renewal charges the fine so far, so lateness never disappears.

**Decision for you (before renewals are built):** if an overdue loan is renewed and then returned late again, is the replacement-cost cap per charge or for the whole loan? Read literally ("as if returned on the renewal day"), each charge is capped separately, so the total could go over the replacement cost. I noted this as open in ADR 0004 rather than choosing.

Nothing is committed yet. The run also created untracked `__pycache__/` folders, and the repo has no `.gitignore` for them.

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

I've read the code, `GLOSSARY.md` and all four ADRs. All 74 tests pass. ADR 0003 already settles two things:

- A balance of **5.00 or more** blocks placing a hold, with `AccountBlocked`.
- A **1.00 no-show fee** is charged when a hold isn't collected. Children are exempt.

It leaves two questions open: how long the pickup time is, and what triggers the fee. Your request suggests `expire_holds` is the trigger. Below are the questions I need answered before I can write the spec. Each one has my suggested answer, so you can reply "all defaults" or list the numbers you want changed.

**Pickup and expiry**
1. **Pickup time:** how many days, and do Sundays count? *Suggest: 3 open days, counted from the day the copy is set aside. `pickup_by` is the last day to collect, so a hold expires only once today is after `pickup_by`.*
2. **No-show fee trigger:** does `expire_holds` charge the 1.00 fee (children exempt) to each READY hold it expires? *Suggest: yes, so the ADR's "clock-driven sweep" question is settled.*
3. **After a hold expires or a READY hold is cancelled:** the copy goes to the next WAITING hold (READY, with a new `pickup_by` counted from today). If nobody is waiting, it goes back on the shelf as AVAILABLE. *Suggest: yes.*
4. **Do WAITING holds ever expire?** For example, after 6 months unfilled. *Suggest: no; out of scope.*

**Placing a hold**
5. **Holds only when no copy is AVAILABLE?** If a copy is on the shelf, refuse with `HoldNotAllowed`. Copies on loan or on the hold shelf for someone else count as "out". *Suggest: yes.*
6. **Title with no copies in circulation** (none added, or all withdrawn): *Suggest: refuse with `HoldNotAllowed`, since no copy will ever come back.*
7. **Duplicates:** a member already has an active (WAITING/READY) hold on the title. *Suggest: `HoldNotAllowed`.* And if they currently have a copy of that title on loan? *Suggest: also `HoldNotAllowed`.*
8. **Limit on holds per member?** *Suggest: none for now (non-goal).*
9. **Children** can place holds under the same 5.00 bar. *Suggest: yes (ADR 0003 makes no distinction).*
10. **Check order** when several refusals apply: *Suggest: unspecified, as with checkout (non-goal).*

**Collecting**
11. **Who can check out a copy on the hold shelf?** Only the member whose READY hold it's set aside for. That marks the hold FULFILLED. Anyone else gets `CopyNotAvailable`. The normal loan-limit and 10.00 borrowing checks still apply. If the hold member is refused, the hold stays READY. *Suggest: yes.*
12. **A copy added with `add_copy` while people are waiting:** does it go straight to the first in line, or onto the shelf? *Suggest: onto the shelf (AVAILABLE). Holds are filled only by returns, expiries and cancellations. Out of scope for now.*

**Cancelling and listing**
13. **`cancel_hold`** works on WAITING or READY holds with no fee. On a FULFILLED, CANCELLED or EXPIRED hold it raises `HoldNotAllowed`. An unknown id raises `HoldNotFound`. *Suggest: yes.*
14. **`holds_for`** returns WAITING and READY holds in the order they were placed. An unknown ISBN raises `TitleNotFound`. *Suggest: yes.*
15. **Missed days:** if the daily job doesn't run for a few days, the next run expires every READY hold whose `pickup_by` has passed. The next person's pickup time counts from that run's date. *Suggest: yes.*

Anything else you want covered, such as notifying members, is a non-goal unless you say otherwise.

### [F2:spec+build] user

Here are my answers by number.

1. Change this one. The pickup time is 7 days from the day the copy comes back and is set aside. If that lands on a Sunday, it moves to the next Monday, since we're closed Sundays. `pickup_by` is the last day to collect. A hold expires only when `pickup_by` is before today, so the `pickup_by` day itself is still fine.
2. All defaults. The fee follows what was settled earlier, so go by the ADR.
3. Yes, with one change. The next waiting hold becomes READY with `pickup_by` = today + 7 days, and Sunday becomes Monday. If nobody is waiting, the copy goes back on the shelf.
4. No, waiting holds don't expire.
5. Yes.
6. Yes, refuse with `HoldNotAllowed`.
7. Yes to both. An active hold on the title is refused. So is a title where the member currently has a copy on loan. Both give `HoldNotAllowed`.
8. I don't mind. Your suggestion is fine.
9. I don't mind. Your suggestion is fine.
10. I don't mind. Your suggestion is fine.
11. Yes.
12. I don't mind. Your suggestion is fine.
13. Yes.
14. Yes. The order is the order the holds were placed.
15. Yes, with one change. The next person's `pickup_by` is the run date + 7 days, with Sunday becoming Monday.

Also, for later: renewals are coming next. While anyone is still waiting in the queue for a title, loans of that title can't be renewed. A hold that is already ready on the hold shelf doesn't count, because that person already has their copy. Renewals will also be only for people who are paid up. If the member's balance shows anything owed when they ask, they can't renew until they've paid. You don't need to build any of that now.

### [F2:spec+build] agent

Holds are built and the full test suite passes: the 74 existing tests plus 50 new ones in `tests/test_holds.py`.

```
$ python3 -m pytest -q
........................................................................ [ 58%]
....................................................                     [100%]
124 passed in 0.06s
```

**Spec:** `SPEC.md` has the interface you fixed, copied word for word, plus the rules, 25 checkable acceptance criteria and the non-goals. Every criterion from 1 to 24 has at least one test named after its number; criterion 25 is the existing tests still passing. The new spec replaced the old overdue-fines one. That file is still in git history, and its rules are already covered by ADRs 0001–0002 and the glossary, so the README now points there for account rules.

**How it behaves:**
- **Placing a hold** is refused with:
  - `AccountBlocked` at a balance of 5.00 or more.
  - `HoldNotAllowed` if a copy is on the shelf, the title has no copies in circulation, the member already has an active hold on it, or they have a copy of it on loan.
- **Returns:** a returned copy goes to the first person waiting. It moves to the hold shelf and their `pickup_by` is the return day + 7, with Sunday moving to Monday.
- **Hold shelf:** only the person the copy is set aside for can check it out, and the usual loan limit and 10.00 borrowing block still apply. If they're refused, the hold stays ready.
- **Daily job:** `expire_holds` expires ready holds whose `pickup_by` is before today and charges adults the 1.00 no-show fee (recorded as a new entry type, `NO_SHOW_FEE`). The copy goes to the next person, with `pickup_by` counted from the day the job runs, or back on the shelf if nobody is waiting. Cancelling a ready hold passes the copy on the same way, with no fee.

**Recorded decisions:**
- **ADR 0005** (new) holds the queue, pickup and expiry rules you settled. ADR 0003 is now marked as built, and its open questions point to 0005.
- **ADR 0006** (new, for later) holds your renewal rules. A loan can't be renewed while anyone is waiting for that title, and ready holds don't count. A member can renew only with a balance of zero. Two questions are noted there as still open: which error each refusal raises, and the fact that the zero-balance check happens before the overdue fine a renewal charges, so that fine blocks the next renewal.
- **`GLOSSARY.md`:** hold, active hold, queue, hold shelf, pickup time, passing a copy on, no-show fee, and "paid up" (a balance of exactly zero) are added or updated.

**Things to be aware of:**
- One consequence of your answer to question 12: a member with a waiting hold can borrow a newly added copy and still keep their place in the queue. The spec lists this as a non-goal, and ADR 0005 flags it for review.
- If the daily job runs late, members can still collect after their `pickup_by` until it runs.
- Nothing is committed. The repo tracks `__pycache__/*.pyc` files, so running the tests marks them as changed. You may want to drop them from git.

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

I've read the glossary, all six ADRs, the current SPEC (holds), and the code. The baseline is 124 tests passing. ADRs 0004 and 0006 already settle a lot of this, and I'll treat these points as fixed unless you tell me otherwise:

- Renewing an overdue loan charges the fine built up so far, using `policy.late_fine` with the renewal day as "as of". After that, lateness counts from the new due date.
- Any **WAITING** hold on the title blocks a renewal. READY holds don't.
- The member must be paid up (balance exactly 0.00) before the renewal. The fine a renewal itself charges doesn't count against that same request, but it does block the next renewal.

That leaves these questions:

**1. New due date.** Should it be counted from the renewal day (renewal day + 21 for a book, + 7 for a DVD, Sunday → Monday), or from the old due date + the loan period?
*My recommendation:* count from the renewal day. That's the usual library rule, and it reuses `policy.due_date`.

**2. Renewal limit.** Is there a maximum number of renewals per loan, for books and DVDs?
*My recommendation:* yes, a limit in `policy`. Please give the number, or say "unlimited".

**3. Fine cap (left open in ADR 0004).** Does the replacement-cost cap apply to each renewal charge separately, or to the total charged over the whole loan, including the final charge at return?
*My recommendation:* cap the total over the loan, so lateness can never cost more than replacing the copy. This would be recorded as a new ADR that amends 0004.

**4. Which error for each refusal.** You fixed `RenewalRefused` for refusals and `LoanNotFound` for unknown ids. Here's my proposed mapping:
- Balance above 0.00: `AccountBlocked` (ADR 0006 says it fits), with the limit shown as 0.00.
- WAITING hold on the title: `RenewalRefused`.
- Renewal limit reached: `RenewalRefused`.
- Loan already returned: `RenewalRefused`. `NoOpenLoan` is about a copy ID handed back at return, so it doesn't fit well here.

Is that right?

**5. Timing.** Is there any restriction on when a loan can be renewed? For example, no earlier than N days before the due date, or no later than N days overdue. Or can it be renewed any time while it's open, including on the day it was borrowed?
*My recommendation:* any time while the loan is open.

**6. Children.** Do children follow exactly the same renewal rules? That means no fine charged (they're exempt), but they still need to be paid up and are still blocked by the queue.

**7. History.** Is a renewal count on the `Loan` enough, or do you also need a record of each renewal (date and old/new due date)? I'd make the per-renewal log a non-goal, apart from the fine entry, which is tied to the `loan_id` as usual.

### [F3:spec+build] user

1. Yes, count from the renewal day, exactly like a checkout made that day (21 days for a book; Sunday -> Monday). Example: book due Mon 23 March, renewed Thu 19 March -> due Thu 9 April. DVDs can't be renewed at all, so there's no +7 case: a DVD renewal is RenewalRefused.
2. Two renewals per loan, for books. The third request is RenewalRefused.
3. I don't mind; go with your recommendation.
4. Your mapping is fine. A returned loan gives RenewalRefused, and I don't mind the rest of the mapping. A DVD is also RenewalRefused.
5. Your recommendation is wrong here. A loan can be renewed from 5 days before its due date onwards. Due Mon 23 March means renewable from Wed 18 March, and on 17 March it's RenewalRefused. There's no limit on how overdue it can be, so an overdue loan can be renewed.
6. I don't mind; follow whatever the existing rules for children say.
7. A count on the Loan is enough. No per-renewal log is needed.

### [F3:spec+build] agent

Renewals are built and the full test suite passes. I haven't committed anything.

```
$ python3 -m pytest -q
........................................................................ [ 46%]
........................................................................ [ 92%]
...........                                                              [100%]
155 passed in 0.05s
```

That's the 124 existing tests plus 31 new ones in `tests/test_renewals.py`. Each new test is named after the spec criterion it checks, and all 21 criteria are covered.

**Spec:** `SPEC.md` replaces the holds spec, which is still in git history. It includes your interface word for word, the rules, 21 acceptance criteria with worked dates, and the non-goals.

**How renewals work:**
- Only open **book** loans can be renewed. DVDs are refused with `RenewalRefused`.
- A loan can be renewed at most **2** times.
- A loan can be renewed from **5 days before its current due date**, with no limit on how overdue it is.
- The new due date is the renewal day + 21 days, with Sunday → Monday.
- **Errors:**
  - an unknown id raises `LoanNotFound`;
  - any balance above 0.00 raises `AccountBlocked`;
  - everything else (returned loan, DVD, too early, limit reached, someone waiting for the title) raises `RenewalRefused`.
- Renewing an overdue loan charges the fine built up so far, as an ordinary overdue fine on that loan. That fine doesn't block the renewal that charges it, but it does block the next one until it's paid.
- **Cap change:** the replacement-cost cap now applies to the **total** of fines for one loan, across its renewals and the return together. This also changes how return fines are worked out: the return now charges only what's left under the cap. For loans that are never renewed, nothing changes.
- **Children:** the same rules apply. They're still never fined, but they still need a zero balance to renew, the same as for every other balance bar.

**Code changes:**
- `RenewalRefused` added to `errors.py`.
- `Loan.renewals: int = 0` added to `models.py`.
- New constants in `policy.py`: books only, a limit of 2, a 5-day window, and a renewal block at any balance from 0.01 up.
- `policy.late_fine` takes a new optional argument for the fines already charged on the loan, so all fine rules stay in that one function.
- `LendingService.renew` added, and `return_copy` now passes in the fines already charged on the loan.

**Project docs:**
- New `docs/adr/0007-renewal-limits-and-fine-cap.md` records your decisions: what can be renewed, the limit and window, how the due date is counted, which error each refusal raises, and the per-loan cap.
- ADRs 0004 and 0006 are now marked as built, with their open questions pointing to 0007.
- ADR 0001 and `GLOSSARY.md` no longer say fines are only charged on return. The glossary also gains *Renewal window* and *Fine cap per loan*, and its *Renewal* entry is no longer marked as planned.

**One thing I couldn't finish:** I tried a quick extra check where I deliberately broke the cap, the window and the paid-up rule to confirm the new tests catch each one. Those commands needed approval in this session, so they didn't run. The suite passes, and I checked all the dates in the spec by hand.

The compiled `__pycache__` files are tracked in git in this repo, so they show up as changed after the test run.
