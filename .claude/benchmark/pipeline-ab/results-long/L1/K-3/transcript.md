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

The codebase is small and clear: in-memory repo, injected clock, Decimal money, rules kept in `policy.py`, and no GLOSSARY.md or ADRs yet. Before I write the spec I need you to settle a few rules. Each question has a proposed default, so you can just reply "ok" or change the ones you want.

**Fine calculation**
1. **Rate:** how much per day late? My proposal: DVD **$1.00/day** and book **$0.25/day**, since DVDs are the problem.
2. **Children:** do child members get fined the same as adults, at a reduced rate, or not at all?
3. **Which days count:** every calendar day after `due_on`, or only days the library is open (Sundays not counted)? Is there a grace period? My proposal: calendar days, no grace period.
4. **Cap:** is the fine for one loan capped? My proposal: capped at the title's `replacement_cost`.

**Balance and blocking**
5. **"Owes right now":** does `balance()` include fines still building on items that are overdue but not yet returned, or only charges already posted (late returns and manual charges) minus payments? This also decides whether someone sitting on an overdue DVD gets blocked.
6. **Block threshold:** what amount blocks borrowing, and does reaching it exactly block? My proposal: blocked when balance **≥ $10.00**.

**Payments and amounts**
7. **Overpaying:** if a member pays more than they owe, do we reject it with `InvalidAmount` or keep a credit (negative balance)? My proposal: reject.
8. **What counts as an `InvalidAmount`:** my proposal is zero, negative, more than 2 decimal places, or not a `Decimal` (e.g. a float). Does that apply to both `add_charge` and `pay`?
9. **Manual charge reason:** must it be non-empty? What happens if it's empty?

**Scope**
10. **Non-goals:** my proposal is to leave out waiving or refunding charges, lost or damaged item handling, a statement or transaction history API, and persistence beyond the in-memory repo. Does any of these need to be in scope?

### [F1:spec+build] user

1. Rates are right: books 0.25 per late day, DVDs 1.00 per late day. 2. Children are never fined. Their late return is processed normally and nothing is charged. 3. Sundays don't count, because we're closed and nobody could return a copy then. Late days run from the day after the due date up to and including the return day, minus Sundays. No grace period. Example: a book due Mon 23 March and back Mon 30 March is 6 late days (7 days minus Sunday the 29th), so 1.50. Back on or before the due date means no fine. 4. Yes, the fine for one loan is capped at the title's replacement cost. 5. Only charges already posted. A loan that is overdue but still out adds nothing yet. The fine is charged when the copy comes back, and each late return adds its own fine. 6. Blocked at 10.00 or more, and exactly 10.00 is blocked. Returning copies and paying always work, even while blocked. 7. Reject it with InvalidAmount. We don't keep credit. Partial payments are fine, and pay returns what is still owed. 8. A payment must be a positive amount in whole cents and can't exceed what the member owes. Manual charges follow the same rule: positive and in whole cents. Anything else is InvalidAmount. 9. I don't mind about the reason. Do whatever is sensible. 10. Fine as proposed. Those are out of scope. Also, a refused checkout, payment or charge must change nothing: no loan is created, the copy stays on the shelf, and the balance stays as it was.

### [F1:spec+build] agent

Overdue fines and member accounts are built, and the full test suite passes.

```
$ python3 -m pytest -q
....................................................................     [100%]
68 passed in 0.02s
```

That's the 18 tests that were already there plus 50 new ones in `tests/test_accounts.py`. Each new test is tagged with the number of the SPEC.md criterion it checks, and every criterion has at least one.

**SPEC.md** includes the interface from your request word for word, your rules, 21 checkable acceptance criteria and the non-goals. Some examples from it:
- A book due Mon 23 March and returned Mon 30 March costs 1.50.
- The first late day is charged, since there's no grace period.
- A DVD fine stops at its 12.00 replacement cost.
- A balance of exactly 10.00 blocks checkout and 9.99 doesn't.
- A refused checkout, payment or charge changes nothing.

