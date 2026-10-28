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

The codebase is small and clear: in-memory repo, injected `Clock`, `Decimal` money, numbers kept in `policy.py`, 18 passing tests. Before I write the spec I need your decisions on these. Each one has a suggested default, so you can just answer "defaults OK" or change only the ones you care about.

**Fine amount**
1. **Rate:** per day late, by material. Suggested: DVD £1.00/day, book £0.20/day. What currency and rates?
2. **Counting days:** calendar days after `due_on`, or only days the library is open (Sundays don't count)? Suggested: open days only, since a member can't return anything on a Sunday. Returning on the due date costs nothing either way.
3. **Cap:** should one loan's fine stop growing at some point? Suggested: cap it at the title's `replacement_cost`.
4. **Children:** same rates, a reduced rate, or no fines? Suggested: same rates.

**What "owes right now" means**
5. Should `balance()` include fines that are still building up on overdue items not yet returned, or only charges already posted (late returns and manual charges)? Suggested: posted charges only. Then the balance only changes when something actually happens, and the fine is charged once, on return.

**Blocking**
6. **Threshold:** suggested: checkout raises `AccountBlocked` when the balance is **£10.00 or more**. Should it be ≥ or >, and is the amount the same for adults and children?
7. Should blocking also count the fines building up on items still out (only matters if you chose "posted only" in Q5)? Suggested: no, posted balance only.
8. **Check order:** if a member is blocked *and* also at their loan limit or asking for an unavailable copy, which error wins? Suggested: unknown member → copy not found → `AccountBlocked` → copy not available → loan limit.

**Amounts**
9. **Overpayment:** if someone pays more than they owe, do we keep it as credit (negative balance) or reject it with `InvalidAmount`? Suggested: reject. The library doesn't hold credit.
10. **Invalid amounts:** suggested: `InvalidAmount` for zero, negative, more than 2 decimal places, NaN/infinity, or anything that isn't a `Decimal` (e.g. a float). Should ints be accepted? Suggested: yes, since `add_title` already converts with `Decimal(...)`.
11. **`reason`:** must it be non-empty? Suggested: yes, a blank reason raises `InvalidAmount`... though that error name is a stretch for text. If you'd rather not, `reason` can just be stored without validation. Which do you prefer?

**Scope**
12. Is each of these a non-goal: viewing an account's transaction history, waiving or refunding fines, lost-item charges, and a fines column in the overdue report? Suggested: all non-goals, except that each charge and payment is still stored with its reason and date, so history can be added later.

### [F1:spec+build] user

1. No preference on currency. Books 0.25 per late day, DVDs 1.00 per late day.
2. Open days only: count days after the due date up to and including the return day, skipping Sundays. On or before the due date costs nothing.
3. Yes, cap one loan's fine at the title's replacement cost.
4. Children are never fined. Their late return is processed normally and nothing is charged.
5. Posted charges only. The fine is charged when the copy comes back, and each late return adds its own fine to the balance.
6. 10.00 or more blocks, so exactly 10.00 is blocked. Same threshold for everyone. Returns and payments must still work while blocked.
7. No, posted balance only.
8. Don't mind, go with your suggested order.
9. Reject with InvalidAmount; we don't keep credit.
10. A payment or charge must be positive and in whole cents, otherwise InvalidAmount. I don't mind about the other details (ints etc.).
11. Don't mind, pick whichever you prefer.
12. Yes, all non-goals, and the overdue report stays as it is. Staff use manual charges for things like a lost card or damaged case.

Also, for later, here is where the service is heading:
- Holds: a member who owes 5.00 or more won't be able to place a hold; it will be refused with AccountBlocked. That bar is deliberately lower than the 10.00 borrowing bar, because a hold ties up a copy for someone who already owes us.
- No-show fee: if a copy is set aside for a member's hold and they don't collect it within the pickup time, they get a 1.00 fee on the same balance as fines. It counts toward the blocks like any fine, and children never pay it.
- Renewals come after holds. Renewing an already overdue loan must charge the late fine accrued so far, counted exactly as if the copy had been returned on the renewal day (usual rates, cap and child exemption). After the renewal, lateness is counted against the new due date. Lateness before a renewal must never just disappear.

### [F1:spec+build] agent

Overdue fines and member accounts are built, and the test suite passes:

```
$ python3 -m pytest -q
........................................................................ [ 98%]
.                                                                        [100%]
73 passed in 0.02s
```

That's the 18 tests that were there before plus 55 new ones in `tests/test_accounts.py`. Each new test is tagged with the number of the `SPEC.md` acceptance criterion it covers, and all 21 criteria have at least one test.

**`SPEC.md`** contains your interface word for word, the rules as you decided them, 21 checkable acceptance criteria, the non-goals, and a "Future direction" section for holds, no-show fees and renewals.

**How it behaves**
- **Fines:** a late return charges books 0.25 and DVDs 1.00 for each open day late; Sundays don't count. A loan's fine never exceeds the title's replacement cost, and children are never fined. The fine is charged when the copy comes back.
- **Balance:** it only counts charges already made and payments. It never goes below zero, so paying more than is owed raises `InvalidAmount`.
- **Blocking:** `checkout` raises `AccountBlocked` once a member owes 10.00 or more. Returns and payments still work while blocked.
- **Error order in `checkout`:** unknown member, then unknown copy, then `AccountBlocked`, then copy not available, then loan limit.
- **Amounts:** charges and payments must be positive and in whole cents, otherwise `InvalidAmount`. Floats, strings, NaN, infinity and values too large to hold in cents are also rejected; whole numbers like `3` are accepted.
- **`reason`** on manual charges is stored as given and not checked.

**Ready for what comes next:**
- Every charge and payment is stored with its date and reason, so account history can be added later.
- The thresholds and the "children don't pay" rule are in `policy.py`. Holds can block at 5.00 and the no-show fee can reuse the child exemption.
- The fine calculation works for any "as if returned on" date, so a renewal can charge exactly what a return that day would.

I also exported the two new model types from the package and added a short paragraph about accounts to `README.md`. I haven't committed anything.

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

I've read the code, the existing `SPEC.md` (the fines feature), and the tests (73 passing). The fines spec already has a "Future direction" section that settles some of holds ahead of time: a member who owes **5.00 or more** can't place a hold (refused with `AccountBlocked`), and a held copy that isn't collected costs a **1.00 no-show fee**, which children never pay. I'll treat those as given unless you say otherwise.

Each question below has my recommendation in **bold**. Reply "all as recommended", or just list the numbers you'd change.

**SPEC.md**
1. `SPEC.md` currently holds the fines spec. **Keep it and add a holds section, and update its "Future direction" section, since holds will no longer be future work.** Or should I replace the whole file?

**Placing a hold**
2. Is a hold only allowed when no copy is on the shelf? **Yes. If any copy is `AVAILABLE`, raise `HoldNotAllowed`; the member should just borrow it.** A copy set aside for someone else doesn't count as available.
3. What if a title has no copies in circulation (none at all, or all withdrawn)? **`HoldNotAllowed`, because nothing will ever come back.**
4. Can a member have two active holds on the same title? **No, `HoldNotAllowed`. Also refuse a hold on a title the member currently has on loan.**
5. Is there a cap on how many holds a member can have? **No cap (non-goal).**
6. Can children place holds? **Yes. They're only exempt from the fee.**
7. In what order are errors checked? **`MemberNotFound` → `TitleNotFound` → `AccountBlocked` (≥ 5.00) → `HoldNotAllowed`.**

**Return and pickup**
8. How long is the pickup window, and is it the same for books and DVDs? **3 calendar days from the day the copy is set aside, the same for every material. Like due dates, `pickup_by` moves to Monday if it lands on a Sunday. The member can collect through `pickup_by` inclusive.**
9. What happens when a copy is returned and the title has waiting holds? **The copy becomes `ON_HOLD_SHELF`; the first waiting hold becomes `READY` with `copy_id` and `pickup_by` set. Fines and the return value work as they do today.**
10. How does the member pick up? **Through the normal `checkout(member_id, copy_id)`. On success the hold becomes `FULFILLED`. Anyone else trying to borrow a set-aside copy gets `CopyNotAvailable`. The usual checkout rules still apply at pickup (10.00 borrow block, loan limit). If one of them fails, the hold stays `READY` until `pickup_by`.**
11. What if a member with an active hold borrows some other copy of the same title, for example one that came back unexpectedly? **That fulfils their hold. If they had a copy set aside, it passes to the next person in line, or back to the shelf if nobody is waiting.**
12. What happens when `add_copy` adds a new copy while people are waiting? **It's set aside for the first in line, the same as a return.**

**Cancel and expire**
13. Which holds can be cancelled? **`WAITING` or `READY` holds; there's no fee. Cancelling a `READY` hold passes the copy on (the next person's window starts today) or puts it back on the shelf. Cancelling a hold that's already `FULFILLED`, `CANCELLED` or `EXPIRED` raises `HoldNotAllowed`. An unknown id raises `HoldNotFound`.**
14. What does `expire_holds()` do? **Every `READY` hold whose `pickup_by` is before today becomes `EXPIRED`, posts the 1.00 no-show fee (adults only), and passes its copy on as in 13. If the job misses days, it catches up. Running it twice on the same day expires nothing new.**
15. Do `WAITING` holds ever expire? **No (non-goal).**
16. How is `holds_for` ordered? **`WAITING` and `READY` holds in the order they were placed. Holds placed on the same day keep their placement order. An unknown ISBN raises `TitleNotFound`.**

