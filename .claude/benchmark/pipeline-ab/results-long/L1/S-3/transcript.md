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

I've read the package. Before writing the spec I need decisions on a few points where the code doesn't decide for me. I've put a proposed default on each one, so you can answer "default" or override just the ones you care about.

**Fines**
1. **Rate.** Is it per day late, and does it differ by material? *Default: DVD 1.00/day, book 0.20/day.*
2. **Children.** Do they get the same rate, a reduced rate, or no fines at all? *Default: same rate as adults.*
3. **Counting days.** The library is closed on Sundays, and the due date already skips them. Should a late fine count every calendar day past `due_on`, or only open days? Is there a grace period? *Default: calendar days, no grace period. Returning on the due date is free, and returning one day after costs one day's fine.*
4. **Cap.** Is the fine for one loan capped? *Default: capped at the title's `replacement_cost`.*
5. **When the fine counts.** Should `balance` include fines still building up on items that are out and overdue, or only fines charged at return, as your request describes? *Default: only at return. Unreturned overdue items don't count toward the balance or the block.*

**Blocking**
6. **Threshold.** How much does a member have to owe before they're blocked, and is it the same for children? *Default: blocked when balance ≥ 10.00, for everyone.*
7. **Scope of the block.** Does it only stop `checkout`? *Default: yes. Returns and payments always work, and returning an item late can push a member over the limit.*

**Amounts**
8. **Overpayment.** Should paying more than is owed be rejected with `InvalidAmount`, or kept as credit (a negative balance)? *Default: reject it.*
9. **Valid amounts.** *Default: `InvalidAmount` for zero, negative, more than 2 decimal places, or anything that isn't a `Decimal`, such as a float. Also for an empty `reason` on `add_charge`.*

**Scope**
10. **Out of scope?** *Default: all of these are non-goals: waiving or refunding fines, charges for lost or damaged items, a public transaction-history API, and changes to `overdue_report`. I'd still keep an internal ledger of charges and payments rather than just a running total.*

### [F1:spec+build] user

Going through your points by number:

1. Rate: it's per late day. Books cost 0.25 per day, not 0.20. DVDs at 1.00 per day are right.
2. Children: they are never fined. A child's late return is processed normally and nothing is charged.
3. Counting days: Sundays don't count, because we're closed and nobody could have returned the copy. Late days start the day after the due date and run up to and including the return day, minus any Sundays. There is no grace period. For example, a book due Mon 23 March and back Mon 30 March has 6 late days (7 days minus Sunday the 29th), so the fine is 1.50.
4. Cap: your default is right. One loan's fine never exceeds the title's replacement cost.
5. When the fine counts: your default is right. A fine is charged only when the copy comes back, so overdue items still out add nothing yet. Each late return adds its own fine, and they add up.
6. Threshold: 10.00 or more is blocked, so exactly 10.00 is blocked. Children are never fined, but the threshold is the same for everyone.
7. Scope of the block: your default is right. It only stops checkout. Returns and payments always work.
8. Overpayment: reject it with InvalidAmount. We don't keep credit.
9. Valid amounts: your default is fine. Amounts must be positive and in whole cents. Manual charges follow the same rule, and they go on the same balance and count toward the block.
10. Scope: your non-goals are fine, and so is an internal ledger. One more rule: a refused checkout, payment or charge changes nothing. A refused checkout creates no loan and leaves the copy on the shelf.

### [F1:spec+build] agent

Overdue fines and member accounts are built, and the full test suite passes.

```
$ python3 -m pytest -q
........................................................................ [100%]
72 passed in 0.03s
```

That's the 20 existing tests plus 52 new ones in `tests/test_accounts.py`. Every acceptance criterion in `SPEC.md` (1–25) has at least one test, and each test is tagged with its criterion number. Your worked example (book due Mon 23 March, returned Mon 30 March, fine 1.50) is one of them.

**The spec (`SPEC.md`)** copies your interface word for word: the four methods on `LendingService` and the two new error classes. It then lists your rules and 25 checkable acceptance criteria, followed by the non-goals.

