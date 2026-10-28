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

The package is small and clean (18 tests passing, `Decimal` money, injected `Clock`, Sunday closures already in `policy`). Before I write the spec I need your decisions on the points below. Each one has a proposed default, so you can just answer "defaults OK" or change only the ones you disagree with.

**Fine calculation**
1. **Rate:** how much per day late, and does it differ by material? *Proposed: DVD €1.00/day, book €0.20/day.*
2. **Which days count:** every calendar day after `due_on`, or only days the library is open (skipping Sundays)? *Proposed: open days only, so a closed day isn't charged.*
3. **Grace period:** any days late that are free? *Proposed: none.*
4. **Cap per loan:** is the fine capped, for example at the title's `replacement_cost`? *Proposed: yes, capped at replacement cost.*
5. **Children:** do child members pay fines at the same rate, a reduced rate, or nothing? *Proposed: same rules.*

**Balance and blocking**
6. **What `balance` includes:** only charges already posted (late returns plus manual charges, minus payments), or also fines still building up on items that are overdue and not yet returned? *Proposed: posted charges only. The fine is charged when the item comes back, as your brief says.*
7. **Blocking threshold:** at what amount does `checkout` raise `AccountBlocked`, and is that amount itself blocked (≥) or allowed (>)? *Proposed: blocked when balance ≥ €10.00.*
8. **Overdue items held:** should a member who currently has an overdue item out also be blocked, even with a zero balance? *Proposed: no. That's a non-goal; blocking is purely about money owed.*

**Payments and charges**
9. **Overpayment:** if someone pays more than they owe, should that be rejected with `InvalidAmount`, or kept as credit (negative balance)? *Proposed: rejected. You can't pay more than the current balance.*
10. **Which amounts are invalid:** *Proposed: `InvalidAmount` for zero, negative, or more than 2 decimal places (fractions of a cent), for both `add_charge` and `pay`. Also for a blank `reason` on `add_charge`.*
11. **Records:** should each charge and payment be kept as a record (date, amount, reason, loan id) even though there's no public method to list them yet? *Proposed: yes, store them; a statement/listing API is a non-goal.*