Anything else you want in or out of scope, such as notifying members or a limit on holds?

### [F2:spec+build] user

Mostly all as recommended, with one correction. Q8 (and the 'next person' window in Q13/Q14): the pickup window is 7 days, not 3. pickup_by = the day the copy is set aside + 7 days, and if that is a Sunday, the next Monday. The member can still collect on pickup_by itself. A cancelled or expired hold passes the copy on with today + 7, same Sunday rule. On the 5.00 hold block and the 1.00 no-show fee for adults only, those were settled earlier and should be written down in the existing SPEC, so follow that. Q11 and Q12: I don't mind, use whatever you find sensible. Q1, Q5 and Q15 are fine; keep SPEC.md and add a holds section. Also, for later: renewals are coming next, so please don't make them hard to add. While anyone is still waiting in the queue for a title, loans of that title can't be renewed. A hold that is already ready on the hold shelf doesn't count, because that person already has their copy. And renewals are only for members who are paid up: if the member's balance shows anything at all owed when they ask, they can't renew until they have paid.

### [F2:spec+build] agent

Holds are built and the full test suite passes: the 73 tests that existed before, plus 45 new ones for holds.

```
$ python3 -m pytest -q
........................................................................ [ 61%]
..............................................                           [100%]
118 passed in 0.04s
```