**What changed:**
- **Fines and blocking:** the rates, the "children are never fined" rule, the 10.00 threshold and the Sunday-skipping late-day count live in `policy.py`, next to the existing loan periods and limits.
- **Account records:** charges and payments are stored as entries in an internal ledger (`AccountEntry` in `models.py`, kept by the repository). The balance is the sum of those entries, so a late return's fine stays traceable to its loan. The ledger isn't available to other code, as agreed.
- **Service methods:** `return_copy` now charges the fine on a late return. `balance`, `add_charge` and `pay` are new, and `checkout` raises `AccountBlocked`. A refused operation checks everything before it changes anything, so it leaves no partial state behind.
- **Errors:** `AccountBlocked` and `InvalidAmount` are added to `errors.py`, and the README has a short "Account" entry.

**Calls I made that you didn't specify, which are in the spec where they affect behaviour:**
- **Whole cents** is judged by value: `Decimal("1.5")` is accepted, `Decimal("1.005")` is refused.
- **Plain numbers are refused:** an `int` or `float` amount raises `InvalidAmount`, consistent with "money is always Decimal".
- **Empty reason:** a blank or whitespace-only reason on `add_charge` also raises `InvalidAmount`, since there's no separate error class for it.
- **Unknown member comes first:** for an unknown member with a bad amount, `MemberNotFound` is raised, not `InvalidAmount`.
- **Very large amounts:** something like `Decimal("1e30")` is refused with `InvalidAmount` rather than crashing with a raw `decimal.InvalidOperation`.

Nothing is committed. Running the tests also created untracked `__pycache__/` directories, because the repo has no `.gitignore`.

### [F1:spec+build] user

Thanks. Also, for later, since you're done with the fines: here is where the service is heading.

- Holds are coming next. A member who owes 5.00 or more won't be able to place a hold. It will be refused with AccountBlocked. That bar is lower than the 10.00 borrowing bar on purpose, because a hold ties up a copy for someone who already owes us.
- No-show fee for holds. If a copy is set aside for a member's hold and they don't collect it within the pickup time, they get a 1.00 no-show fee. It goes on the same balance as fines and counts toward the blocks like any fine. Children never pay it.
- Renewals come after holds. Renewing a loan that is already overdue must charge the late fine accrued so far as part of the renewal. It is counted exactly as if the copy had been returned on the renewal day, with the usual rates, cap and child exemption. After the renewal, lateness is counted against the new due date. Lateness before a renewal must never just disappear.

### [F1:spec+build] agent

Your permission settings block my memory directory, so I wrote your plans to `ROADMAP.md` in the repo instead. It's uncommitted, so delete it if you'd rather keep it out of the repo.

**How the fines work fits what's coming:**
- **Renewals:** the fine is already calculated from a due date and a return day. Renewal can reuse that calculation with the renewal day as the return day, then move the due date forward. Lateness up to the renewal is charged when the loan is renewed, so it never disappears.
- **No-show fee:** it can go on the same internal ledger as fines and manual charges. Children can be exempted by the rule that already exempts them from fines. It will need its own kind of ledger entry.
- **Holds threshold:** the block check currently has the 10.00 borrowing threshold built in. Holds will need a second threshold of 5.00 next to it, and both will be "or more", like borrowing. I haven't changed any code for this yet.

**Three questions to settle before building, also listed in `ROADMAP.md`:**
1. **Cap across a renewal:** if a loan is late before and after renewing, is the replacement-cost cap on the loan's total fines, or on each part separately? Your current rule ("one loan's fine never exceeds replacement cost") suggests the total. Capping each part could charge up to twice the replacement cost.
2. **Renewing while blocked:** can a member who owes 10.00 or more renew? And what if the fine charged at renewal is what pushes them over?
3. **Pickup time:** how long is it, and does it count Sundays?

### [F1:spec+build] user

Your recommendation on the cap is fine: the total fine for one loan, across a renewal, never goes above the replacement cost. On renewing while blocked, and on the pickup time and Sundays, I don't mind, so use whatever you think is sensible. Please don't build any of the holds, no-show or renewal work yet. I'll ask for that separately, and keeping ROADMAP.md in the repo is fine.

### [F1:spec+build] agent

I've recorded the decisions in `ROADMAP.md`, replacing the open questions. I haven't changed any code: holds, no-show fees and renewals are still unbuilt.

- **Cap across a renewal (your call):** one loan's total fine, counting both what's charged at renewal and at the final return, never goes above the title's replacement cost.
- **Renewing while blocked (my call):** renewal follows the 10.00 borrowing bar. It's refused with `AccountBlocked` if the balance, plus the fine the renewal would charge, comes to 10.00 or more. A refused renewal changes nothing, but the lateness isn't lost because it's still charged when the copy comes back. The outcome matches returning the copy and then trying to borrow it again.
- **Pickup time (my call):** a set-aside copy can be collected for 7 days, with a deadline that moves from Sunday to Monday the way due dates do. The 1.00 no-show fee is charged once that day passes without collection.