**Scope**
12. **Out of scope:** *Proposed non-goals: lost/damaged item charges, waiving or refunding charges, currency handling (amounts are plain `Decimal` in the library's currency), and changes to `overdue_report`.*

### [F1:spec+build] user

Going through them by number:
1. Books are 0.25 per late day, not 0.20. DVDs are 1.00 per late day. No euro sign needed, just plain amounts.
2. Open days only. Sundays aren't counted. Late days run from the day after the due date up to and including the day it comes back. If it's back on or before the due date, there's no fine.
3. No grace period, as you proposed.
4. Yes, capped at the title's replacement cost, per loan.
5. Children are never fined. Their late returns are processed normally but nothing is charged.
6. Posted charges only. The fine is charged when the copy comes back, and each late return adds its own fine.
7. Blocked at 10.00 or more, so exactly 10.00 is blocked. Returning copies and paying always work, even when the member is blocked.
8. Agreed, it's purely about money owed.
9. Rejected with InvalidAmount. We don't keep credit on accounts.
10. Agreed. A payment or charge must be positive and in whole cents, otherwise InvalidAmount. Partial payments are fine, and pay returns what is still owed. The same applies to manual charges, which go on the same balance and count toward the block. On the blank reason, I don't mind.
11. I don't mind how you store them.
12. Fine with me. Leave the overdue report as it is.

One more thing: a refused checkout must create no loan and leave the copy on the shelf. A refused payment or charge must leave the balance as it was.

Also, for later, so you can keep it in mind: we're adding holds next. A member who owes 5.00 or more won't be able to place a hold, and that will be refused with AccountBlocked. That bar is lower than the 10.00 borrowing bar on purpose. We'll also charge a 1.00 no-show fee, on the same balance as fines, when a copy set aside for a hold isn't collected in time. It counts toward the blocks, and children never pay it. After holds, renewals are coming. Renewing a loan that is already overdue must charge the fine accrued so far, counted as if the copy had been returned on the renewal day, with the usual rates, cap and child exemption. After the renewal, lateness is counted against the new due date. Lateness before a renewal must never just disappear.

### [F1:spec+build] agent

I wrote the spec to `SPEC.md` and built the feature, and the full test suite passes:

```
$ python3 -m pytest -q
.......................................................................  [100%]
71 passed in 0.02s
```

That's the original 18 tests plus 53 new ones in `tests/test_accounts.py`. Each new test is tagged with the spec criterion it covers, and all 22 behaviour criteria have at least one test. Criterion 23 ("the existing suite still passes") is covered by the original 18 passing unchanged. The overdue report wasn't touched.

**What changed**
- **`LendingService`**: `balance`, `add_charge` and `pay` match your signatures. `return_copy` now charges the fine on a late return. `checkout` raises `AccountBlocked` when the balance is 10.00 or more; that check runs after the existing ones and before any loan is created, so a refused checkout leaves nothing behind.
- **`errors.py`**: adds `AccountBlocked` and `InvalidAmount`, both subclasses of `LendingError`. `AccountBlocked` carries the balance and the threshold, so holds can reuse it with their 5.00 bar.
- **`policy.py`**: holds the numbers (0.25 / 1.00 per day, the 10.00 bar), the count of open late days, and the rule that children are never fined. Your holds and renewals rules can reuse these.
- **Records**: every fine, charge and payment is stored with its date, reason and (for fines) loan id. The balance is worked out from those records, so it can't drift from them.

**Calls I made that you should check**
- **Children and manual charges:** staff can put a manual charge on a child's account. I read "children are never fined" as covering automatic late fines only. It's spec criterion 11; tell me if children should be exempt from manual charges too.
- **What counts as an invalid amount:** `InvalidAmount` covers zero, negative, fractions of a cent, NaN/infinity, absurdly large values, and non-money types such as floats, strings and booleans. Plain integers like `3` are accepted.
- **Blank reason:** since you didn't mind, the reason on a manual charge isn't checked.

**Ready for renewals:** the cap applies to everything charged on one loan, not to each charge separately. Today each loan only gets one fine, so this changes nothing yet. When renewals charge part of the fine early, the fine at final return will stay within the replacement cost, and the earlier lateness stays on the account. If you'd rather each renewal's charge be capped on its own, that's a one-line change, but it should be decided before renewals ship.

I also added a short "Accounts" entry to the README. Nothing is committed.

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

I've read the code and the existing `SPEC.md`. Its "Coming next" section already settles three things about holds, and I'll carry them over unchanged:
- A member who owes 5.00 or more can't place a hold (`AccountBlocked`).
- A copy that's set aside and not collected costs a 1.00 no-show fee, charged to the same balance.
- Children never pay that fee.

A few things are still open. Each question has a proposed answer, so you can just reply "all defaults" or correct the ones you disagree with.

**When a hold can be placed**
1. **Only when no copy is free.** Should `place_hold` raise `HoldNotAllowed` if the title has an `AVAILABLE` copy? Copies set aside for someone else, on loan, or withdrawn don't count as free. *Proposed: yes.*
2. **No copy in circulation.** What if every copy is withdrawn, or the title has no copies? *Proposed: `HoldNotAllowed`, since nothing would ever come back to fill the hold.*
3. **Duplicates.** Should these raise `HoldNotAllowed`: the member already has an active (WAITING/READY) hold on the title, or already has a copy of it on loan? *Proposed: yes to both.*
4. **Limits.** Is there a cap on how many active holds a member can have? *Proposed: no cap; children can place holds.*

**Pickup window**
5. **How long is "a few days"?** *Proposed: 3 calendar days from the day the copy is set aside, moved to the next open day if it lands on a Sunday (same rule as due dates). The member can collect on any day up to and including `pickup_by`. The hold expires once today is after `pickup_by`.*

**Returns and checkout**
6. **Return with a queue.** When a copy comes back and the title has waiting holds, should it go to `ON_HOLD_SHELF` for the first in line, making that hold READY with `copy_id` and `pickup_by` set? Otherwise it goes back to `AVAILABLE`. Fines work as before. *Proposed: yes.*
7. **Checking out a set-aside copy.** Only the hold's member can check it out, and doing so marks the hold FULFILLED. Anyone else gets `CopyNotAvailable`. The usual loan limit and borrowing block still apply at pickup. If pickup is refused, the hold stays READY until `pickup_by`. *Proposed: yes.*
8. **Passing a copy on.** When a READY hold is cancelled or expires, its copy goes straight to the next WAITING hold, with a new `pickup_by` counted from that day, or back to `AVAILABLE` if no one is waiting. *Proposed: yes.*
9. **New copies.** Should `add_copy` on a title with waiting holds put the new copy on the hold shelf? *Proposed: no, it stays `AVAILABLE` and holds are filled only by returns, or by a copy passed on from a cancelled or expired hold. This would be listed as a non-goal.*

**Cancel and expire**
10. **Cancelling.** Members can cancel a WAITING or READY hold with no fee. Cancelling a hold that is already FULFILLED, CANCELLED or EXPIRED raises `HoldNotAllowed`. An unknown id raises `HoldNotFound`. *Proposed: yes.*
11. **What expires.** Only READY holds expire, never WAITING ones, however long they wait. Running `expire_holds` twice on the same day expires nothing the second time. *Proposed: yes.*

**Housekeeping**
12. **SPEC.md.** It currently holds the accounts spec from the previous feature. *Proposed: replace it with the holds spec (the accounts spec stays in git history), keeping the "Renewals" item under "Coming next".* Or would you rather I add holds as a new section under the existing spec?

### [F2:spec+build] user

Corrections: Q5 and Q8 use 7 days, not 3. pickup_by is the return day + 7 days, Sunday -> next Monday. When a copy is passed on from a cancelled or expired hold, it's today + 7, with the same Sunday rule. Q1-3, 6, 7, 10, 11: agreed. Q4, Q9, Q12: I don't mind, go with your proposals; replacing the spec is fine. The three items from 'Coming next' were settled earlier, so carry them over as the project has them written down. Also, for later: renewals are next. While anyone is still waiting in the queue for a title, loans of that title can't be renewed. A hold that is already ready on the hold shelf doesn't count, since that person has their copy. Renewals are also only for members who are paid up: if the balance shows anything owed when they ask, they can't renew until they've paid.

### [F2:spec+build] agent

Holds are built and the full test suite passes: 120 tests, including the existing ones.

```
$ python3 -m pytest -q
........................................................................ [ 60%]
................................................                         [100%]
120 passed in 0.04s
```

**Spec.** `SPEC.md` now holds the holds spec, replacing the accounts spec. Your interface is copied in word for word, followed by the rules, 39 acceptance criteria and the non-goals. The settled hold rules are quoted exactly as the old spec had them. Under "Coming next", the existing renewals text is kept, and your two new renewal rules are added: no renewal while anyone is WAITING for the title (a READY hold doesn't count), and no renewal while anything is owed.

**Code.**
- **Interface:** all four new methods are on `LendingService`, and `Hold`, `HoldStatus`, `CopyStatus.ON_HOLD_SHELF`, `HoldNotAllowed` and `HoldNotFound` are in place as you specified.
- **`checkout` and `return_copy`** keep their signatures. A returned copy now goes to the first person waiting, and checking out a set-aside copy completes that hold.
- **Policy values** live in `src/lending/policy.py`: the 7-day pickup window (moved to Monday if it lands on a Sunday), the 5.00 bar for placing holds and the 1.00 no-show fee.
- **Fee records:** I added an `EntryKind.NO_SHOW_FEE` value so these fees can be told apart from fines and manual charges.
- **Exports and README:** `Hold` and `HoldStatus` are exported from the package, and the README describes holds.

**Tests.** They're in `tests/test_holds.py`, and each test name starts with the number of the criterion it covers. Every criterion from 1 to 38 has at least one test; 39 is the existing suite still passing. I tried to break a couple of rules on purpose to confirm the new tests would catch it, but that needed approval, so I skipped it.

**Two calls I made that you didn't decide.** Both are written into the spec; tell me if either is wrong:
- **Criterion 21:** a member can still collect after `pickup_by` until the daily job has actually expired the hold.
- **Criterion 23:** if a member with a hold checks out a different copy of the same title (possible because new copies go straight to the shelf), their hold is marked FULFILLED. If a copy had been set aside for them, it passes to the next person in line.

**Housekeeping.** Nothing is committed. The repo tracks its `__pycache__/*.pyc` files, so those show as modified too; you may want to leave them out of the commit.

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

I've read the code and the current `SPEC.md`. That file is the holds spec, and its "Coming next" section already settles three renewal rules:

- Renewing an overdue loan charges the fine so far, and later lateness counts from the new due date.
- No renewal while anyone is `WAITING` for the title.
- Only paid-up members can renew.

I'll take those as given. These are the gaps. Each has my suggested default, so "yes to all" works as an answer.

**Limits and dates**
1. **How many renewals per loan?** Suggested: at most 2 per loan, the same for adults, children, books and DVDs. Or do you want a different number, a per-material number, or no limit?
2. **How is the new due date counted?** Suggested: from the renewal day, so renewal day + the normal loan period (21 days for books, 7 for DVDs), moved to Monday if it lands on a Sunday. The other option is counting from the old due date.
3. **Early renewals:** counting from the renewal day means renewing on the day of checkout gives the same due date. Suggested: refuse a renewal that wouldn't push the due date later (`RenewalRefused`), so it doesn't use up a renewal. Or allow it anyway?
4. **How late can a loan be renewed?** Suggested: no cutoff. Any open loan can be renewed, however overdue, as long as the fine is charged. Or should very overdue loans (say, ones that hit the replacement-cost cap) be refused?

**Money**
5. **When is "paid up" checked?** Suggested: on the balance *before* this renewal's own overdue fine is posted. So a paid-up member with an overdue loan gets the renewal and ends up owing the fine, and their next renewal is refused until they pay. The alternative is to post the fine first and then refuse, which means an overdue loan could never be renewed.
6. **Which error for "owes money"?** `AccountBlocked(member_id, balance, threshold)` already exists for "owes too much to do this". Suggested: reuse it with threshold `0.01`. Or should every renewal refusal be `RenewalRefused`, to keep it uniform?
7. **Atomicity:** suggested: a refused renewal changes nothing (no fine posted, due date and count unchanged). Agree?

**Other refusals**
8. **Loan already returned:** suggested `RenewalRefused`. `NoOpenLoan` takes a `copy_id` and means "this copy was handed back but isn't on loan", which doesn't really fit.
9. **Loan limit and the 10.00 borrowing block:** suggested: they don't apply, since the paid-up rule is stricter and a renewal doesn't add a loan. Agree?
10. **A `READY` hold on the title:** it doesn't block renewal (already settled). And if the borrower themselves is `WAITING` on the same title? They can't be, since `place_hold` refuses members who have it on loan, so I'll treat that as impossible.

**Scope and the doc**
11. **History:** is the `renewals` count enough? Suggested non-goals: no per-renewal dates or audit log, no member self-service or online renewal, no renewal notices, no auto-renewal, and no change to `overdue_report` beyond what follows from `due_on` moving.
12. **SPEC.md:** last time the holds spec replaced the previous one and carried the earlier settled rules over word for word. Suggested: do the same now. Replace the holds spec with a renewals spec that quotes the three "Coming next" rules verbatim, with the holds rules staying in git history. Or would you rather I append a renewals section and keep the holds spec?

### [F3:spec+build] user

1. Two renewals per loan is right, but DVDs can't be renewed at all. Only books can. The third request is `RenewalRefused`.
2. Counting from the renewal day is right. It's a fresh full loan period, exactly like a checkout made that day, with Sunday moved to Monday. Example: a book due Mon 23 March and renewed Thu 19 March is due Thu 9 April.
3. I don't want your "no later due date" rule. The rule is about timing. A loan can be renewed from 5 days before its due date onwards. If a book is due Mon 23 March, it can be renewed from Wed 18 March, and on 17 March it's `RenewalRefused`. A refused renewal uses up nothing.
4. Overdue loans can be renewed, with no cutoff from me, as long as nothing else stops it.
5. That was settled earlier, so go by what's written in the project. I don't remember the details.
6. I don't mind. Reuse `AccountBlocked` if it fits.
7. Agreed. A rejected renewal changes nothing: due date and renewal count stay as they were.
8. Agreed, `RenewalRefused`. An unknown loan id is still `LoanNotFound`.
9. Agreed. A renewal isn't a new loan, so the borrowing limit doesn't apply. A member at their limit can renew. It's the same `loan_id`, `copy_id`, member and `borrowed_on`, and the copy stays on loan.
10. I don't mind. Your call.
11. The counter is enough. I don't care about a history list. Your non-goals are fine.
12. I don't mind. Do it the way you did last time.

### [F3:spec+build] agent

Renewals are built, and the full test suite passes.

```
$ python3 -m pytest -q
........................................................................ [ 50%]
........................................................................ [100%]
144 passed in 0.05s
```

That's the 120 tests that already existed plus 24 new ones in `tests/test_renewals.py`. Each new test name carries the number of the spec criterion it checks, and all 25 criteria are covered.

**What a renewal does now:**
- It extends the same loan: same id, copy, member and borrow date, and the copy stays on loan. The new due date is a full loan period from the renewal day, moved to Monday if it falls on a Sunday.
- It's refused with `RenewalRefused` when:
  - the loan is a DVD,
  - it has already been renewed twice,
  - it's earlier than 5 days before the due date,
  - the loan has been returned,
  - or someone is `WAITING` for the title.
- A member who owes anything gets `AccountBlocked`. The balance is checked as it stands when they ask, before any fine from this renewal is added.
- Renewing late charges the fine up to that day, with the usual rates, replacement-cost cap and no fines for children. Any later lateness counts from the new due date.
- A refused renewal changes nothing.

**Choices I made where you left it to me:**
- **Owing money:** this reuses `AccountBlocked`, with the bar set at 0.01 as a new constant in `policy.py`.
- **`SPEC.md`:** I replaced the holds spec, as was done last time, and quoted the three renewal rules from its "Coming next" section word for word. The holds spec is still in git history.
- **Borrower waiting on their own title:** I didn't handle this, because the existing hold rules already prevent it.
- **README:** I added a short Renewals entry.

**Files changed:** `SPEC.md`, `README.md`, `src/lending/errors.py`, `models.py`, `policy.py`, `service.py`, plus the new test file.

Nothing is committed. Running the tests also rewrote the `__pycache__/*.pyc` files, which this repo tracks in git, so they'll show up in `git status` too.