**Spec:** I kept the fines spec in `SPEC.md` and added a "Spec: holds" section after it. It has the interface copied word for word from your request, the rules, 24 checkable acceptance criteria and the non-goals. The 5.00 hold block and the adults-only 1.00 no-show fee now sit in its rules. The "Future direction" section now covers only renewals, including your two new rules: no renewing while anyone is WAITING for the title, and no renewing while anything at all is owed. The new tests in `tests/test_holds.py` cover every criterion.

**How it behaves:**
- **Pickup window:** a copy set aside on a given day must be collected within 7 days, moved to Monday if that's a Sunday. The same rule applies when a cancelled or expired hold passes the copy to the next person.
- **Collecting:** the member picks up through the normal `checkout`. Anyone else trying to borrow a set-aside copy gets `CopyNotAvailable`.
- **Daily job:** `expire_holds()` only expires holds on the day *after* their last pickup day, so a second run on the same day does nothing.
- **Your Q11/Q12 choices:** I went with my recommendations. A new copy added while people are waiting is set aside for the first in line. A member who borrows a different copy of the title has their hold fulfilled, and the copy set aside for them is released.

**Things you should know:**
- **I changed one criterion (AC13).** One case it described can never happen. A copy only goes back on the shelf when nobody is waiting, and nobody can place a hold while a copy is on the shelf. So when someone borrows a different copy, there's never a next person to receive the copy set aside for them. It simply goes back to the shelf, and the criterion now says that.
- **Additions you didn't ask for:**
  - a new account entry type (`EntryKind.FEE`) for no-show fees, so they're kept separate from fines and manual charges;
  - three new settings in `policy.py`: the 5.00 hold limit, the 7-day window and the 1.00 fee;
  - a short Holds entry in the README.