**What changed**
- **`service.py`:** `balance`, `add_charge` and `pay` are new. `return_copy` now charges the fine when a copy comes back late, and its signature and return value are unchanged. `checkout` raises `AccountBlocked` only after all its other checks pass, so a refused checkout changes nothing.
- **`policy.py`:** the rates, the fact that children aren't fined, the 10.00 limit and the late-day counting all live here with the other circulation rules. Late days skip whatever days the library is closed, which is currently Sundays.
- **Account storage:** each fine, manual charge or payment is recorded as an entry that is never edited, and the balance is worked out from those entries.

**Choices I made that you should check**
- **Manual charge reason:** a blank or missing reason is refused with a new error, `MissingReason(LendingError)`. It's the only error class I added beyond the two you named.
- **What counts as an invalid amount:** besides zero, negative and fractions of a cent, `InvalidAmount` is also raised for anything that isn't a finite `Decimal`, including floats, ints, strings and `NaN`. `Decimal("1.500")` is accepted as 1.50.
- **Which error wins:** if a member is blocked and the copy is also unavailable or they're at their loan limit, they get the existing error, not `AccountBlocked`.

As CLAUDE.md asks, I created `GLOSSARY.md` (account, balance, blocked, charge, fine, late day, and so on) and two decision records:
- `docs/adr/0001-fines-posted-on-return.md`: fines are charged at return and count only open days.
- `docs/adr/0002-member-account-ledger-no-credit.md`: no credit and the 10.00 block.

I also added a short Account entry to the README.

Nothing is committed. Running pytest created untracked `__pycache__/` folders, and the repo has no `.gitignore` yet.

### [F1:spec+build] user

Thanks. Also, for later, this is where the service is heading:

1. **Holds are coming next.** A member who owes 5.00 or more won't be able to place a hold, and the request is refused with `AccountBlocked`. That bar is lower than the 10.00 borrowing bar on purpose, because a hold ties up a copy for someone who already owes us.
2. **No-show fee for holds.** If a copy is set aside for a member's hold and they don't collect it within the pickup time, they get a 1.00 no-show fee. It goes on the same balance as fines and counts toward the blocks like any fine. Children never pay it.
3. **Renewals come after holds.** Renewing a loan that is already overdue must charge the late fine accrued so far as part of the renewal. It is counted exactly as if the copy had been returned on the renewal day, with the usual rates, cap and child exemption. After the renewal, lateness is counted against the new due date. Lateness before a renewal must never just disappear.

### [F1:spec+build] agent

I've recorded all three as decisions for later, so whoever builds holds and renewals will see them when they read `docs/adr/` before starting:

- **`docs/adr/0003-holds-blocked-at-five.md`:** a member owing 5.00 or more can't place a hold and gets `AccountBlocked`. This bar is a separate setting from the 10.00 borrowing bar on purpose, and a refused hold changes nothing.
- **`docs/adr/0004-hold-no-show-fee.md`:** an uncollected hold charges 1.00 to the same balance. It counts toward both blocks, children are exempt, and the replacement-cost cap doesn't apply.
- **`docs/adr/0005-renewal-charges-accrued-fine.md`:** renewing an overdue loan charges the fine so far, worked out as if the copy were returned that day. Lateness after that counts from the new due date, and no late day is ever dropped or charged twice. A refused renewal charges nothing and leaves the due date alone.

I also updated two existing documents. ADR 0001 now notes that renewals will be a second point where a fine is charged, not just returns. `GLOSSARY.md` now has entries for hold, no-show fee, pickup time and renewal (each marked as planned), and its "blocked" entry lists both bars. I didn't change any code: today's code has a single 10.00 bar, and ADR 0003 notes it will need one per action once holds arrive.

Two questions are still open, and I left both undecided in the ADRs:
1. **Cap across renewals:** is the replacement-cost cap applied to each charge on its own, or to the loan's total across renewals and the final return? Capping each charge separately means a loan renewed late more than once could cost more than the copy's replacement cost.
2. **Pickup time:** how long a set-aside copy waits before the no-show fee is charged.

Neither blocks anything now, but both need an answer before that work starts.

### [F1:spec+build] user

1. The cap is per loan. The total fined on one loan never exceeds the title's replacement cost, across renewals and the final return together.
2. I don't mind the pickup time. Pick whatever you think is sensible.