Nothing is committed yet. The uncommitted files are the fines work, `SPEC.md` and `ROADMAP.md`; tell me if you want them committed on a branch.

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

I've read the code, the current `SPEC.md` (the fines feature), and `ROADMAP.md`. The roadmap already settles several things about holds, so I'll treat these as given unless you tell me otherwise:

- A member who owes **5.00 or more** can't place a hold. This is refused with `AccountBlocked`.
- **No-show fee of 1.00** if a set-aside copy isn't collected in time. It goes on the normal balance and counts toward both blocks. Children never pay it.
- **Pickup window**: 7 days from the day the copy is set aside, moved to Monday if it lands on a Sunday. The fee is charged once `pickup_by` has passed, so on `pickup_by + 1` or later.

These are the questions that are still open. Each has my recommendation, so you can answer "yes" or just name the ones you'd change.

**Placing a hold**
1. **When is a hold allowed?** I'd say only when the title has no `AVAILABLE` copy. If a copy is on the shelf, refuse with `HoldNotAllowed`. Copies set aside for someone else count as "out".
2. **Titles with no copies in circulation** (none added, or all withdrawn): should a hold be allowed and wait for a copy that may never come, or be refused with `HoldNotAllowed`? I'd refuse it.
3. **Duplicates**: each member gets one active (WAITING/READY) hold per title, and a second is refused with `HoldNotAllowed`. Also refuse a hold on a title the member already has a copy of on loan?
4. **Limits**: no cap on how many holds a member can have, and children can place holds. Unknown member → `MemberNotFound`, unknown ISBN → `TitleNotFound`.

**Returns and collection**
5. **On return**: if the title has WAITING holds, the copy becomes `ON_HOLD_SHELF`. The first hold in line becomes READY, with `copy_id` set and `pickup_by` computed from the return day. `return_copy` still returns the `Loan`.
6. **Collecting**: the member collects by calling the normal `checkout(member_id, copy_id)` on the set-aside copy, and the hold becomes FULFILLED. Anyone else trying to check out that copy gets `CopyNotAvailable`. The normal checkout rules still apply to the hold's member: the loan limit and the 10.00 block. If checkout is refused, the hold stays READY and the clock keeps running. OK?
7. **A member with a WAITING hold who checks out another copy of the same title** (for example, a newly added copy that went on the shelf): should that fulfil the hold automatically? I'd say yes, so they don't stay in the queue for a book they already have.
8. **Newly added copies** (`add_copy`) go on the shelf as `AVAILABLE` even when people are waiting. Only returned copies get routed to the queue. Should I put this in the non-goals?

**Cancelling and expiry**
9. **`cancel_hold`** works on WAITING or READY holds and never charges a fee. Cancelling a READY hold passes its copy to the next person in line, with a fresh window from today, or puts it back on the shelf if nobody is waiting. Cancelling a FULFILLED, CANCELLED or EXPIRED hold → `HoldNotAllowed`. Unknown id → `HoldNotFound`.
10. **`expire_holds`** marks READY holds whose `pickup_by` has passed as EXPIRED and charges the no-show fee. The copy then moves on to the next person in line (window from today) or back to the shelf. WAITING holds never expire. Running it twice on the same day expires nothing the second time. If the job is skipped for a few days, each overdue READY hold is expired once, and the next person's window starts from the day the job actually runs.
11. **`holds_for`** lists WAITING and READY holds in the order they were placed. Ties on the same day keep the order they came in.
12. **`withdraw_copy`** on a copy on the hold shelf keeps refusing with `CopyNotAvailable`, since it already refuses anything that isn't `AVAILABLE`.

**Housekeeping**
13. `SPEC.md` currently holds the fines spec. Should I **replace** it with the holds spec (the fines spec stays in git history), or **append** the holds spec below it? I'd append so the fines rules stay in view. I'd also update the README concepts and remove "Holds (next)" from `ROADMAP.md`.

### [F2:spec+build] user