- **Renewals are ready to add.** There's already an internal lookup for who is still WAITING on a title, and the existing balance check can take a different limit per action. One thing to decide when we build them: an overdue renewal posts its fine, which puts the member in debt. Is the "nothing owed" check made before that fine is posted? Your wording ("when they ask") suggests before.
- **Nothing is committed.** The repo tracks compiled `__pycache__/*.pyc` files, so those show up as changed too. You may want to remove them from git and add them to `.gitignore`.

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

The existing SPEC.md already has a "Future direction: Renewals" section, so these rules are settled and I won't ask about them again:
- Renewing an overdue loan posts the fine owed so far, counted as if the copy were returned that day (same rates, cap and child exemption).
- After a renewal, lateness counts from the new due date.
- A **WAITING** hold on the title blocks renewal. A READY hold doesn't.
- Any balance above 0 blocks renewal.

These questions are still open. Each has my recommendation, so you can just answer "agree" or correct the ones you'd change.

**1. New due date.** Is it counted from the renewal day (today + 21 days for a book, 7 for a DVD) or from the old due date (old `due_on` + the loan period)? The Sunday → Monday rule applies either way.
*Recommend: from the old due date.* Renewing early then never shortens the loan, and the member doesn't lose days.

**2. Renewal limit.** Is there a maximum per loan? Is it the same for books and DVDs, and for adults and children?
*Recommend: 2 renewals per loan for everyone, kept in `policy`.* The 3rd attempt gets `RenewalRefused`.

**3. Overdue loans.** Can they always be renewed (fine posted, then renewed), or is there a cutoff, e.g. no renewal more than N days late?
*Recommend: no cutoff.* The future-direction text already assumes overdue loans can be renewed.

**4. When to check the balance.** Check it before the renewal fine is posted. So a paid-up member with an overdue loan gets the fine posted *and* the renewal granted. Their next renewal needs them to pay first.
*Recommend: yes, as described.*

**5. Which error for owing money.** Use the existing `AccountBlocked` (threshold 0.01, same pattern as the 10.00 and 5.00 blocks), or `RenewalRefused`?
*Recommend: `AccountBlocked`.* You asked to reuse existing errors where they fit, and this is exactly that class's meaning.

**6. Other refusals.** Which error for each of these?
- Renewing a loan that's already returned: *recommend `RenewalRefused`.* `NoOpenLoan` is about a copy being handed back and takes a `copy_id`, so it doesn't fit.
- A WAITING hold on the title: *recommend `RenewalRefused`.*
- The renewal limit already reached: *recommend `RenewalRefused`.*

**7. Check order, and what a refusal changes.** The first failing check raises its error, and a refused renewal changes nothing (no fine posted).
*Recommend this order:* `LoanNotFound` → returned loan (`RenewalRefused`) → balance (`AccountBlocked`) → WAITING hold (`RenewalRefused`) → limit (`RenewalRefused`).

**8. Fine cap across renewals.** Is the replacement-cost cap for the *whole loan*, adding up fines from renewals and the final return, or does each part get its own cap?
*Recommend: the whole loan.* Repeated renewals of a very late DVD shouldn't add up to more than the cost of replacing it.