### [F1:spec+build] agent

I've written both answers into the ADRs and the glossary, so neither question is open any more.

**Cap is per loan** (`docs/adr/0005-renewal-charges-accrued-fine.md`)
- All fines on one loan, across every renewal and the final return, add up to at most the title's replacement cost.
- Each new fine is limited to whatever is left under the cap. Once the cap is reached, nothing more is charged on that loan.
- I added a worked example: a DVD with a 12.00 replacement cost is renewed 8 days late and charged 8.00. It then comes back 6 days late, which works out to 6.00, but only 4.00 is charged.
- The ADR also warns that today's `return_copy` caps each fine on its own. That's correct while a loan can only be fined once, but the renewals work must change it to subtract earlier fines on the same loan. Each recorded fine already notes which loan it belongs to, so that's straightforward.

**Pickup time is 7 open days** (`docs/adr/0004-hold-no-show-fee.md`)
- The clock starts the day after the copy is set aside. If the member hasn't collected it by the end of the 7th open day, the 1.00 no-show fee is charged.
- Sundays don't count, the same as for late days, since nobody can collect while the library is closed. The ADR records that you left the length to me.

In `GLOSSARY.md`, the "fine" entry now says the cap is per loan, and "pickup time" gives the 7 open days. I only changed documentation, so the code and tests are as they were (68 passing). Nothing is committed.

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

I've read the glossary, all five ADRs, the code and the tests (68 passing). Several things are already settled and I won't ask about them again:

- **ADR 0003:** placing a hold is refused with `AccountBlocked` when the balance is 5.00 or more, and a refused hold changes nothing.
- **ADR 0004:**
  - A 1.00 no-show fee is charged when a hold isn't collected in time. Children are exempt, and the fee counts towards both blocks.
  - Pickup time is 7 open days after the day the copy is set aside (Sundays don't count).
  - The fee is charged once per expired hold.

That leaves these open questions. Each one has my recommendation, so you can answer "all as recommended" or just correct the ones you disagree with.

**When a hold can be placed**
1. **A copy is on the shelf:** if any copy of the title is `AVAILABLE`, is the hold refused with `HoldNotAllowed`? *Recommend: yes. A hold is only for when no copy is on the shelf. Copies set aside for other people's holds don't count as on the shelf.*
2. **No copies at all:** a title with no copies, or only withdrawn ones, can never be returned to anyone. *Recommend: refuse with `HoldNotAllowed`.*
3. **Duplicates:** a member who already has an active (waiting or ready) hold on the title places another. *Recommend: refuse with `HoldNotAllowed`.*
4. **Already borrowing it:** a member who has a copy of this title out on loan places a hold. *Recommend: refuse with `HoldNotAllowed`.*
5. **Limits:** should there be a maximum number of active holds per member? And should the loan limit be checked when the hold is placed? *Recommend: no hold limit for now, and the loan limit is checked only at pickup. Children can place holds the same as adults.*

**Pickup**

6. **Who can borrow a set-aside copy:** only the member it is set aside for can check it out. Anyone else gets `CopyNotAvailable`, and that checkout marks the hold `FULFILLED`. The normal checkout rules still apply at pickup (borrow block at 10.00, loan limit). If one of them refuses the checkout, the hold stays ready until its pickup date. *Recommend: as described.*
7. **Last day:** is `pickup_by` the 7th open day itself, so the member can still collect on that day? And is the hold expired by the first daily run *after* that day? *Recommend: yes.*

**Expiry and cancelling**

8. **What expires:** does `expire_holds` only clear *ready* holds that weren't collected? Or should *waiting* holds also lapse after some time? *Recommend: only ready holds. Waiting holds stay in the queue until cancelled.*
9. **Where the copy goes next:** when a ready hold expires or is cancelled, the copy goes to the next person waiting, with a fresh 7-open-day pickup counted from that day. If nobody is waiting, it goes back to `AVAILABLE`. *Recommend: as described.*
10. **Cancelling a ready hold:** is a no-show fee charged? *Recommend: no fee. Cancelling frees the copy early, which is the behaviour we want.*
11. **Holds that are already finished:** cancelling a fulfilled, cancelled or expired hold raises `HoldNotAllowed`. An unknown hold id raises `HoldNotFound`. *Recommend: as described.*

**Housekeeping and later work**

12. **The existing `SPEC.md`:** it holds the fines spec, and `tests/test_accounts.py` points at its criterion numbers. *Recommend: move it to `docs/specs/0001-fines.md`, update that pointer, and write the holds spec to `SPEC.md`.*
13. **For the renewals work (not built now):** should a loan be refused renewal while other members are waiting for that title? *Recommend: yes. I'd record it as an ADR so the renewals work has to follow it.*
14. **Non-goals:** I plan to leave these out:
    - telling members when a copy is ready (notices)
    - holds on one particular copy instead of the title
    - staff overriding the queue order
    - pausing or suspending holds
    - persistence beyond the in-memory repository

    *Anything here you actually want included?*

### [F2:spec+build] user

Mostly all as recommended, with one correction: pickup_by is the set-aside day + 7 calendar days (not open days); if that is a Sunday, move to the next Monday. Same for a copy passed on after expiry/cancel (today + 7, Sunday -> Monday). If ADR 0004 says 7 open days, it needs to be brought in line with that. Q1-4: yes, refuse with HoldNotAllowed. Q5: as recommended, I don't mind. Q6: as described. Q7: yes, the pickup_by day itself is still fine; a hold expires only when pickup_by is before today, so the first run on a later day expires it, and a second run the same day expires nothing. Q8: yes, only ready holds. Q9: as described, with the corrected pickup date. Q10: no fee on cancel, I don't mind. Q11: as described. Q12: fine, go ahead. Q13: yes, and please record it as an ADR: while anyone is still waiting in the queue for a title, loans of that title can't be renewed; a hold already ready on the hold shelf doesn't count, since that person has their copy. Also for later on renewals: a member can't renew if their balance shows anything at all owed when they ask; they must pay first. Please record that in an ADR too. Q14: none of those wanted, leave them all out.

### [F2:spec+build] agent

The docs are done:
- The fines spec moved to `docs/specs/0001-fines.md`, and the pointer in the tests now names it.
- ADR 0004 now says 7 calendar days, with Sunday moving to Monday.
- The two renewal rules are recorded as ADR 0006 (no renewal while anyone is waiting) and ADR 0007 (renewing needs a zero balance).

Writing the spec turned up two gaps where your answers don't yet say what happens. Both change behaviour, so I'd rather ask than guess:

**A. A copy is added while people are waiting.** Someone calls `add_copy` for a title that has waiting holds. Does the new copy go straight to the first person in line, as a returned copy would? Or does it go on the shelf as `AVAILABLE`? *I recommend the first person in line.* That keeps one rule simple: a title never has a copy on the shelf while someone is waiting for it. `add_copy` keeps its signature either way.

**B. A member with a ready hold borrows a different copy of the same title.** Say Ann has copy B1 set aside for her, and copy B2 is on the shelf because nobody else was waiting when it came back. Ann checks out B2. What happens to her hold on B1? *I recommend that borrowing any copy of the title counts as collecting the hold.* Her hold becomes `FULFILLED`, with `copy_id` changed to the copy she actually borrowed. B1 then goes to the next person in line, or back to the shelf if nobody is waiting. Without a rule like this, her hold would expire and she'd be charged the 1.00 no-show fee even though she took the book.

Once you answer these I'll write `SPEC.md` and the holds ADR (0008), then build it.

### [F2:spec+build] user

A: I don't mind what happens when a copy is added while people are waiting, so go with your recommendation. B: I don't mind a member with a ready hold borrowing a different copy of the title either, so go with your recommendation. Go ahead with SPEC.md and the build.

### [F2:spec+build] agent

Holds are built and the full test suite passes:

```
$ python3 -m pytest -q
........................................................................ [ 61%]
.............................................                            [100%]
117 passed in 0.04s
```

That is the 68 tests that existed before plus 49 new ones in `tests/test_holds.py`. `SPEC.md` has 37 acceptance criteria. Each test is tagged with the criteria it covers, and every criterion from 1 to 36 has at least one test; criterion 37 is the regression check, covered by the whole suite passing.

**Spec and decisions**
- **`SPEC.md`** is now the holds spec. It copies the interface you fixed word for word, and lists the non-goals you agreed.
- **The old fines spec** moved to `docs/specs/0001-fines.md`. The note at the top of `tests/test_accounts.py` that points at its criterion numbers now names the new path.
- **ADR 0004** now says pickup time is 7 calendar days (Sunday moves to Monday), with a note that it was changed. It also records that cancelling never charges a fee.
- **ADR 0006:** while anyone is waiting for a title, its loans can't be renewed. Ready holds don't count.
- **ADR 0007:** renewing is refused if the member owes anything when they ask. The check happens before the renewal posts any fine of its own (ADR 0005), so a member who owes nothing can still renew an overdue loan.
- **ADR 0008:** the holds design, which later work must follow:
  - holds are a first-come queue per title;
  - no copy sits on the shelf while anyone is waiting;
  - borrowing any copy of the title counts as collecting the hold;
  - the daily job expires a ready hold only when `pickup_by` is before today;
  - waiting holds never expire.
- **`GLOSSARY.md`** has the new hold terms, such as hold shelf, ready hold and pickup date, and the entries that said "planned" are updated.
- **`README.md`** describes holds, and ADR 0002 refers to the renamed threshold.

**Code**
- **Models and errors:** `Hold`, `HoldStatus`, `CopyStatus.ON_HOLD_SHELF`, a new `EntryKind.NO_SHOW_FEE`, and `HoldNotAllowed` / `HoldNotFound`. A hold refused for a balance of 5.00 or more raises the existing `AccountBlocked`, as ADR 0003 says.
- **Policy:** the single borrowing threshold is now one per action (`BORROW_BLOCK_THRESHOLD` 10.00 and `HOLD_BLOCK_THRESHOLD` 5.00), as ADR 0003 asked. The pickup time and the no-show fee amount also live here.
- **Service:** `return_copy`, `add_copy`, and an expired or cancelled ready hold all hand the copy to the first person waiting, or put it back on the shelf if nobody is. `checkout` keeps its signature. It now lets only the holder borrow a set-aside copy, and marks their hold fulfilled.

The `__pycache__/*.pyc` files are tracked in git, so running the tests shows them as modified. Nothing is committed yet.

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

I've read the glossary, all eight ADRs, both earlier specs and the code. All 117 tests pass. Much of this is already settled:

- **ADR 0005:** renewing an overdue loan posts the fine so far, and the replacement-cost cap applies per loan across renewals and the return. This means `return_copy` changes too.
- **ADR 0006:** no renewal while any hold on the title is `WAITING`.
- **ADR 0007:** no renewal while the member owes anything. The balance is checked before the renewal's own fine.
- A refused renewal changes nothing.

I'll treat those as given. Here is what's still open; each question has my recommendation:

1. **New due date.** I recommend the renewal day plus the material's normal loan period (21 days for books, 7 for DVDs), with Sunday moving to Monday, exactly like a fresh checkout. `borrowed_on` stays the original date. Counting from the old due date would make renewing an overdue loan pointless.

2. **Renewal limit.** I recommend a maximum of **2 renewals per loan**, the same for books and DVDs and for adults and children. After that the member returns the copy. Or do you want no limit, or a different number?

3. **Earliest time to renew.** I recommend no window: any open loan can be renewed at any time. The one exception is a renewal that wouldn't move `due_on` later (for example, on the day the copy was borrowed). It would be refused, so it doesn't use up a renewal.

4. **Which error for which refusal.** I recommend:
   - Balance above zero → `AccountBlocked`. It already covers the checkout and hold blocks, and you asked to keep existing classes where they fit.
   - Loan already returned → `RenewalRefused`. `NoOpenLoan` is keyed by copy and means "a copy was handed back that isn't out", so it doesn't fit a loan id.
   - Someone is waiting, the limit is reached, or the renewal wouldn't extend the loan → `RenewalRefused`.

5. **Scope.** Non-goals I'd list: self-service or online renewal, notices, a per-renewal history beyond the `renewals` count, staff overrides of the refusals, and automatic renewal. Anything you want added to or removed from that list?

Reply "all as recommended" or correct any of them. I'll then write SPEC.md (moving the current holds spec to `docs/specs/0002-holds.md`, like the fines spec before it), record the new rules in an ADR and the glossary, and build it.

### [F3:spec+build] user

Corrections:

1. Due date: renewal day plus the normal loan period, Sunday moves to Monday, is right for books (21 days). DVDs can't be renewed at all, so the 7-day case never comes up. Example: a book due Mon 23 March, renewed Thu 19 March, is due Thu 9 April. `borrowed_on` stays the original date.

2. Limit: 2 renewals per loan is right. The third request is refused (`RenewalRefused`).

3. Earliest time: not "any time". A loan can be renewed from 5 days before its due date onwards. Due Mon 23 March means renewable from Wed 18 March; on 17 March it's `RenewalRefused`. Overdue loans can still be renewed. Your "wouldn't extend" exception is fine as long as it doesn't conflict with this.

4. Errors: your mapping is fine. Returned loan -> `RenewalRefused`, unknown loan id -> `LoanNotFound`, balance -> `AccountBlocked`. Also, DVDs can't be renewed: `RenewalRefused`. I don't mind which error wins when there are two reasons.

5. Scope: your non-goals list is fine. One addition: a renewal is not a new loan. Same `loan_id`, `copy_id`, member and `borrowed_on`, and the copy stays on loan. The borrowing limit doesn't apply, so a member at their limit can still renew.

ADRs 0005-0007 were settled earlier and I don't remember the details, so follow what's written there. Go ahead with SPEC.md.

### [F3:spec+build] agent

Renewals are built and the whole test suite passes.

```
$ python3 -m pytest -q
........................................................................ [ 48%]
........................................................................ [ 97%]
....                                                                     [100%]
148 passed in 0.09s
```

That's the 117 tests that were there before plus 31 new ones in `tests/test_renewals.py`. Each new test is tagged with the `SPEC.md` criterion it covers. Criteria 1–23 all have at least one test, and criterion 24 (existing tests still pass) is the suite itself.

**Spec and docs**
- **`SPEC.md`** is the renewals spec: why, the interface copied word for word from your request, the rules, 24 checkable criteria with March/April 2026 dates, and the non-goals including your "a renewal is not a new loan".
- **Holds spec moved:** `SPEC.md` held the holds spec, so I moved it to `docs/specs/0002-holds.md`, where the fines spec already lives. The links in `README.md` and `tests/test_holds.py` now point there.
- **ADR 0009** records your new decisions: books only, at most 2 renewals per loan, renewable from 5 days before the due date, the loan limit doesn't apply, and which error each refusal raises.
- **ADR 0005** gets a dated note: its worked example uses a DVD, which can no longer be renewed. The arithmetic still holds for books, so I left the accepted text alone.
- **`GLOSSARY.md`** no longer marks renewals as "planned" and gains "Renewal window". **`README.md`** has a short Renewal entry.

**Code**
- **`renew(loan_id)`** extends the loan in place. The new due date is calculated the same way as at checkout.
- **Errors:** unknown ids raise `LoanNotFound`. Any balance owed raises `AccountBlocked`. Everything else (returned loan, DVD, third renewal, too early, someone waiting) raises `RenewalRefused`.
- **Fines, per ADR 0005:** renewing an overdue loan posts the fine so far. `return_copy` now takes off what the loan has already been fined, so all fines on one loan together never exceed the replacement cost. Loans that are never renewed are fined exactly as before.
- **Numbers:** books only, the limit of 2 and the 5-day window are in `policy.py`.

**What I changed from your answers**
- **"Wouldn't extend" rule dropped.** The 5-day window means a book renewal always moves the due date at least 16 days later, so that case can't happen. It isn't in the spec.
- **Error when several reasons apply:** you didn't mind which comes first. Mine are checked in this order: returned, DVD, limit, too early, someone waiting, balance.

Nothing is committed. The compiled `__pycache__` files are tracked in git, so running the tests changed them too.