1. Yes. If a copy is on the shelf, refuse with HoldNotAllowed; copies set aside for someone else count as out.
2. Refuse with HoldNotAllowed. Nothing will ever come back for a title with no copies in circulation (all withdrawn, or none added).
3. Yes to both: one active hold per member per title, and a member who has a copy of that title on loan right now can't hold it. Both HoldNotAllowed.
4. I don't mind a cap or children placing holds; use your recommendation. Unknown member -> MemberNotFound, unknown ISBN -> TitleNotFound.
5. Yes. pickup_by = return day + 7, moved to Monday if that is a Sunday.
6. Yes, that's right: only the holder can take a set-aside copy, everyone else gets CopyNotAvailable. The holder's checkout follows the normal rules; if it's refused, the hold stays READY and the clock keeps running.
7. I don't mind; use your recommendation.
8. I don't mind; put it wherever you see fit.
9. Yes. Cancel works on WAITING or READY holds. A cancelled READY hold's copy moves on as in expiry (fresh window from today, or back to the shelf if nobody waits). Cancelling a non-active hold -> HoldNotAllowed; unknown id -> HoldNotFound.
10. Yes. A READY hold expires only once pickup_by is before today (the pickup day itself is still fine). WAITING holds never expire. A second run the same day expires nothing. The copy goes to the next waiting hold with a window of today + 7 (Monday if Sunday), or back to the shelf. For the roadmap items (the 5.00 block, the 1.00 no-show fee), go with what the roadmap says.
11. Yes: only WAITING and READY holds, in the order they were placed.
12. Fine, no change.
13. Append is fine; updating README and roadmap too.

Also, for later, this is where the service is heading: renewals are next. Two rules will apply. (a) While anyone is still waiting in the queue for a title, loans of that title can't be renewed; a hold that is already READY on the hold shelf doesn't count, because that person already has their copy. (b) Renewals are only for members who are paid up: if their balance shows anything at all owed when they ask, they can't renew until they've paid.

### [F2:spec+build] agent

Holds are built and the full test suite passes: 114 tests, the 72 that were there before plus 42 new ones.

```
$ python3 -m pytest -q
........................................................................ [ 63%]
..........................................                               [100%]
114 passed in 0.03s
```

**Spec:** I added a "Holds" section to the end of `SPEC.md`, below the fines spec. It has the interface you fixed, copied word for word, plus the rules, 32 acceptance criteria and the non-goals. Each new test in `tests/test_holds.py` is tagged with the criterion number it checks, and all 31 criteria about holds have at least one test. Criterion 32 is that the old tests still pass.

**What changed in the code:**
- **`models.py`:** the new `Hold`, `HoldStatus` and `CopyStatus.ON_HOLD_SHELF`, plus a new account entry type for the no-show fee.
- **`errors.py`:** `HoldNotAllowed` and `HoldNotFound`.
- **`policy.py`:** the hold numbers: the 5.00 hold block, the 7-day pickup window moved to Monday if it ends on a Sunday, the 1.00 fee, and the child exemption.
- **`repository.py`:** stores holds in the order they were placed, which is the queue order.
- **`service.py`:** the four new methods.
  - `checkout` now lets only the holder take a set-aside copy, and it marks the member's hold FULFILLED.
  - `return_copy` hands the copy to the first person waiting.
  - Cancelling or expiring a READY hold passes its copy to the next person, or puts it back on the shelf if nobody is waiting.

**Choices I made where you left it to me:**
- There's no cap on how many holds a member can have, and children can place holds.
- If a member with a hold borrows a different copy of the same title, the hold is FULFILLED. If a copy was already set aside for them, it goes to the next person in line.
- New copies added with `add_copy` go on the shelf even if people are waiting. This is listed as a non-goal.

**Renewals:** I put your two rules for later in `ROADMAP.md`. Your "paid up only" rule conflicts with a decision already there (renewal refused only if balance plus the renewal fine reaches 10.00). I marked that decision as replaced by your rule but kept its text visible so you can confirm. Which error a refused renewal raises is listed as still open.

**Not done:**
- I tried to check that the new tests catch bugs by breaking three rules in the code on purpose and rerunning. The sandbox blocked those commands, so I skipped it. The tests do pass against the real code.
- Nothing is committed yet.
- The repo tracks `__pycache__/*.pyc` files, so they show up as changed. You may want to add them to `.gitignore` before committing.

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

The roadmap already settles a lot: overdue renewals charge the fine so far, the cap covers the whole loan, a WAITING queue blocks renewal, members must be fully paid up, and a refused renewal changes nothing. Here's what it leaves open, with my recommendation for each:

1. **Renewal limit.** How many times can one loan be renewed? I'd suggest **2**, the same for books and DVDs. Or should there be no limit, or different limits per material?
2. **New due date.** I'd suggest **renewal day + the normal loan period** (21 days for books, 7 for DVDs, moved to Monday if it lands on a Sunday). The alternative is old due date + loan period, which lets an early renewal stack extra time.
3. **Renewing too early.** With option 2, renewing on the day you borrowed gives the same due date and uses up a renewal for nothing. I'd **refuse with `RenewalRefused` when the new due date wouldn't be later than the current one**. Or should a renewal always be allowed?
4. **Which error when the member owes money.** The roadmap leaves this open. I'd use **`RenewalRefused`**. `AccountBlocked` stands for the 10.00 borrowing bar and carries that threshold, so using it for "owes anything at all" would mislead callers. Or would you rather reuse `AccountBlocked`?
5. **Renewing a loan that's already returned.** I'd use **`RenewalRefused`**. `NoOpenLoan` is keyed by copy and means "handed back a copy that isn't out".
6. **Children.** I'd suggest the **same rules**. They're never fined, so an overdue renewal charges them nothing, but they still need a zero balance.
7. **Order of checks** when several reasons apply: does it matter which error wins? I'd go unknown id → closed → limit reached → owes money → queue → too early, and treat the exact order as untested.

Reply "all recommended" or override any of them.

### [F3:spec+build] user

Mostly fine, with three corrections.
1. Limit 2 per loan is right (third request refused). But DVDs can't be renewed at all: RenewalRefused. Only books can be renewed.
2. Renewal day + normal loan period, same as a checkout made that day (21 days for a book, Sunday moves to Monday). The DVD case never applies since DVDs are refused.
3. Don't use the 'new due date must be later' rule. Instead, a loan can only be renewed from 5 days before its due date onwards. E.g. due Mon 23 March: renewable from Wed 18 March; on 17 March it's RenewalRefused. Overdue loans can still be renewed as long as nothing else stops it.
4. I don't mind; RenewalRefused is fine.
5. RenewalRefused for a returned loan, as you suggest; an unknown loan id stays LoanNotFound.
6. I don't mind; go with your suggestion.
7. Order doesn't matter to me.
Also, a renewal is the same loan, not a new one: same loan_id, copy, member and borrowed_on date, and the copy stays on loan. The borrowing limit does not apply, so a member at their limit can still renew. A refused renewal changes nothing.

### [F3:spec+build] agent

Renewals are built and the full test suite passes.

```
$ python3 -m pytest -q
........................................................................ [ 52%]
................................................................         [100%]
136 passed in 0.04s
```

That's the 114 existing tests plus 22 new ones in `tests/test_renewals.py`. Each new test is tagged with the spec criterion it covers, and together they cover all 18 renewal criteria. The 19th criterion is that the old tests still pass. As a check, I briefly turned off the rule that limits a loan's total fines, and the two tests for it failed.

**The spec** is a new "Renewals" section at the end of `SPEC.md`, following the two features already there. It copies your interface word for word. It combines your answers with the rules already settled in `ROADMAP.md`:
- An overdue renewal charges the fine built up so far.
- One loan's fines, across renewals and the final return, never add up to more than the title's replacement cost.
- Anyone WAITING for the title blocks renewal; a READY hold doesn't.
- The member must owe nothing at all.
- A refused renewal changes nothing.

**What changed in the code:**
- **`renew()`** (`src/lending/service.py`) runs every check before changing anything, so a refused renewal leaves the loan, the account and the holds alone. An overdue renewal records its fine against that loan.
- **Returns:** `return_copy` now subtracts fines already charged at earlier renewals, so the replacement-cost limit covers the whole loan.
- **Numbers:** books only, at most 2 renewals, renewable from 5 days before the due date. They're in `src/lending/policy.py` with the other circulation rules.
- **`Loan.renewals`** (default 0) is in `src/lending/models.py`.
- **`RenewalRefused`** is in `src/lending/errors.py`. It carries `loan_id` and a reason (`why`), like `HoldNotAllowed`.

I also added a Renewal entry to the README and marked renewals done in `ROADMAP.md`, including that refused renewals raise `RenewalRefused`.

Your 21-day period has one side effect: renewal day + 21 is always the same weekday, so the "moves to Monday" rule only applies to a renewal made on a Sunday. Criterion 4 tests it that way.

Nothing is committed. Git also shows changed `.pyc` files, because the repo tracks `__pycache__`. You'll probably want to leave those out of the commit.