**9. Earliest renewal.** Can a loan be renewed any time, including the day it was borrowed?
*Recommend: any time.* With rule 1 nothing is lost, and the limit stops abuse.

**10. Non-goals (proposed).**
- Renewal history (dates of each renewal) beyond the `renewals` count.
- Staff overrides of the limit or the blocks.
- Automatic or self-service renewal.
- Notifications.
- Changing the overdue report beyond it naturally using the new `due_on`.

Anything to add or remove?

### [F3:spec+build] user

Answers by number:
1. No - count from the renewal day, like a checkout made that day: 21 days for a book, Sunday due date moves to Monday. E.g. book due Mon 23 March, renewed Thu 19 March -> due Thu 9 April. DVDs can't be renewed at all, so there's no 7-day case.
2. Two renewals per loan; the third request is RenewalRefused. I haven't set different limits for adults/children, so same for everyone. DVDs are never renewable (RenewalRefused).
3. Agree, no cutoff. Overdue loans can be renewed as long as nothing else stops it.
4. I don't mind; the fines/balance rules were settled earlier and should be written down in the project - go with that and your recommendation.
5. Same as 4, go with your recommendation.
6. Agree on all three: RenewalRefused for returned loan, WAITING hold and limit reached. Unknown loan id stays LoanNotFound.
7. Agree that a refused renewal changes nothing (due date and renewal count stay as they were). I don't mind which error wins when several apply; your order is fine.
8. I don't mind, go with your recommendation.
9. No, not any time: a loan can be renewed from 5 days before its due date onwards. Due Mon 23 March -> renewable from Wed 18 March; on 17 March it's RenewalRefused.
10. Your list is fine. Also a renewal is not a new loan: same loan_id, copy_id, member and borrowed_on, and the copy stays on loan.

### [F3:spec+build] agent

Renewals are built and the full test suite passes:

```
$ python3 -m pytest -q
........................................................................ [ 50%]
........................................................................ [100%]
144 passed in 0.05s
```

That's the 118 tests that existed before plus 26 new ones in `tests/test_renewals.py`. Each new test is tagged with the spec criterion it covers, and every one of the 19 criteria has at least one test.

**Spec.** I added a "Spec: renewals" section to the end of `SPEC.md`, with your interface copied in word for word. The old "Future direction" note now points to it.

**How it behaves:**
- **What a renewal does:** it extends the same loan in place. `loan_id`, `copy_id`, member and `borrowed_on` stay the same and the copy stays on loan. The new due date is the renewal day + 21, moved to Monday if it lands on a Sunday, and `renewals` goes up by 1.
- **Checks, in order:**
  1. Unknown loan id → `LoanNotFound`.
  2. Returned loan → `RenewalRefused`.
  3. DVD → `RenewalRefused`.
  4. More than 5 days before the due date → `RenewalRefused`.
  5. Member owes anything at all → `AccountBlocked`, with a threshold of 0.01.
  6. Someone has a WAITING hold on the title → `RenewalRefused`.
  7. Loan already renewed twice → `RenewalRefused`.
- **Refusals:** a refused renewal changes nothing: due date, renewal count and balance all stay as they were.
- **Overdue loans:** renewing one posts the fine owed so far, counted as if it were returned that day, then renews it. The balance is checked before that fine is posted. So a member who owes nothing can renew an overdue loan once, but has to pay that fine before renewing again.

**Change to existing behaviour.** The replacement-cost cap now covers all fines on a loan, at renewals and at the final return combined. For loans that are never renewed, fines come out exactly as before.

**Where the code is:** the rules (books only, 2 renewals, 5-day window, 0.01 threshold) are in `src/lending/policy.py`. `renew` and the loan-wide cap are in `src/lending/service.py`. I also added a short note on renewals to the README.

**Before you commit:** the `__pycache__/*.pyc` files are tracked in git, so running the tests changed them. You'll probably want to leave them out of the commit, or stop tracking them. Nothing is committed yet.
