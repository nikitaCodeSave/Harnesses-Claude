### [F1:grill] operator

/grill-with-docs Late returns cost nothing today, so DVDs come back weeks late. Add overdue fines and a member
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

### [F1:grill] agent

I've read the whole `lending` package and its tests. There's no `GLOSSARY.md` or ADR yet. Before the questions, here's what the code tells me:

- **Due dates are already set for you.** `policy.due_date` never lands on a Sunday, and Sundays are the only closed day. `reports.OverdueLine.days_overdue` counts calendar days.
- **`Title.replacement_cost` exists but nothing uses it yet.** It's an obvious upper limit for a fine.
- **Return days are already recorded.** `Loan.returned_on` is set from the injected `Clock`, so the fine can be worked out at return time with no new date logic.
- **There is no money record of any kind.** `Member` has no balance field and the repository doesn't store charges.

Here is round 1. These are all the decisions that don't depend on any other answer.

---

❓ **Q1** - **Which days count toward a fine?** A DVD due Saturday that comes back Monday is 2 calendar days late, but the library was closed for one of them (Sunday). Options:
(a) count every calendar day after the due date, matching `days_overdue` in the overdue report;
(b) count only open days, so the member isn't charged for a day they couldn't return the item.

➡️ (b) Count only open days after the due date, up to and including the return day. Use `policy.is_open_day` so there's still one place that decides when the library is open.

---

❓ **Q2** - **Daily rate by material**: Should each material have its own daily rate in `policy`, like the loan periods do? Placeholder rates: **DVD 1.00/day, book 0.20/day**. No currency symbol; it's just `Decimal`.

➡️ Yes. Add a `FINE_PER_DAY: dict[Material, Decimal]` table using those placeholder rates, and change the numbers if you want different ones.

---

❓ **Q3** - **Limit on one fine**: Should one late return be charged at most the title's `replacement_cost`? Without a limit, a DVD returned a year late would cost about 365.00 for a 12.00 disc.

➡️ Yes. Limit each fine to the title's `replacement_cost`.

---

❓ **Q4** - **Children's fines**: Should children pay the same fines as adults?

➡️ Yes, same rates. One table is simpler, and it's easy to add a per-category factor later if you need one.

---

❓ **Q5** - **Grace period**: Should a late return be charged from the first late day, with no grace period?

➡️ Yes, no grace period. One day late on a DVD costs 1.00.

---

❓ **Q6** - **When is a member blocked?** Should there be one blocking threshold for every member, so `checkout` raises `AccountBlocked` when the balance is **at least 10.00**?

➡️ Yes. One `BLOCK_THRESHOLD = Decimal("10.00")` in `policy`, and a member is blocked when `balance >= threshold`. Adults and children use the same threshold.

---

❓ **Q7** - **Fines on items not yet returned**: The brief says a *late return* charges the fine. That means a member sitting on a DVD that's 3 months late currently owes **0** and can keep borrowing. Should `balance()` count only charges that have actually been made (fines from returns plus manual charges, minus payments), without adding fines that are still building up on open overdue loans?

➡️ Yes. `balance` is only what has actually been charged. Fines that are still building up don't count until the copy comes back. Blocking members who hold overdue items is a separate rule that's out of scope here; I'll note it as a follow-up.

---

❓ **Q8** - **Paying more than is owed**: Should a payment larger than the current balance raise `InvalidAmount`, so the balance can never go below zero (no account credit)?

➡️ Yes. Reject overpayments; the balance is always zero or more.

---

❓ **Q9** - **Which amounts are accepted?** For both `add_charge` and `pay`, should an amount be accepted only if it's a `Decimal` that is **greater than zero** and has **no more than 2 decimal places**? Anything else, including `float`, zero, negative amounts, `Decimal("0.005")`, NaN and Infinity, would raise `InvalidAmount`.

➡️ Yes. A `float` is rejected rather than converted, because the README says money is never float. An `int` is the only exception, since it's exact: it's accepted and turned into a `Decimal`.

---

❓ **Q10** - **Waivers and refunds**: Is it OK to leave out any way to cancel or reduce a charge, since `add_charge` takes only positive amounts and the interface has no waive method? For now, the only way to reduce a balance would be `pay`.

➡️ Yes, waivers are out of scope. Staff who need to forgive a fine would have to record it as a payment, which isn't great, so I'll note it as a follow-up.

---

❓ **Q11** - **The charge reason**: Should `reason` be required and not blank? If so, what should a blank reason raise? `InvalidAmount` would be the wrong name. The options are to accept any string, or add a third error.

➡️ Accept any string as given and don't validate it. That keeps the error list to exactly the two you specified.

---

❓ **Q12** - **Account history or just a number?** Should the member account be a history of entries (each **charge** with amount, date, reason and the loan it came from if it's a fine, and each **payment**), with `balance` worked out from the total? The alternative is to store one running balance per member.

➡️ Yes, keep the history. It costs little extra, it lets staff answer "why do I owe 7.00?", and the balance can't drift away from its entries.

---

❓ **Q13** - **Order of checks in `checkout`**: If a blocked member tries to borrow a copy that's already on loan, which error should they get? Should the order be: `MemberNotFound` → `AccountBlocked` → `CopyNotAvailable` → `LoanLimitReached`?

➡️ Yes. Check the block right after looking up the member, because it's about the member and doesn't depend on which copy they picked.

---

❓ **Q14** - **Names for things**: I'd like to fix these terms in `GLOSSARY.md`:
- **Account**: what a member owes the library.
- **Charge**: anything that increases what a member owes.
- **Fine**: a charge made automatically for a late return.
- **Manual charge**: a charge a staff member adds by hand.
- **Payment**: money the member hands over, which reduces what they owe.
- **Balance**: total charges minus total payments.
- **Blocked**: a member whose balance is at or above the threshold, who therefore can't borrow.

"Fee" and "debt" would be avoided as alternative names. Are these the terms you want?

➡️ Yes, use those terms.

### [F1:grill] user

Most of this is fine. Two answers need correcting:

- **Q2:** Books cost 0.25 per late day, not 0.20. DVDs at 1.00 are right.
- **Q4:** No, children are never fined. Their late return is processed normally and nothing is charged. Please don't use a per-category factor.

Everything else is fine as you proposed, including Q1: open days only, Sundays not counted.

Q13 (order of checks), Q11 (reason text) and the follow-up notes in Q7 and Q10 I don't mind. Use whatever you think is sensible.

### [F1:grill] agent

I've written the account terms you approved into `GLOSSARY.md`: Account, Charge, Fine, Manual charge, Payment, Balance and Blocked, each with a list of names to avoid. I didn't put rates or other rules in it; it only defines the words.

You left these to me, so here's what I picked:
- **Q13 (order of checks):** `MemberNotFound` → `AccountBlocked` → `CopyNotAvailable` → `LoanLimitReached`.
- **Q11 (reason text):** any string is stored exactly as given, with no check.
- **Q7 / Q10 (follow-ups):** "blocking members who hold overdue items" and "waiving a charge" will go in an "Out of scope / follow-ups" section of the spec, not in separate issues.

Round 2 follows. These questions only became possible once round 1 was settled.

---

❓ **Q15** - **Manual charges and blocking for children**: Children are never *fined*. Can staff still add a **manual charge** to a child's account (say 3.00 for a damaged case)? And if a child's balance reaches 10.00, are they blocked like anyone else?

➡️ Yes to both. "Never fined" only means late returns are free. A child's account otherwise works the same as an adult's.

---

❓ **Q16** - **Worked example: the Sunday rule**: Here's how open-day counting works out:
- A DVD due **Mon 9 Mar** comes back **Mon 16 Mar**. The late days are Tue–Sat (5) plus Mon 16 (1), so **6 days = 6.00**, compared with 7 calendar days.
- A DVD due **Sat 14 Mar** is posted through the book drop on **Sun 15 Mar**. That's **0 open days late**, so there's no fine.
- If it's handed in on **Mon 16 Mar** instead, that's **1 day = 1.00**.

Are those the right results? The rule is: count the open days after the due date, up to and including the return day.

➡️ Yes.

---

❓ **Q17** - **Returns with no fine**: When a return costs nothing (on time, a child's return, or late only on a Sunday), should the account get **no entry at all**, rather than a 0.00 fine? And when a fine is charged, should its entry record the loan it came from and a reason like `"late return of D1"`?

➡️ Yes. Only real charges get an entry, and each fine records its loan.

---

❓ **Q18** - **Leave `return_copy`'s return value as it is?** It returns a `Loan`. I could add a `fine` field to `Loan`, but you said the return value doesn't change. Should the fine be recorded only on the account, with no change to the `Loan` model?

➡️ Yes. `Loan` stays as it is, and the account entry refers to the loan by `loan_id`.

---

❓ **Q19** - **Viewing the account history**: We're keeping a full history of charges and payments (Q12). Should I add a public method for reading it now, like `account_history(member_id)`? Or should `LendingService` get only the four methods you listed, with the history stored in the repository but not yet visible to other code?

➡️ Only the four methods you listed. I'll put "account history / statement" on the follow-up list. The data will already be there, so adding the method later is a small change.

---

❓ **Q20** - **Overdue report**: Should `reports.overdue_report` stay as it is, without a column for the fine that's building up on each overdue loan?

➡️ Yes, leave it alone. Under Q7, a fine doesn't exist until the copy is returned, so showing one beforehand would confuse the meaning of "fine".

---

❓ **Q21** - **Record this decision as an ADR?** The decision that "fines are charged at return and fines still building up aren't in the balance" passes all three ADR tests:
- **It's surprising:** someone 3 months late on a DVD owes 0 and isn't blocked.
- **It was a real trade-off:** against counting fines as they build up.
- **It's costly to reverse:** changing it later changes who is blocked and what the balance means.

Should I write `docs/adr/0001-fines-charged-on-return.md`?

➡️ Yes. It's one paragraph, and it will stop someone later from "fixing" balances to include fines still building up.

### [F1:grill] user

Yes to all of these. Your Q16 examples are right. A Sunday return is something I don't mind either way.

Also, for later, this is where the service is heading:

- **Holds:** when we add them, a member who owes 5.00 or more can't place a hold. It gets refused with `AccountBlocked`. That bar is lower than the 10.00 borrowing bar on purpose. A hold ties up a copy for someone who already owes us.
- **No-show fee:** if a copy is set aside for a member's hold and they don't collect it within the pickup time, they get a 1.00 no-show fee. It goes on the same balance as fines and counts toward the blocks. Children never pay it.
- **Renewals:** these come after holds. Renewing a loan that is already overdue must charge the late fine accrued so far as part of the renewal. It's counted exactly as if the copy had been returned on the renewal day, with the usual rates, cap and child exemption. After the renewal, lateness is counted against the new due date. Lateness before a renewal must never just disappear.

None of this is for now. I just don't want the design to rule it out.

### [F1:grill] agent

I've written two things:
- **`docs/adr/0001-fines-charged-on-return.md`:** fines go on the account when lateness is settled, and the balance never includes fines still building up. I wrote it so renewals already fit ("when the copy is returned, or the overdue loan is renewed").
- **The Fine definition in `GLOSSARY.md`:** it now reads "a charge for the open days a loan ran past its due date, made when that lateness is settled". The old wording, "made when a copy is returned late", would have been wrong once renewals exist.

So that holds, no-show fees and renewals stay possible later, this work will be built as follows. None of this changes the four methods or the two errors.

- **The fine calculation won't read the loan's return date.** It will be a pure function that takes the due date, the "until" day, the material and the replacement cost. Returns call it with today; renewals can later call it with the renewal day.
- **A loan can have more than one fine.** Each fine records its `loan_id` and the due date it was counted from. Nothing will assume one fine per loan.
- **Each account entry records what kind of charge it is.** For now that's fine or manual charge; a no-show fee can be added later without changing the account.
- **The blocking threshold will be tied to an action, not to the member.** The account doesn't hold a "blocked" flag. `checkout` compares the balance with the borrowing threshold, and holds can later compare it with their own threshold and raise the same `AccountBlocked`.

Round 3 is about names and rules that your notes changed.

---

❓ **Q22** - **"Fee" vs "Charge"**: The glossary currently lists **Fee** as a word to avoid for Charge, and your next feature is called the *no-show fee*. Should I keep **No-show fee** as the name of that specific kind of charge, alongside Fine and Manual charge, and still avoid "fee" as a general word for any charge?

➡️ Yes. Keep "No-show fee", since that's what staff will say at the desk, and keep the rule that a generic amount owed is called a **charge**, never a "fee". I'll add a note to Charge saying fines, no-show fees and manual charges are the three kinds.

---

❓ **Q23** - **What "Blocked" means**: Blocking now depends on the action: 10.00 for borrowing and 5.00 for holds. My definition, "a member whose balance has reached the limit", stops making sense once there are two thresholds. Should I change it to:
- **Blocking threshold**: the balance at which a member may no longer do a particular action (borrowing: 10.00; placing a hold: 5.00 later). Avoid *limit*, which already means the number of open loans, and avoid *bar*.
- **Blocked**: a member is blocked *from an action* when their balance is at or above that action's threshold.

`AccountBlocked` would carry `member_id`, `balance` and `threshold`, so the same error can be reused for holds.

➡️ Yes.

---

❓ **Q24** - **One exemption rule for children?** Children aren't fined, and later they won't pay no-show fees. Should the rule be "**children pay no automatic charges**", meaning fines and no-show fees now plus anything automatic added later, with manual charges the only thing that can go on a child's account? The alternative is to decide for each charge type separately.

➡️ Yes, one rule. A single policy check on "does this member pay automatic charges" means no-show fees just use it, with nothing new to decide.

---

❓ **Q25** - **Limit across renewals (for later, but it decides what data we keep now)**: You said a renewal fine uses "the usual cap". Consider a DVD with a 12.00 replacement cost that's renewed 10 days late (10.00) and then returned 10 days late again. Should the second fine be:
(a) **10.00**, with each fine limited separately, for a total of 20.00;
(b) **2.00**, with the total fines on one loan limited to the replacement cost, for a total of 12.00?

➡️ (b). The limit is there so lateness never costs more than replacing the copy, and renewing shouldn't get around that. The data needed for this (fines recorded with their `loan_id`) is already in the design, so it's not urgent: I'll note it as a renewal question in the spec if you'd rather decide later.

### [F1:grill] user

Yes to Q22, Q23 and Q24. For Q25, (b) matches what I want. The fine for one loan should never add up to more than the replacement cost, however many times it's renewed. Noting it as a renewal question in the spec is fine.

### [F1:grill] agent

Every question is now answered, so the grilling is finished. I've updated `GLOSSARY.md` with your round 3 answers:
- **Charge** now names its three kinds, and "fee" is avoided except in "no-show fee".
- **No-show fee** is a new entry.
- **Blocking threshold** is a new entry, avoiding "limit" and "bar".
- **Blocked** now means blocked from a particular action.

Please confirm this summary of what we agreed before I write the spec or any code.

## What we agreed

**The interface is exactly as you specified.** `return_copy` keeps its signature and still returns the `Loan`; the `Loan` model doesn't change. The new methods are `balance`, `add_charge` and `pay`, and the new errors are `AccountBlocked` and `InvalidAmount`. An unknown member raises `MemberNotFound`.

**Fines**
- **When:** a fine is charged when a late copy is returned. The balance never includes fines that are still building up (ADR-0001).
- **Days counted:** open days after the due date, up to and including the return day. Sundays don't count, and there's no grace period.
- **Rates:** DVD 1.00 per day, book 0.25 per day, set in `policy`.
- **Limit:** the total fines on one loan never exceed the title's `replacement_cost`. Today a loan only gets one fine, but I'll calculate it as "replacement cost minus fines already charged on this loan" so renewals inherit the right behaviour.
- **Children:** they pay no automatic charges. That covers fines now and no-show fees later.
- **No-fine returns:** a return that costs 0 adds nothing to the account.
- **What a fine records:** its `loan_id`, the due date it was counted from, and a reason.

**The account**
- It keeps a history of entries. Each charge records its kind (fine or manual), amount, date and reason, plus the loan for a fine; payments are recorded too.
- `balance` is total charges minus total payments, and it never drops below zero.
- There's no public method for reading the history yet.

**Accepted amounts:** a `Decimal` or `int` greater than zero with no more than 2 decimal places. A float, zero, a negative amount, NaN, Infinity or a fraction of a penny raises `InvalidAmount`. So does a payment larger than the balance.

**Manual charges:** any reason string is stored exactly as given. They can be added to children's accounts too.

**Blocking**
- `checkout` raises `AccountBlocked` when the balance is at least the borrowing threshold of 10.00. The same rule applies to children.
- The error carries `member_id`, `balance` and `threshold`.
- `checkout` checks in this order: `MemberNotFound` → `AccountBlocked` → `CopyNotAvailable` → `LoanLimitReached`.

**Not changing:** the overdue report stays as it is.

## Out of scope / follow-ups (these go in the spec)
- Blocking members who hold overdue copies.
- Waiving or reducing a charge.
- A public method for reading the account history.
- **Holds:** the hold blocking threshold of 5.00, reusing `AccountBlocked`.
- **The no-show fee:** 1.00, never charged to children.
- **Renewals:**
  - Renewing an overdue loan charges the fine built up so far, worked out as if the copy were returned that day.
  - After that, lateness counts from the new due date.
  - The per-loan limit covers all fines on the loan, however many times it's renewed (decided: option (b)).

If that's right, I'll write `.scratch/overdue-fines/spec.md` and split the work into numbered issues under `.scratch/overdue-fines/issues/`, unless you want me to implement it straight away.

### [F1:grill] user

Yes, that summary matches what I want. Please stop here and don't write the spec, the issues or any code. I'll start those steps myself with /to-spec, then /to-tickets, then /implement.

### [F1:grill] agent

Understood. I'm stopping here: no spec, no issues and no code.

The grilling session changed only two files, and neither is committed:
- **`GLOSSARY.md`** (new): Account, Charge, Fine, No-show fee, Manual charge, Payment, Balance, Blocking threshold and Blocked.
- **`docs/adr/0001-fines-charged-on-return.md`** (new): fines are charged when lateness is settled, and the balance never includes fines that are still building up.

Everything else we agreed exists only in this conversation: rates, the open-day counting, the per-loan limit, the child exemption, the amount rules, the order of checks, the error fields and the follow-up list. If you run `/to-spec` in this same session, it can use the summary above. In a fresh session that context would be lost.

### [F1:to-spec] operator

/to-spec

### [F1:to-spec] agent

Before I write the spec, please confirm the testing approach.

**I'd test through one seam: the public methods of `LendingService`.** That's `checkout`, `return_copy`, `balance`, `add_charge` and `pay`, called on the existing `service` and `clock` fixtures in `tests/conftest.py` (an `InMemoryRepository` with a `FixedClock` that starts on Monday 2 March 2026). It needs nothing new: the existing tests in `test_loans.py` and `test_catalogue.py` already work this way. Every rule we agreed can be seen from there:

- **Open-day counting:** move the clock past a Sunday, return the copy, check `balance`.
- **Rates and the per-loan limit:** a DVD versus a book, and returning a long time late against `replacement_cost`.
- **The child exemption:** a late return by `kid` leaves the balance at 0, while a manual charge still counts.
- **Blocking:** `checkout` raises `AccountBlocked` at 10.00 but not at 9.99, and the error carries `member_id`, `balance` and `threshold`. It's also raised before `CopyNotAvailable`.
- **Amount rules:** `InvalidAmount` for a float, zero, a negative amount, a fraction of a penny, NaN, Infinity, or paying more than the balance.
- **Unknown members:** `MemberNotFound` from `balance`, `add_charge` and `pay`.
- **No change to `return_copy`:** its return value is unchanged.

**I'd leave out a second seam** that tests `policy`'s fine calculation function directly. It would make the open-day maths quicker to test in isolation, but it would tie the tests to a function that's an internal detail. Everything it would cover is already reachable through the service with the `FixedClock`.

Does testing only through `LendingService` match what you expect? If so, I'll write the spec and save it as `.scratch/overdue-fines/spec.md` with `Status: ready-for-agent`.

### [F1:to-spec] user

Yes, testing only through `LendingService` is fine with me. Go ahead and write the spec.

### [F1:to-spec] agent

I've written the spec to `.scratch/overdue-fines/spec.md` and marked it `ready-for-agent`, so `/to-tickets` can pick it up. Nothing else changed: no issues, no code and no commits.

It contains everything from the grilling session, including 38 user stories. All testing goes through `LendingService` only, with specific scenarios built on the existing fixture dates. I checked the dates and amounts against the calendar; for example, a DVD due Mon 9 Mar and returned Wed 25 Mar is 14 open days late, which the per-loan limit brings down to 12.00. The future work on holds, no-show fees and renewals is listed under Out of Scope. Your answer to Q25 is recorded in Further Notes: the replacement-cost limit covers all fines on one loan, however many times it's renewed.

I made four small decisions we hadn't discussed. They're in the spec, so check them before `/to-tickets`:
- **Unknown members are checked first.** `balance`, `add_charge` and `pay` look up the member before checking the amount, so an unknown member always gets `MemberNotFound`, even with a bad amount.
- **`InvalidAmount` carries the rejected `amount`.** That matches how the other errors carry their fields.
- **`True` and `False` are not accepted as amounts.** Python treats them as integers, so without this an `int` check would accept `True` as 1.
- **The README gets one line in its Concepts section** about accounts, fines and blocking.

### [F1:to-tickets] operator

/to-tickets

### [F1:to-tickets] agent

Here is how I'd split the work, based on the spec. Every ticket goes from policy through to service-level tests and ends with the suite passing. I didn't find anything worth refactoring before starting.

1. **Member account: manual charges and balance**
   - **Blocked by:** none (can start immediately).
   - **What it delivers:** staff can add a manual charge with a reason and get the new balance back, and `balance` reports what the member owes.
   - **Includes:** the account history in the repository, the amount checks (`InvalidAmount` for floats, zero, negative amounts, fractions of a penny, NaN and Infinity; `int` accepted, `bool` rejected), and `MemberNotFound` for unknown members. Manual charges work on children's accounts too, and the README gets an "accounts" line.

2. **Payments**
   - **Blocked by:** 1.
   - **What it delivers:** a member can pay part or all of what they owe and gets the new balance back. A payment larger than the balance, or any payment when nothing is owed, raises `InvalidAmount`. `pay` raises `MemberNotFound` for unknown members.

3. **Fines on late return**
   - **Blocked by:** 1.
   - **What it delivers:** `return_copy` charges a fine for the open days after the due date, up to and including the return day. That's DVD 1.00 and book 0.25 per day, with Sundays not counted and no grace period.
   - **Includes:** the per-loan limit at replacement cost (calculated as "replacement cost minus fines already on this loan"), no automatic charges for children, and no account entry when the fine is 0. Each fine records its loan, the due date it counted from and a reason. The return value is unchanged, and the README gets a "fines" line.

4. **Blocking at checkout**
   - **Blocked by:** 1 and 2.
   - **What it delivers:** `checkout` raises `AccountBlocked` (`member_id`, `balance`, `threshold`) when the balance is at least 10.00, for adults and children alike.
   - **Includes:** 9.99 still borrows, a payment that brings the balance below 10.00 lets the member borrow again, and the order of checks is `MemberNotFound` → `AccountBlocked` → `CopyNotAvailable` → `LoanLimitReached`. The README gets a "blocking" line.

Ticket 1 comes first. After that, tickets 2 and 3 can run in parallel, and ticket 4 can start once 2 is done.

Three questions before I publish:
- **Ticket 4's dependency on ticket 2:** it depends on 2 only because of the "paying unblocks" check. Should I drop that dependency and move the check into ticket 2? Then ticket 2 would also be blocked by 4, so the order would flip but it wouldn't run in parallel any more. My suggestion is to keep the dependency as it is.
- **Splitting ticket 3:** it's the largest ticket. Should I split it into "fines with daily rates and open-day counting" and "per-loan limit and the child exemption"? I'd keep it as one, because the whole thing fits easily in one context window and the limit is just one `min`.
- **Overall size:** do four tickets feel right to you, or too fine or too coarse?

### [F1:to-tickets] user

Four tickets feel right to me. Keep ticket 4 depending on ticket 2, and keep ticket 3 as one ticket. I don't mind the details beyond that. Go ahead and publish.

### [F1:to-tickets] agent

I've published the four tickets in `.scratch/overdue-fines/issues/`. Each one is marked `ready-for-agent`, and none of them is committed yet:

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Member account: manual charges and balance | None |
| 02 | Payments | 01 |
| 03 | Fines on late return | 01 |
| 04 | Blocking at checkout | 01, 02 |

Ticket 01 can start now. After it's done, 02 and 03 can run in parallel, and 04 can start once 02 is done. Each ticket links back to the spec and `GLOSSARY.md`, and ticket 03 also links to ADR-0001. The acceptance criteria use the exact dates and amounts from the spec's test scenarios. I didn't change the spec itself.

### [F1:implement:01] operator

/implement .scratch/overdue-fines/issues/01-member-account-manual-charges-and-balance.md

### [F1:implement:01] agent

I've implemented ticket 01 (member account: manual charges and balance) and committed it to `main` as `6f9ef9e`. All 35 tests pass: the 18 existing ones, unchanged, plus 17 new ones in `tests/test_account.py`. Pyright reports no errors.

**What changed**
- **Account entries:** each member's account is a list of entries stored in the repository. An entry records its kind, amount, the day it was recorded (from the injected clock) and the reason. It also has optional `loan_id` and `counted_from` fields for fines in ticket 03. For now the only kind is `MANUAL_CHARGE`.
- **`balance(member_id)`:** adds up the member's entries, so it is never stored separately. It is 0 for a member who has never been charged.
- **`add_charge(member_id, amount, reason)`:** looks up the member first (so unknown members get `MemberNotFound`), then checks the amount, records the charge and returns the new balance.
- **`InvalidAmount`:** new error carrying the rejected amount. The check is a private helper, `_money`, in `service.py` so payments can reuse it. It rejects zero, negative amounts, fractions of a penny, NaN, infinity, floats and bools, and converts `int` to `Decimal`.
- **README:** Concepts has a new line on accounts and balance.

**Decision for you:** the decimal-places check is exact, so `Decimal("1.500")` is rejected as having 3 decimal places, even though it equals 1.50. That follows the spec's wording. I tried normalising instead, but that rounds at very high precision and wrongly accepted `1.0000…0001`. If 1.500 should be accepted, it needs a different exact check.

**Review**
- **Standards:** no hard breaches. Three fixes made:
  - an out-of-order import in `service.py`;
  - "whole pennies" wording that could be read as integer pence, now "at most 2 decimal places";
  - `AccountEntry` and `EntryKind` exports in `__init__.py` that nothing asked for (the Spec reviewer flagged these too), now removed.
- **Spec:** every acceptance criterion is implemented and tested. One limit: the test that the reason is "stored exactly as given" can only show that odd reasons are accepted, because the spec has no way to read account history.
- **Left for ticket 02:** both reviewers noted that `balance` adds up all entries without checking their kind. That is correct while only charges exist. When payments arrive, ticket 02 needs to subtract them, ideally with a sign on the entry kind kept in one place.

The `tdd` skill isn't available through the Skill tool, so I followed its instructions from the file on disk. The seam it asks you to confirm was already set by the ticket: tests go through `LendingService` only.

Two things to clean up:
- The Spec reviewer left a scratch file at `/tmp/l1pl2_probe/probe.py`, outside the repo. Deleting it needed permission, so it's still there and you can delete it.
- `.scratch/`, `GLOSSARY.md` and `docs/adr/` were already untracked before I started, so I left them out of the commit, along with the `__pycache__` folders.

### [F1:implement:02] operator

/implement .scratch/overdue-fines/issues/02-payments.md

### [F1:implement:02] agent

Ticket **02: Payments** is done and committed to `main` as `bc046e4`. All 54 tests pass, including the existing ones, which I didn't change.

**What changed**
- **`LendingService.pay(member_id, amount) -> Decimal`** (`src/lending/service.py`): it checks the member exists first, then applies the same amount checks as `add_charge`. It raises `InvalidAmount` for any payment above the balance, which also means any payment when nothing is owed is refused. Otherwise it records a payment entry and returns the new balance.
- **Payments are stored as positive amounts** with a new entry kind, `EntryKind.PAYMENT` (`src/lending/models.py`). `balance` subtracts them. Every other kind counts as a charge, so fines can be added in ticket 03 without changing `balance`.
- **Tests:** `tests/test_payments.py` has 19 tests covering every acceptance criterion, all going through `LendingService` with the shared fixtures. The overpayment check went in with the first test, so I disabled it briefly and confirmed 5 tests then fail.
- **Docs:** one line on payments in the README's Concepts section, and the `InvalidAmount` docstring now mentions the overpayment case.

**Process notes**
- **No typechecking:** neither mypy nor pyright is installed, so tests were the only check.
- **No TDD skill:** `mattpocock-skills:tdd` isn't installed, so I did the red/green steps by hand.

**Review findings I left alone**
- **Repeated steps in `pay` and `add_charge`:** I'd pull the shared part into one helper when ticket 03 adds fine entries and there's a third copy.
- **Placeholder payment reason:** every payment is stored with the reason `"payment"`. The spec doesn't say what a payment's reason should be, so this only needs a decision if account history is ever shown.
- **`Decimal("5.500")` is rejected** for its trailing zero. That comes from ticket 01's amount check and affects `add_charge` the same way. It's a literal reading of "no more than 2 decimal places", so I didn't change it.

I didn't update the ticket's `Status:` line or tick its checkboxes.

### [F1:implement:03] operator

/implement .scratch/overdue-fines/issues/03-fines-on-late-return.md

### [F1:implement:03] agent

Late returns now charge a fine automatically. All 65 tests pass, pyright reports 0 errors, and the work is committed to `main` as `f89a00b` ("Charge fines on late return").

**How it works**
- **Rules:** the daily rates (DVD 1.00, book 0.25) and the child exemption are in `src/lending/policy.py`, next to the other circulation numbers.
- **Calculation:** `policy.fine(due_on, until, material, replacement_cost, already_fined)` takes the smaller of (open late days × rate) and (replacement cost minus fines already charged on the loan). It never reads the loan's return date, so a renewal can call it later with the renewal day.
- **Charging:** `return_copy` keeps its signature and still returns the closed loan. It now also records a fine entry with the loan, the due date it counted from, the day it was charged and a reason like "late return of D1". A fine of 0 records nothing, and children are never charged.
- **Tests:** `tests/test_fines.py` has 11 tests, all going through `LendingService` with the shared fixtures. They cover every scenario in the ticket, plus one extra test that a fine can be paid off. The existing tests and the overdue report are unchanged.
- **README:** Concepts has a new line on fines.

There's no `tdd` skill installed here, so I did red-green by hand: 6 of the new tests failed before the change and all passed after.

**Review**
- **Spec:** nothing missing or wrong. The reviewer checked the date arithmetic by hand. Two requirements aren't covered by tests: that a zero fine records no entry, and what a fine entry contains. Neither can be seen through `LendingService`, which is the only thing the tests may call.
- **Standards:** no breaches of the repo's documented rules. It noted three possible tidy-ups, none blocking, and I left them alone:
  - The code that builds an account entry now appears three times in the service and could share a helper.
  - Adding up a loan's earlier fines could become a `fines_on(loan_id)` lookup on the repository.
  - Getting from a loan to its title goes through the copy, which could sit behind one helper.

I didn't tick the checklist or change the `Status:` line in the ticket file, since the `.scratch/` directory isn't tracked in git. I can mark it done if you want.

### [F1:implement:04] operator

/implement .scratch/overdue-fines/issues/04-blocking-at-checkout.md

### [F1:implement:04] agent

I've implemented **04: Blocking at checkout** and committed it as `fa20d28`. All 75 tests pass and pyright reports no errors.

**What changed**
- **New error:** `AccountBlocked(LendingError)` in `src/lending/errors.py`, carrying `member_id`, `balance` and `threshold`.
- **Threshold:** `BORROWING_BLOCKING_THRESHOLD = Decimal("10.00")` lives in `src/lending/policy.py`.
- **`checkout`:** it now compares the member's balance with the threshold, checking in the order the ticket gives: `MemberNotFound` → `AccountBlocked` → `CopyNotAvailable` → `LoanLimitReached`. Nothing is stored on the member.
- **README:** Concepts has a new Blocking line.
- **Tests:** `tests/test_blocking.py` has 10 tests, all going through `LendingService` with `add_charge`/`pay`. They cover every item on the ticket's checklist plus a few edge cases: owing more than 10.00, paying down to exactly 10.00 (still blocked), and a blocked member who is also at their loan limit. No existing test was changed.

**Process notes**
- **No `tdd` skill:** it isn't installed in this session, so I worked test-first by hand: the first test failed, then I wrote the code. Most later tests passed immediately because the check already covered them. To be sure the ordering test isn't vacuous, I temporarily moved the copy check ahead of the block; that test failed, and I put the code back.
- **Review:** neither reviewer found a spec problem or a breach of the repo's documented standards. I acted on three minor suggestions: a type annotation on the constant, test names that no longer say "ten pounds", and a test proving blocking is reported before the loan limit. I kept the error's docstring line about reusing it for holds, since the ticket asks for that.

I didn't commit the untracked `.scratch/`, `GLOSSARY.md` and `docs/adr/`, which were already there before this work. I also didn't change the ticket's `Status:` line or tick its checklist; say if you want that done.

### [F2:grill] operator

/grill-with-docs When every copy of a title is out, members can only keep asking at the desk. Add holds: a member
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

### [F2:grill] agent

I've read the code, the overdue-fines spec, ADR-0001 and `GLOSSARY.md`. A few things are already decided in earlier work, so I'll build on them rather than ask again:

- **Hold blocking threshold is 5.00**, and a refusal raises `AccountBlocked` (spec, Out of Scope).
- **No-show fee is 1.00.** It's charged when a set-aside copy isn't collected within the pickup time, it goes on the same account, it counts towards blocks, and children don't pay it (spec + glossary).
- The glossary already uses "hold", "set aside", "collect" and "pickup time", but doesn't define them yet.

Round 1 (everything that doesn't depend on another open answer):

---

❓ **Q1** - **Vocabulary**: I'd like to add these words to the glossary:
- **Hold**: a member's request for the next copy of a title.
- **Queue**: the members waiting on a title, first placed first. Your brief says "line"; one word should win.
- **Set aside**: a returned copy kept on the hold shelf for one hold.
- **Ready**: a hold whose copy has been set aside.
- **Pickup time**: how long a ready hold waits before it lapses. The last day is the **pickup-by date**.
- **Collect**: a member checking out the copy set aside for them.
- **Expire**: the daily job ending an uncollected ready hold.

Use **queue** (avoid "line" and "waitlist"), **collect** (avoid "pick up" as a verb) and **expire** (avoid "lapse" and "clear")?

➡️ Yes, those terms, with those words to avoid.

---

❓ **Q2** - **When a hold may be placed**: The brief says "when every copy of a title is out". I read that as **no copy of the title is `AVAILABLE`**. Copies on loan, or set aside for someone else, count as out. Two edge cases:
- (a) A title with no copies, or only withdrawn ones. Nothing will ever come back.
- (b) A title with a copy on the shelf.

Refuse both with `HoldNotAllowed`?

➡️ Yes. A hold is allowed only when the title has at least one copy that isn't withdrawn and none of its copies are available. Otherwise `HoldNotAllowed`.

---

❓ **Q3** - **Duplicate and pointless holds**: Refuse with `HoldNotAllowed` if the member:
- (a) already has a waiting or ready hold on the same title, or
- (b) currently has a copy of that title on loan?

➡️ Yes to both. (b) also means a returned copy can never be set aside for the member who just returned it.

---

❓ **Q4** - **Order of checks in `place_hold`**: `checkout` currently checks member, then block, then copy lookup, then state. Mirror that: `MemberNotFound` → `AccountBlocked` (5.00, children included) → `TitleNotFound` → `HoldNotAllowed`?

➡️ Yes, the same order as `checkout`, so a blocked member hears about the block first.

---

❓ **Q5** - **Limits on holds**: Should there be a cap on how many holds a member can have? Should active holds count towards the loan limit (glossary: "limit" means open loans)?

➡️ No cap on holds. Holds don't count towards the loan limit; it's checked at collection like any checkout.

---

❓ **Q6** - **Pickup time**: "A few days." My proposal:
- The pickup-by date is the day the copy was set aside + **7 calendar days**, moved to the next open day if it lands on a Sunday. That mirrors `due_date`.
- The hold can be collected up to and including the pickup-by date.
- The number lives in `policy`.

Or would you prefer a different count, or counting open days only?

➡️ Yes: 7 calendar days, never ending on a closed day, collectable through the pickup-by date.

---

❓ **Q7** - **Return when someone is waiting**: When `return_copy` gets back a copy whose title has waiting holds:
- the copy becomes `ON_HOLD_SHELF`;
- the first waiting hold becomes `READY`, with `copy_id` and `pickup_by` set;
- with no waiting holds, the copy goes to `AVAILABLE` as today.

The fine is still charged and the returned `Loan` is unchanged. Is "first" the earliest placed hold, with ties on the same day broken by placement order?

➡️ Yes.

---

❓ **Q8** - **Collecting**: A ready hold is collected through the existing `checkout(member_id, copy_id)` on the set-aside copy. That hold becomes `FULFILLED`. Anyone else checking out that copy gets `CopyNotAvailable`.

Does the collecting member still go through the normal checks? That means the 10.00 borrowing block and the loan limit, so a blocked member can't collect until they pay down, and the hold may expire meanwhile.

➡️ Yes. Collection is an ordinary checkout with all the normal checks. Only the copy-status check changes, so that "set aside for *this* member" counts as available to them.

---

❓ **Q9** - **The daily job (`expire_holds`)**: For each ready hold whose pickup-by date is before today:
- it becomes `EXPIRED`;
- a 1.00 no-show fee is charged, unless the member is a child. That's a new entry kind, with a reason like "uncollected hold H0001 (D1)";
- the copy passes to the next waiting hold, whose pickup-by date counts from the day the job ran. With nobody waiting, the copy goes back to `AVAILABLE`.

Waiting holds never expire, however old. If the job skips days, it catches up on its next run. It returns only the holds it expired.

➡️ Yes to all of it.

---

❓ **Q10** - **Cancelling**: `cancel_hold` works on waiting or ready holds.
- Cancelling a ready hold passes its copy on exactly as in Q9, with **no** no-show fee.
- Cancelling a fulfilled, cancelled or expired hold raises `HoldNotAllowed`.
- An unknown id raises `HoldNotFound`.

The service does no who-may-cancel check, same as today.

➡️ Yes. Cancelling ahead of the pickup-by date is the polite thing to do, so it should cost nothing.

---

❓ **Q11** - **`holds_for`**: "Active" means waiting and ready, in queue order. A ready hold sits where it was in the queue, which is at the front. An unknown ISBN raises `TitleNotFound`.

➡️ Yes.

---

❓ **Q12** - **A copy appears on the shelf while people are waiting**: `add_copy` creates an `AVAILABLE` copy even if the title has a queue.
- (a) Should `add_copy` set the new copy aside for the first waiting hold?
- (b) Or leave it on the shelf for anyone, and a member who checks out a copy of a title they have a waiting hold on has that hold fulfilled? (b) needs a rule like that anyway, or they'd keep a pointless place in the queue.

➡️ (b). `add_copy` stays as it is. Checking out any copy of a title fulfils the member's waiting hold on it. Setting new stock aside is out of scope.

---

❓ **Q13** - **Withdrawals with a queue**: `withdraw_copy` already refuses anything not `AVAILABLE`, so a set-aside copy can't be withdrawn. If every remaining copy is withdrawn while holds are waiting, those holds wait forever. Accept that as out of scope?

➡️ Yes, out of scope for now. Staff can cancel those holds.

### [F2:grill] user

All of Q1-Q13 are fine as you've written them. The no-show fee and the 5.00 hold block were settled earlier and should be written down in the project; go by what's there.

### [F2:grill] agent

I added a **Holds** section to `GLOSSARY.md` with the seven terms. Agreed. I'll take the 5.00 hold blocking threshold and the 1.00 no-show fee (child exemption included, counts towards both blocks) from the overdue-fines spec and the glossary as written.

Your answers opened up a few more questions:

---

❓ **Q14** - **Collecting late, before the job has run**: Q6 says a hold can be collected through the pickup-by date. But only `expire_holds` moves a hold to `EXPIRED`. Suppose the job skipped a day and the member turns up the day after the pickup-by date: the hold still says `READY`. Should `checkout` refuse them, or let them collect?

This also touches ADR-0001, which says the balance never changes just because a day passed. If the no-show fee is charged only when the job expires the hold, that's a dated event, and the ADR's spirit holds.

➡️ Let them collect. A hold ends only when it's collected, cancelled or expired by the job. There's no fee if they collect before the job runs. `checkout` never looks at the pickup-by date.

---

❓ **Q15** - **A member with a ready hold borrows a different copy of that title**: This can happen when `add_copy` puts new stock on the shelf (Q12). Should their ready hold become `FULFILLED`, with the set-aside copy passed to the next waiting hold or the shelf, as in Q9 but with no no-show fee?

And for both this case and Q12's waiting-hold case: does the hold's `copy_id` record the copy they actually borrowed? For Q12 that means `copy_id` is set and `pickup_by` stays `None`.

➡️ Yes to both. `copy_id` on a fulfilled hold is always the copy the member walked out with.

---

❓ **Q16** - **What we produce at the end**: Should I write it up the way overdue-fines was?
- `.scratch/holds/spec.md`, in the same shape.
- Vertical-slice issues under `.scratch/holds/issues/`, roughly:
  1. place, cancel and list holds, with blocking and refusals;
  2. setting a copy aside on return, and collecting through `checkout`;
  3. the daily expiry job and the no-show fee;
  4. checkout of another copy fulfilling a hold (Q12/Q15).
- A README Concepts line about holds.
- No ADR: none of these decisions is both hard to reverse and surprising.

➡️ Yes. Write the spec and four issues, all `ready-for-agent`, with no ADR.

### [F2:grill] user

Q14-Q16 are fine as written. Also, for later: renewals are the next feature after holds. (1) While anyone is still waiting in the queue for a title, loans of that title can't be renewed. A hold that is already ready on the hold shelf doesn't count, because that person already has their copy. (2) Renewals are only for people who are paid up: if the member's balance shows anything at all owed when they ask, they can't renew until they've paid. That's not part of this work; I'm telling you so the holds design doesn't make it hard to add.

### [F2:grill] agent

Every question is answered, and I've written up the holds design: a glossary update, a spec and four tickets. Nothing in `src/` has changed yet, and nothing is committed.

**What's written**
- **`GLOSSARY.md`** has a new "Holds" section defining Hold, Queue, Set aside, Ready, Pickup time, Collect and Expire, each with the words to avoid. Earlier entries already used some of these terms without defining them; those definitions now exist.
- **`.scratch/holds/spec.md`** follows the shape of the overdue-fines spec: the interface you fixed, the order `place_hold` checks things in, and how collecting through `checkout` and the daily expiry job work. It also has concrete test cases with dates from the shared test setup.
  - It takes the 5.00 hold block and the 1.00 no-show fee from the overdue-fines spec as written there.
- **Four tickets** in `.scratch/holds/issues/`, all `ready-for-agent`:
  1. Place, cancel and list holds (can start now)
  2. Set aside on return, and collect (needs 01)
  3. Expire uncollected holds, with the no-show fee (needs 02)
  4. Borrowing another copy fulfils a hold (needs 02, so it can be built alongside 03)
- **No ADR.** None of these decisions is both hard to undo and surprising.

**Renewals**

Your two rules are recorded under the spec's Further Notes:
- **"Someone is waiting":** it's enough to check whether any hold on the title is still `WAITING`. A ready hold has its own status, so it never gets counted by mistake. The spec makes "waiting holds on a title" a single repository query that renewals can reuse.
- **"Paid up":** this is the existing blocking idea with a renewal threshold of 0.01, and it reuses `AccountBlocked`.

**Decision for you:** a fine that is still building up on an overdue loan isn't part of the balance (ADR-0001). So a member with nothing owed could renew an overdue loan, and the renewal would then charge them the fine. The spec flags this for when you design renewals.

### [F2:grill] user

Thanks, that all matches what I asked for. For renewals, I meant what the balance shows when the member asks, so the overdue-fine question can wait until we design renewals. I'll run /to-spec next.

### [F2:grill] agent

I've updated the renewals note in `.scratch/holds/spec.md`. It now records that the paid-up check uses the balance as it stands when the member asks. It also lists the overdue-fine question as open until renewals are designed.

Before you run `/to-spec`: `.scratch/holds/spec.md` and its four tickets already exist from this session. Point `/to-spec` at that file to refine it, or it may write a second holds spec alongside it.

### [F2:to-spec] operator

/to-spec

### [F2:to-spec] agent

Before I finalise the spec, here are the test seams I'm planning. Please check they match what you expect.

**One seam: the public methods of `LendingService`.** No new seams.

- **Placing, cancelling and listing holds:** tests call `place_hold`, `cancel_hold` and `holds_for`, and check what comes back or what error is raised.
- **Setting a copy aside and collecting it:** tests go through the existing `return_copy` and `checkout`. They see the result through `get_copy` (copy status), `available_copies` and `holds_for`.
- **The daily job:** tests call `expire_holds()` directly and move the existing `FixedClock` to control "today". Nothing models a scheduler; running the job once a day is the caller's job.
- **No-show fees and the hold block:** tests check them through `balance`, and set balances up with `add_charge` and `pay`, as the blocking tests do.
- **Nothing reaches into the repository, account entries or policy functions.** For example, no test calls the pickup-by date function directly. It's covered by "a copy set aside on Sun 8 Mar can be collected until Mon 16 Mar".

Prior art: `tests/test_blocking.py` and `tests/test_fines.py`, with the shared `service`/`clock` fixtures. The holds tests go in a new module of their own.

If that matches, I'll update the existing `.scratch/holds/spec.md` to this template rather than create a second spec. It's already in nearly this shape and labelled `ready-for-agent`. The four tickets stay as they are.

### [F2:to-spec] user

That matches what I expect. Testing through the public LendingService methods, with the clock moved for the daily job, is fine. Go ahead and update the existing spec rather than writing a second one.

### [F2:to-spec] agent

I updated the existing `.scratch/holds/spec.md` in place; no second spec was written. It follows the `/to-spec` template and keeps its `Status: ready-for-agent` line.

What changed:
- **User Stories** grew from 30 to 37. The new ones cover:
  - a refused hold leaving nothing behind;
  - the no-show fee's reason, and the fee counting towards both blocks;
  - set-aside copies being kept out of the available copies and not withdrawable;
  - the daily job using the injected clock and being safe to run twice;
  - `return_copy` and `checkout` keeping their signatures;
  - the queue telling waiting holds apart from ready ones, for renewals.
- **Testing Decisions** now states the seam we agreed:
  - all tests go through the public `LendingService` methods;
  - `expire_holds()` is called directly and the `FixedClock` is moved to set "today";
  - nothing models a scheduler;
  - no test reaches into the repository, the account entries or the policy functions.
- **Following the template's rules:** I replaced the constant-name snippet in Implementation Decisions with plain prose, and swapped file paths for names like "the overdue-fines spec" or "the existing blocking and fines tests".

The four tickets under `.scratch/holds/issues/` and the decisions themselves are unchanged. Nothing is committed: `GLOSSARY.md` is modified and `.scratch/holds/` is new and untracked.

### [F2:to-tickets] operator

/to-tickets

### [F2:to-tickets] agent

Tickets for holds already exist from the design session: four of them, in `.scratch/holds/issues/`. I checked them against the updated spec and the code. Here's the breakdown as it stands, plus two things to decide before I republish.

**Proposed breakdown**

1. **Place, cancel and list holds**
   - **Blocked by:** none (can start immediately).
   - **Delivers:** `place_hold`, with the full check order (member, then the 5.00 hold block, then title, then the four hold refusals). Also `cancel_hold` for waiting holds and `holds_for` in queue order, plus the `Hold` and `HoldStatus` models, the two new errors and the hold blocking threshold in policy. Every hold stays waiting, because no copy is set aside yet.
2. **Set aside on return, and collect**
   - **Blocked by:** 01.
   - **Delivers:**
     - a returned copy goes on the hold shelf for the first waiting hold, which becomes ready with a pickup-by date (7 days, never a Sunday);
     - the member collects through the normal `checkout`, with the normal checks;
     - anyone else is refused the copy;
     - cancelling a ready hold passes its copy on.
   - "Passing a copy on" is built here as one rule, so 03 and 04 can reuse it.
3. **Expire uncollected holds**
   - **Blocked by:** 02.
   - **Delivers:** `expire_holds()`. It expires overdue ready holds, charges the 1.00 no-show fee (children exempt) and passes each copy on. Running it twice the same day does nothing extra, and if it missed days it catches up on its next run.
4. **Borrowing another copy fulfils a hold**
   - **Blocked by:** 02.
   - **Delivers:** checking out any copy of a title fulfils the member's active hold on it, recording the copy they actually borrowed. If that hold was ready on a different copy, that copy is passed on. 03 and 04 can be built in parallel.

**Questions**

- **Q1 - A small refactor first?** `place_hold`, and later renewals, need the same "is the balance at or above this threshold? Then raise `AccountBlocked`" check that `checkout` does inline today. I could pull it out into a single shared check (existing tests unchanged) as a ticket 00, or just do it as the first step of 01.
  ➡️ Fold it into 01. It's a few lines and doesn't deserve its own ticket.
- **Q2 - A temporary gap between 01 and 04.** Suppose a member with a waiting hold borrows a newly added copy of that title (`add_copy` mid-queue). Until 04 lands, their hold stays waiting, and a later return could set a copy aside for someone who already has one. I could close the gap early by moving "checkout fulfils a *waiting* hold" into 01, which doesn't need set-aside, and leave 04 handling only the ready-on-a-different-copy case.
  ➡️ Keep it as is. The gap needs new stock to arrive mid-queue, it's never visible in any ticket's own tests, and 04 closes it.
- **Q3 - Granularity.** 02 is the largest ticket (set-aside, collecting and cancelling a ready hold), but it's one connected path and fits one context window. Splitting off "cancelling a ready hold" would leave a ticket too thin to stand on its own.
  ➡️ Keep four tickets with the edges above: 01 → 02 → (03 ∥ 04).

If all three recommendations are fine, I'll republish the four files: same numbering and `ready-for-agent` status. The one change is adding the shared blocking check to 01. Otherwise, tell me which to change.

### [F2:to-tickets] user

All three recommendations are fine: fold the shared blocking check into 01, keep the 01/04 gap as it is, and keep four tickets as proposed. Go ahead and republish.

### [F2:to-tickets] agent

The four holds tickets are republished in `.scratch/holds/issues/`, all `ready-for-agent`:

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Place, cancel and list holds | None (can start immediately) |
| 02 | Set aside on return, and collect | 01 |
| 03 | Expire uncollected holds | 02 |
| 04 | Borrowing another copy fulfils a hold | 02 |

Once 02 is done, 03 and 04 can be worked on at the same time.

Changes from the earlier version:
- **01** now starts with the shared blocking check. `checkout`'s inline check becomes one rule that takes the threshold as an input, and `place_hold` uses it with the 5.00 hold threshold. The existing blocking tests have to pass unchanged before any hold code is written, and there's a new acceptance criterion for this.
- **03** now refers to the decision record as "ADR-0001" instead of by its file path.

The 01/04 gap stays as you agreed. The spec isn't changed. Nothing is committed yet: `GLOSSARY.md` is modified and `.scratch/holds/` is new and untracked.

### [F2:implement:01] operator

/implement .scratch/holds/issues/01-place-cancel-and-list-holds.md

### [F2:implement:01] agent

I've implemented ticket **01: Place, cancel and list holds** and committed it to `main` as `95946aa`. All 101 tests pass (the 75 existing ones unchanged, plus 26 new ones in `tests/test_holds.py`), and pyright reports no errors.

**What's in it**
- **Shared blocking check:** I did this first, before any hold code. `checkout`'s inline check became `_check_not_blocked(member_id, threshold)` in `src/lending/service.py`, and the existing blocking tests passed unchanged before I went on.
- **Placing a hold:** `place_hold` checks in the order the ticket gives: `MemberNotFound` → `AccountBlocked` → `TitleNotFound` → `HoldNotAllowed`. The 5.00 hold blocking threshold is in `policy.HOLD_BLOCKING_THRESHOLD`. A hold id is only taken after every check passes, so a refused hold creates nothing and doesn't use up a number.
- **Cancelling and listing:** `cancel_hold` cancels an active hold and refuses one that's already cancelled. `holds_for` returns the title's active holds, earliest placed first.
- **Models and errors:** `Hold` and `HoldStatus` are exported from the package. `HoldNotAllowed` carries `reason` and `HoldNotFound` carries `hold_id`. The repository stores holds, looks one up by id, and lists a title's holds in placement order.
- **README:** Concepts has a new Hold bullet that gives the 5.00 threshold.
- **Not added yet:** the repository query for a title's waiting holds and passing on a ready hold's copy when it's cancelled. Nothing in this ticket uses them; they come in ticket 02.

**Review**
- **Spec:** no missing or wrong requirements. It noted a few extra tests (re-placing a hold after cancelling, a blocked member asking about an unknown title), which follow from the spec. It also flagged a sorting edge case: past 9,999 holds, string ids like `H10000` sort before `H9999`. Loan ids already have the same problem, so I left it.
- **Standards:** no hard violations. I fixed two things:
  - The README Blocking bullet still said the balance is only checked at checkout; it now covers placing a hold too.
  - I renamed the repository's `holds_on` to `holds_of` to match `copies_of` and `loans_of`.
  - The other points (the `FULFILLED` status, the `holds_for` name, the status values and fields not used yet, and `HoldNotAllowed` carrying a free-text `reason`) are all set by the ticket's interface, so I left them.

**Left out of the commit**
- `GLOSSARY.md` and `.scratch/holds/` are your existing uncommitted changes. That means the ticket checklist isn't ticked off.
- The `__pycache__/*.pyc` files are tracked in git, so every test run changes them. You may want to untrack them and add them to `.gitignore`.

The ticket asks for a `tdd` skill, but it isn't installed here, so I wrote the failing tests and then the code by hand, testing only through `LendingService`.

### [F2:implement:02] operator

/implement .scratch/holds/issues/02-set-aside-on-return-and-collect.md

### [F2:implement:02] agent

Ticket **02: Set aside on return, and collect** is done and committed to `main` as `c1341a3`. The full suite passes (all 101 existing tests plus 18 new ones, 119 total) and pyright reports no errors.

**What changed**
- **Return:** `return_copy` closes the loan and charges any fine exactly as before. It then passes the copy on to the first hold that is still waiting. That hold becomes `READY`, with the copy and a pickup-by date. The copy becomes `ON_HOLD_SHELF`. With nobody waiting, it goes back on the shelf. This is the one passing-on rule, `_pass_on` in `src/lending/service.py`, so tickets 03 and 04 can reuse it.
- **Pickup time:** `PICKUP_DAYS = 7` and `pickup_by_date()` are in `policy.py`, written the same way as `due_date`.
- **Collect:** `checkout` lets a set-aside copy go only to the member it was set aside for, and marks their hold `FULFILLED`. Everyone else gets `CopyNotAvailable`. The blocking and loan-limit checks run in the same order as before and still apply. A refused checkout leaves the hold `READY`. `checkout` never looks at `pickup_by`.
- **Cancel:** cancelling a ready hold costs nothing and passes its copy on, with a pickup-by date counted from the cancel day.
- **Also:** a repository query for the waiting holds on a title (the spec wants this reused later for renewals), and README Concepts lines for `ON_HOLD_SHELF` and the 7-day pickup time.

On scope: `checkout` only fulfils the hold that the borrowed copy was set aside for. If a member borrows a *different* copy of the title, their hold is left alone; ticket 04 covers that.

**Review:** the spec review found every acceptance item covered and no defects. The standards review found no breaches of the documented rules, only a few judgement calls. I fixed the cheap ones: a test name that used "hold back", which the glossary says to avoid; two unclear names in `service.py`; and a README line that said a hold waits only "until a copy comes back" (it can also be cancelled).

Two other things:
- **TDD skill:** the `tdd` skill isn't installed, so I did the red-green cycles by hand through `LendingService`.
- **Left out of the commit:** these were already in the working tree before I started — your `GLOSSARY.md` holds vocabulary, the untracked `.scratch/holds/` folder (spec and tickets) and the tracked `__pycache__` files. I also haven't ticked the ticket's checklist, since that file isn't under version control.

### [F2:implement:03] operator

/implement .scratch/holds/issues/03-expire-uncollected-holds.md

### [F2:implement:03] agent

I've implemented ticket **03: Expire uncollected holds** and committed it to `main` as `cf68ad1`. All 133 tests pass (the 119 existing ones are unchanged) and pyright reports no errors.

**What the job does:** `LendingService.expire_holds()` (`src/lending/service.py`) looks at every ready hold whose pickup-by date has passed and works through them in queue order. For each one it:
- marks the hold `EXPIRED`;
- charges the member a 1.00 no-show fee, with a reason like "uncollected hold H0001 (D1)". Children aren't charged.
- passes the copy on with the same rule cancelling uses: set aside for the next waiting member, with a pickup-by date counted from the day the job runs, or back on the shelf if nobody is waiting.

It returns the holds it expired. If the job missed some days it catches up, and running it twice on the same day expires and charges nothing more.

**Supporting changes:**
- New `EntryKind.NO_SHOW_FEE`. It counts as a charge, so it counts towards both blocking thresholds (borrowing and placing holds).
- The 1.00 fee is `NO_SHOW_FEE` in `policy.py`, next to the other circulation numbers.
- The repository has a new query for all ready holds. The queue-order sort now lives in one shared helper.
- `Hold.is_past_pickup(day)`, written the same way as the existing `Loan.is_overdue`.
- A README Concepts entry on expiry and the fee.

**Tests:** I wrote 14 new tests in `tests/test_holds.py` first and watched them fail. They go only through `LendingService`, moving the `FixedClock`, and cover every item on the ticket's checklist. There's no `tdd` skill installed, so I did this by hand.

**Review:** The spec review found nothing missing or wrong. The standards review found no rule breaches and five possible code smells. I fixed two: the queue order was written out twice, and the expiry check sat in the service rather than on `Hold`. I left the other three:
- **Shared charge helper:** the no-show fee code has the same shape as the fine code. Merging them would mean refactoring the existing fine logic.
- **Shared ready-hold ending:** expiry and cancellation end a ready hold the same way. Same reason; that would mean reworking the existing cancel code.
- **Date constants in tests:** inline dates sit beside new named constants. Tidying that means editing existing tests, which the ticket says must stay unchanged.

**Not in the commit:**
- The `GLOSSARY.md` edit and the `__pycache__` files. Both were already uncommitted changes when I started, so I left them for you.
- The ticket's `Status:` line, still `ready-for-agent`. Tickets 01 and 02 were never updated after they were done either, and `.scratch/` isn't tracked by git.

### [F2:implement:04] operator

/implement .scratch/holds/issues/04-borrowing-another-copy-fulfils-a-hold.md

### [F2:implement:04] agent

Ticket 04, **Borrowing another copy fulfils a hold**, is done and committed to `main` as `274b9fc`. All 141 tests pass, none of the existing tests changed, and pyright reports no errors.

**What changed**
- **`checkout`** now fulfils the member's active hold on the title whichever copy they borrow (`src/lending/service.py:365`). The hold becomes `FULFILLED` and its `copy_id` records the copy actually borrowed. A waiting hold keeps `pickup_by` = `None`.
- **Set-aside copy:** if the hold was ready on a different copy, that copy is passed on with no charge, using the existing rule. It goes to the next waiting hold with a fresh pickup-by date, or back to the shelf if nobody is waiting.
- **No other change to checkout:** this only happens after every check passes, so a blocked member or one at the loan limit keeps their hold as it was. Members with no hold on the title see no difference.
- **Tests:** 8 new ones in `tests/test_holds.py`, covering each item on the ticket's checklist. They go through `LendingService` only and use the shared fixtures.
- **README:** one sentence added to the "Collect" entry.

**Review**
- **Fixed:** the README said "with no fee", which breaks the glossary's rule against "fee" outside "no-show fee"; it now says "at no charge". The reviewer also found no test for a member collecting the set-aside copy while someone else is waiting, so I added one.
- **Not changed:** `_fulfil_hold`, `cancel_hold` and `expire_holds` each close a hold and pass its copy on in a similar way, and checkout now looks up the member's holds twice. Merging them felt beyond this ticket.

**Worth knowing**
- **Old pickup-by date:** a ready hold fulfilled with another copy keeps the pickup-by date it had for the set-aside copy. The spec doesn't say what should happen here, so tell me if it should be cleared.
- **No `tdd` skill:** it isn't installed here, so I wrote the tests first by hand instead.
- **Left out of the commit:** the `GLOSSARY.md` edits and `__pycache__` files that were already changed before I started, and the untracked `.scratch/`. I also didn't update the ticket file's checkboxes or status.

### [F3:grill] operator

/grill-with-docs Members ask to keep books longer, and staff do it by returning and re-checking the copy out, which
breaks the loan history. Add renewals.

Interface (other code will call exactly this):
- `LendingService.renew(loan_id: str) -> Loan` in `src/lending/service.py` — renews the open loan in
  place (same `loan_id`) and returns it.
- `Loan` in `src/lending/models.py` gets a field `renewals: int` (default `0`): how many times the
  loan has been renewed.
- Add `RenewalRefused(LendingError)` to `src/lending/errors.py` for renewals that can't be granted;
  unknown loan ids keep raising `LoanNotFound`, and keep using the other existing error classes where
  they already fit.

### [F3:grill] agent

I've read the code, ADR-0001, and the holds and overdue-fines specs. A few decisions about renewals were already made in earlier specs, so I'll ask you to confirm those before we build on them:

- **Holds spec (1):** a loan can't be renewed while any hold on its title is `WAITING`. A `READY` hold doesn't block it.
- **Holds spec (2):** only members who are paid up can renew. That's a renewal blocking threshold of 0.01, refused with `AccountBlocked`, checked against the balance at the time they ask.
- **Overdue-fines spec / ADR-0001:** renewing an overdue loan settles its lateness. It charges the fine up to the renewal day (same rates, child exemption, and replacement-cost cap across the whole loan). Lateness after that counts from the new due date.

One issue the holds spec left open: a member who owes nothing can still have an overdue loan, because a fine that's still building up isn't part of the balance.

---

❓ **Q1** - **Confirm the three earlier decisions**: Should renewals follow the three bullets above exactly: waiting holds refuse, paid-up only at 0.01 via `AccountBlocked`, and an overdue renewal settles the fine?

➡️ Yes, all three as written.

---

❓ **Q2** - **Can an overdue loan be renewed at all?** The ADR's wording ("when an overdue loan is renewed") assumes it can. The other option is to refuse renewing once the due date has passed, so the member has to return the copy and pay first.
- (a) Allow it. The renewal charges the fine built up so far, so the member leaves owing that amount (and can't renew again until they pay it).
- (b) Refuse it with `RenewalRefused`.

➡️ (a). It matches the ADR and the earlier specs, and it fixes the problem you described: staff returning and re-borrowing an overdue copy already charges that fine today.

---

❓ **Q3** - **What does the new due date count from?**
- (a) The renewal day: `due_date(material, today)`, so a full loan period from today, not landing on a Sunday.
- (b) The current due date plus another loan period.

With (b), an overdue renewal could hand back a due date that's already passed, or nearly passed. With (a), renewing early gains less time.

➡️ (a), the renewal day. That's the normal library rule, and it lines up with lateness being settled up to the renewal day.

---

❓ **Q4** - **Is there a maximum number of renewals per loan?** I suggest a policy constant `MAX_RENEWALS = 2`, the same for books and DVDs and for adults and children. One more renewal after that is refused with `RenewalRefused`.

➡️ Yes, 2 per loan for everyone, kept in `policy.py`.

---

❓ **Q5** - **What error does renewing a returned loan raise?** `NoOpenLoan` is keyed by copy and says "copy X is not on loan". That's wrong here, because the copy may be on loan to someone else by now. So it doesn't really fit.

➡️ `RenewalRefused`, with a reason such as "loan L0003 was returned on …".

---

❓ **Q6** - **What order are the checks in, and is a refusal free of side effects?** Proposed order: unknown loan → `LoanNotFound`, then returned loan → `RenewalRefused`, then not paid up → `AccountBlocked`, then renewal limit reached → `RenewalRefused`, then waiting hold on the title → `RenewalRefused`. Every check runs before anything changes. A refused renewal of an overdue loan charges no fine and leaves the loan as it was.

➡️ Yes, that order, and a refusal changes nothing.

---

❓ **Q7** - **What does the loan record keep?** I suggest: same `loan_id`, same `borrowed_on`, `due_on` replaced by the new date, `renewals` + 1. Earlier due dates aren't stored on the loan. The only trace of them is `counted_from` on any fine entry. The overdue report and `overdue_loans` then use the new due date. Also, a renewal doesn't count against the loan limit and isn't checked against the 10.00 borrowing threshold, since the 0.01 renewal threshold is stricter anyway.

➡️ Yes. A count plus the moved due date is enough, and there's no list of past due dates.

---

❓ **Q8** - **Glossary term**: I'd add:

> **Renew**: To give an open loan a new due date without the copy being returned; it stays the same loan. A loan's renewals are how many times this has happened.
> _Avoid_: Extend, re-borrow, re-check-out

➡️ Yes, add it with that wording.

### [F3:grill] user

Q1–Q3 and Q5–Q8 are fine as you wrote them. The earlier decisions in Q1 were settled in previous sessions and should be written down in the project, so go with what the specs say.

Q4 needs a correction. The limit of 2 renewals is right, but DVDs can't be renewed at all. A DVD renewal should be refused with RenewalRefused. Only books can be renewed.

### [F3:grill] agent

Thanks. I've added **Renew** to `GLOSSARY.md` under a new "Loans" heading. The earlier decisions stand as the specs wrote them. DVDs can never be renewed, books up to twice. That's a policy rule rather than a definition, so it goes in the spec and `policy.py`, not the glossary.

Your answers open up these questions:

---

❓ **Q9** - **How should "DVDs can't be renewed" sit in `policy.py`?** `LOAN_DAYS` and `FINE_PER_DAY` are already dicts keyed by material. The options:
- (a) `MAX_RENEWALS: dict[Material, int] = {BOOK: 2, DVD: 0}`. A DVD then just has a limit of 0.
- (b) A separate `RENEWABLE_MATERIALS = {BOOK}` plus a single `MAX_RENEWALS = 2`.

➡️ (a). It follows the existing per-material pattern, and making DVDs renewable later would be a one-number change. When the limit is 0, the refusal reason should say "DVDs can't be renewed" rather than "renewal limit reached".

---

❓ **Q10** - **Where does the DVD check go in the order?** If it sits with the renewal-limit check, a DVD borrower who owes 0.50 gets `AccountBlocked`. That tells them to pay, and the renewal would still be refused once they had. Proposed order: unknown loan → `LoanNotFound`, returned → `RenewalRefused`, material can't be renewed → `RenewalRefused`, not paid up → `AccountBlocked`, renewal limit reached → `RenewalRefused`, waiting hold → `RenewalRefused`.

➡️ Yes. Check that the material can be renewed straight after the returned-loan check, before blocking.

---

❓ **Q11** - **Should a renewal that doesn't move the due date be refused?** The new due date counts from the renewal day (Q3). So a book renewed on the day it was borrowed gets the same due date and uses up one of its two renewals for nothing. The Sunday shift can cause the same thing.

➡️ Yes. Refuse it with `RenewalRefused` ("the due date would not change") whenever the new due date wouldn't be later than the current one. It's the last check, and nothing is used up.

---

❓ **Q12** - **What does the fine from an overdue renewal look like?** Fines on return are recorded as "late return of B1". I suggest the same entry kind (`FINE`), `loan_id` set, `counted_from` = the due date before the renewal, and the reason "late renewal of B1". `_charge_fine` would take the reason as a parameter.

➡️ Yes, a `FINE` entry with the reason "late renewal of <copy_id>".

---

❓ **Q13** - **What does `RenewalRefused` carry?** `HoldNotAllowed` carries only a `reason` string. I suggest `RenewalRefused(loan_id, reason)`, with both stored as attributes, so callers can tell which loan was refused without parsing the message.

➡️ Yes, `loan_id` and `reason`.

---

❓ **Q14** - **What gets written down?** The project keeps specs in `.scratch/<feature>/spec.md`, with one file per issue. I suggest `.scratch/renewals/spec.md`, which pulls together the inherited decisions from the holds and overdue-fines specs and today's answers, plus one issue, `issues/01-renew-a-loan.md` (`Status: ready-for-agent`). It's a single vertical slice, so one ticket is enough. I'd also add a **Renew** bullet to the README's Concepts list when the work is implemented. I don't see anything that needs an ADR: every choice here is a policy number or is easy to reverse, and ADR-0001 already covers the fine on an overdue renewal.

➡️ Yes: one spec, one issue, the README bullet as part of the issue, and no ADR.

### [F3:grill] user

Q9, Q10 and Q12–Q14 are fine as proposed.

Q11 touches a rule I haven't given you yet. A loan can only be renewed from 5 days before its due date onwards. For example, if a loan is due Mon 23 March, it can be renewed from Wed 18 March, and on 17 March the request is refused with RenewalRefused. So a renewal on the day of borrowing is refused for that reason. Your "due date would not change" check is fine as a backstop, but it should not be the only protection. Put the early check wherever it fits in the order.

### [F3:grill] agent

That's clear. Checking your example: 23 March 2026 is a Monday, and 18 March is five calendar days before it, with Sunday 22nd counted. So the window is in calendar days, the same as loan periods and pickup time. Two more questions follow from it, plus one about the glossary:

---

❓ **Q15** - **How is the renewal window defined?** I suggest a constant in `policy.py`, `RENEWAL_WINDOW_DAYS = 5`, the same for every member category. A loan can be renewed from `due_on − 5 calendar days` (inclusive) onwards, with no upper bound. An overdue loan is always inside the window. The refusal reason names the first day renewal is possible, e.g. "loan L0003 can be renewed from 2026-03-18".

➡️ Yes, those exact semantics.

---

❓ **Q16** - **Should the check order be reshaped around "can paying fix this?"** The reasoning behind Q10 also applies to the renewal limit and the window. A member who has used both renewals and owes 0.50 would get `AccountBlocked`, pay, and then still be refused. I suggest putting every refusal that paying can't change ahead of the balance check:

1. unknown loan → `LoanNotFound`
2. returned → `RenewalRefused`
3. material can't be renewed (DVD) → `RenewalRefused`
4. renewal limit reached → `RenewalRefused`
5. too early (before the window opens) → `RenewalRefused`
6. not paid up → `AccountBlocked`
7. waiting hold on the title → `RenewalRefused`
8. backstop: due date wouldn't move later → `RenewalRefused`

The waiting-hold check stays after the balance check. It's a temporary state, and it can clear while the member goes to pay. With today's numbers, the backstop can never fire: the window opens at most 5 days before the due date, and a renewal gives 21 days from the renewal day. It's only there in case the policy numbers change.

➡️ Yes, this order.

---

❓ **Q17** - **Is the window a glossary term?** Staff could say "the renewal window" or "renewable from". I'd leave it out. It's a rule about when **Renew** is allowed, not a new concept, and it belongs in the spec and `policy.py`.

➡️ Yes, keep it out of the glossary.

### [F3:grill] user

Yes to all three, Q15 to Q17, as you proposed them. The order in Q16 is fine with me.

### [F3:grill] agent

I don't have any open questions left. Here is the full design for you to confirm before I write the spec and issue (Q14). So far the only file I've changed is `GLOSSARY.md`, where I added **Renew**.

**`LendingService.renew(loan_id) -> Loan`** renews the open loan in place and returns it.

**Checks, in this order.** All of them run before anything changes, so a refused renewal charges nothing and leaves the loan as it was.
1. Unknown loan → `LoanNotFound`
2. Loan already returned → `RenewalRefused`
3. The material can't be renewed (`MAX_RENEWALS[DVD] == 0`) → `RenewalRefused`, reason "DVDs can't be renewed"
4. Renewal limit reached (`MAX_RENEWALS[BOOK] == 2`) → `RenewalRefused`
5. Too early: today is before `due_on − RENEWAL_WINDOW_DAYS` (5 calendar days, inclusive) → `RenewalRefused`, with the reason naming the first day renewal is possible
6. Not paid up: balance ≥ 0.01 → `AccountBlocked`, using the shared blocking check, the same for children
7. Any `WAITING` hold on the title → `RenewalRefused` (a `READY` hold doesn't count)
8. Backstop: the new due date wouldn't be later than the current one → `RenewalRefused`

**When the renewal is granted:**
- If the loan is overdue, its lateness up to today is settled first. That's a `FINE` entry with the reason "late renewal of <copy_id>" and `counted_from` set to the old due date. It uses the same rates and child exemption, and the replacement-cost cap across the whole loan. `_charge_fine` takes the reason as a parameter.
- `due_on = policy.due_date(material, today)`, and `renewals += 1`. `loan_id` and `borrowed_on` stay the same, and earlier due dates aren't kept.
- The renewal doesn't count toward the loan limit and isn't checked against the borrowing threshold. The overdue report and `overdue_loans` use the new due date.

**Code changes:**
- `Loan.renewals: int = 0`
- `RenewalRefused(LendingError)` carrying `loan_id` and `reason`
- `policy.py` gets `MAX_RENEWALS = {BOOK: 2, DVD: 0}`, `RENEWAL_WINDOW_DAYS = 5` and `RENEWAL_BLOCKING_THRESHOLD = 0.01`
- A **Renew** bullet in the README's Concepts list

**Files to write:**
- `.scratch/renewals/spec.md`, which pulls together the decisions from the holds and overdue-fines specs and today's answers
- `.scratch/renewals/issues/01-renew-a-loan.md`, with `Status: ready-for-agent`
- No ADR: ADR-0001 already covers settling the fine when an overdue loan is renewed.

Is that our shared understanding? If so, I'll write the spec and the issue.

### [F3:grill] user

Yes, that matches what I want. Please don't write the spec or the issue now. I'll start that step myself with /to-spec.

### [F3:grill] agent

Understood, I won't write the spec or the issue. The grilling is finished and you've confirmed the design.

This session changed one file: `GLOSSARY.md`, which now has a "Loans" heading with the **Renew** entry. Nothing else in the repo was touched, and no ADR was needed.

When you run `/to-spec`, the design to work from is the summary in my last message. The decisions it carries over from earlier are in `.scratch/holds/spec.md` (Further Notes, items 1 and 2), the Out of Scope and Further Notes sections of `.scratch/overdue-fines/spec.md`, and ADR-0001.

I also tried to save a note that you run the spec step yourself after a grilling session, but the permission settings blocked the write to the memory folder, so it isn't saved.

### [F3:to-spec] operator

/to-spec

### [F3:to-spec] agent

Before I write the spec, here's the test seam I suggest, as the skill asks me to check with you.

**One seam: the public `LendingService` interface.** It's driven the way every existing test file does it: the `service` and `clock` fixtures in `conftest.py`, a `FixedClock` starting Mon 2 March 2026, an `InMemoryRepository`, books B1/B2 and DVD D1.

- `renew(loan_id)` is the action under test.
- The results are observed only through public reads that already exist:
  - `get_loan` / the returned `Loan` for `due_on`, `renewals`, `loan_id`, `borrowed_on`
  - `balance` for fines charged by an overdue renewal
  - `open_loans`, `loan_history` and `overdue_loans`
  - the existing `return_copy` and `checkout` for the after-effects: a later late return counts from the new due date, the per-loan cap holds across renewals, and the renewal doesn't count against the loan limit
- Refusals are checked by exception type (`RenewalRefused`, `AccountBlocked`, `LoanNotFound`). Each test also checks that nothing changed: same `due_on`, same `renewals`, same balance.
- `overdue_report` gets one test through the existing `reports` entry point, the way `test_catalogue.py` already covers it, to show it uses the new due date.

**No new seams.** Tests won't call `policy` directly or reach into the repository, matching the existing suite (`test_fines.py` checks fines only through `balance`).

**One gap this leaves:** the fine entry's reason ("late renewal of B1") and its `counted_from` can't be seen from outside, because there's no public account history and the overdue-fines spec ruled that out of scope. They'd be checked only indirectly, through the amounts charged.

Does that seam match what you expect? If so, I'll write `.scratch/renewals/spec.md` with `Status: ready-for-agent`.

### [F3:to-spec] user

Yes, that seam is fine with me. Go ahead and write the spec.

### [F3:to-spec] agent

I've written the spec to `.scratch/renewals/spec.md` with `Status: ready-for-agent`. Nothing is committed, and I didn't write a separate issue file.

What's in it:
- **The interface you specified:** `renew(loan_id) -> Loan` working in place, `Loan.renewals` defaulting to 0, and `RenewalRefused` carrying `loan_id` and a reason. An unknown loan raises `LoanNotFound`, and a member who isn't paid up gets `AccountBlocked` at the 0.01 threshold.
- **The eight checks in the order you approved:** the refusals that paying can't fix (returned loan, DVD, renewal limit, too early) come before the balance check. Waiting holds come next, and the due-date check is last as a backstop. Every check runs before anything changes.
- **Overdue renewals:** the fine is charged up to the renewal day, recorded as "late renewal of <copy>". Lateness after that counts from the new due date, and the replacement-cost cap covers all fines on the loan.
- **36 user stories, and a test plan using only the public `LendingService` methods.** The concrete scenarios are built on the existing fixtures. For example: a book due Mon 23 Mar is refused on Tue 17 Mar and renewed on Wed 18 Mar, which makes it due Wed 8 Apr. An overdue renewal on Mon 30 Mar charges 1.50, and a later return on Mon 27 Apr adds another 1.50.

Things worth checking when you read it:
- **Dates and amounts are hand-calculated.** I couldn't run Python here (the permission settings blocked it), so I worked the scenario dates and fine amounts out by hand against `policy.py`. Running the tests will confirm them.
- **The earlier example no longer works.** The overdue-fines spec shows the replacement-cost cap with a 12.00 DVD that gets renewed, and DVDs can't be renewed now. The spec explains this, and its cap test uses a book with a 2.00 replacement cost instead.
- **Two parts can't be tested from outside, and the spec says so.** The fine's reason and the due date it was counted from aren't visible through any public method, so they're only checked through the amounts charged. The due-date backstop can't be triggered with the current policy numbers.
- **I added one rule we didn't discuss.** Like checkout and return, `renew` doesn't check whether the library is open that day. I wrote that into Implementation Decisions under "Unchanged", and listed refusing renewals on closed days as out of scope. Change it if you want something different.

### [F3:to-tickets] operator

/to-tickets

### [F3:to-tickets] agent

Here's the breakdown I'd suggest, using the spec in `.scratch/renewals/spec.md`. One prefactor is needed: the fine-charging step has to take the entry's reason as a parameter. That change is tiny, so I've made it the first step of the overdue ticket, which is the only one that uses it. The holds work did the same with its blocking-check refactor.

1. **Renew a book loan inside the renewal window**
   - **Blocked by:** None (can start immediately).
   - **What it delivers:** the end-to-end tracer.
     - `renew(loan_id)`, the `Loan.renewals` field (0 by default) and the `RenewalRefused` error.
     - An unknown loan raises `LoanNotFound`. A returned loan is refused, as is a request before the 5-day window opens (the reason names the first allowed day).
     - The new due date counts from today, plus the due-date backstop.
     - The same loan with a new due date shows up in `get_loan`, `open_loans`, `loan_history`, `overdue_loans` and the overdue report. A renewal doesn't count against the loan limit.
     - A first **Renew** entry in the README.
   - **Check it:** B1 due Mon 23 Mar is refused on Tue 17 Mar, renewed on Wed 18 Mar, and is then due Wed 8 Apr.

2. **Renewal limit: books twice, DVDs never**
   - **Blocked by:** 01.
   - **What it delivers:** the per-material renewal limit (book 2, DVD 0). A third renewal is refused, and a DVD is refused with "DVDs can't be renewed". Both checks go in their place in the order: after the returned-loan check and before the window check.

3. **Only paid-up members renew, and not while someone is waiting**
   - **Blocked by:** 02.
   - **What it delivers:**
     - The 0.01 renewal blocking threshold, raising `AccountBlocked` through the shared check, the same for children.
     - Waiting holds on the title refuse renewal, and ready holds don't.
     - The ordering tests that need both 02 and 03: a DVD, limit-reached or too-early request while owing gets `RenewalRefused`, not `AccountBlocked`, and owing while someone waits gets `AccountBlocked`.

4. **Renewing an overdue loan settles its fine**
   - **Blocked by:** 03.
   - **What it delivers:**
     - Prefactor first: the reason becomes a parameter, and returns still read "late return of …".
     - Then an overdue renewal charges the fine up to today ("late renewal of …", `counted_from` = the old due date). Later lateness counts from the new due date.
     - The replacement-cost cap applies across renewals, and children are exempt.
     - It covers the "renewed late, now blocked until they pay" path and a refused overdue renewal that charges nothing.

Questions for you:
- **Granularity:** Does this feel right? It's a small feature, so the other sensible option is three tickets, merging 02 and 03 into one "refusals" ticket.
- **Blocking edges:** 02 → 03 → 04 isn't strictly needed for the core behaviour. It's there because of the ordering tests. 03's "limit reached while owing" test needs 02, and 04's "renewed late, now blocked" and "refusal charges nothing" tests need 03's blocking check. If you'd rather run 02, 03 and 04 in parallel after 01, I'd move those cross-ticket tests into a small final ticket blocked by all three. Which do you prefer?
- **Merge or split:** Should anything else be merged or split?

### [F3:to-tickets] user

Four tickets is fine with me. Keep the chain 01 -> 02 -> 03 -> 04 as you have it. I don't want a separate ticket for the ordering tests. I don't need anything merged or split.

### [F3:to-tickets] agent

I've written the four tickets to `.scratch/renewals/issues/`. They form the chain you approved, each blocked by the one before it and each marked `ready-for-agent`. Nothing is committed, and the spec itself is unchanged.

1. `01-renew-a-book-loan-inside-the-renewal-window.md` (can start now):
   - adds `renew`, `Loan.renewals` and `RenewalRefused`;
   - covers unknown and returned loans, the 5-day window, the new due date counted from today, and the backstop;
   - checks that the renewed loan reads back correctly through the existing loan lookups and the overdue report;
   - starts the README's **Renew** entry.
2. `02-renewal-limit-books-twice-dvds-never.md`: the per-material renewal limit. Its two checks go after the returned-loan check and before the window check.
3. `03-only-paid-up-members-renew-and-not-while-someone-waits.md`: the 0.01 blocking threshold and the waiting-hold refusal. This completes the check order and includes the ordering tests that span 02 and 03.
4. `04-renewing-an-overdue-loan-settles-its-fine.md`: starts with the reason-parameter refactor, which must leave the existing fines tests passing. Then the overdue renewal charges the fine, with the cap across renewals and the child exemption. It also covers the case where a member who renewed late is blocked from renewing again until they pay.

Each ticket names the README update it owes and ends with "existing tests pass unchanged". As with the spec, I calculated the dates and amounts in the acceptance criteria by hand, so the first test run will be what confirms them.

### [F3:implement:01] operator

/implement .scratch/renewals/issues/01-renew-a-book-loan-inside-the-renewal-window.md

### [F3:implement:01] agent

Ticket 01, **"Renew a book loan inside the renewal window"**, is implemented and committed to `main` as `aad4129`. The full suite passes (152 tests: 141 existing, unchanged, plus 11 new), and pyright reports no errors.

**What changed**
- **`LendingService.renew(loan_id)`** renews the loan in place and runs the ticket's checks in order:
  1. An unknown loan id raises `LoanNotFound`.
  2. A returned loan is refused, e.g. "loan L0001 was returned on 2026-03-20".
  3. A renewal before the window opens is refused, e.g. "loan L0001 can be renewed from 2026-03-18".
  4. The backstop refuses a renewal whose new due date wouldn't be later than the current one.

  If all checks pass, the new due date is the policy due date counted from today and `renewals` goes up by 1. It doesn't count against the loan limit, check the borrowing threshold or touch holds.
- **`Loan.renewals`** defaults to 0.
- **`RenewalRefused`** is a new domain error carrying `loan_id` and `reason`.
- **Policy:** the 5-day renewal window is `policy.RENEWAL_WINDOW_DAYS`, with a helper `renewable_from(due_on)`.
- **README:** the Concepts section has a new **Renew** entry.
- **Tests:** the new tests are in `tests/test_renewals.py` and go only through the service and the overdue report. Every refusal test also checks that `due_on`, `renewals` and the balance are unchanged.

**Review**
- **Fixed:**
  - The title lookup now runs before the window check, so ticket 02's material and renewal-limit checks can go in between without moving code.
  - The copy-to-title lookup, which `_charge_fine` also did, is now one helper `_title_of`.
  - The open-loan check uses `is_open`, like the rest of the service.
  - The README now says an overdue loan is "always inside the window" rather than "can always be renewed", which tickets 02–04 would make false.
- **Left as is:**
  - The standards reviewer said `renew` conflicts with ADR-0001 because renewing an overdue loan charges no fine yet. The ticket defers that to ticket 04 on purpose, and the commit message says so.
  - Loan ids in the refusal reasons aren't quoted, unlike other errors, because that's how the spec's example reasons are written.

**Not in the commit:** your uncommitted `GLOSSARY.md` change and `.scratch/renewals/` (earlier specs and glossary edits had their own commits), and the regenerated `__pycache__` files. I also didn't tick the ticket's checkboxes or change its status. The `tdd` skill isn't installed here, so I wrote the tests first by hand.

### [F3:implement:02] operator

/implement .scratch/renewals/issues/02-renewal-limit-books-twice-dvds-never.md

### [F3:implement:02] agent

Ticket **02: Renewal limit: books twice, DVDs never** is done and committed as `8f190ef`. All 157 tests pass, existing tests are unchanged, and pyright reports no errors.

**What changed**
- **Policy:** a new per-material table, `RENEWAL_LIMITS` (book 2, DVD 0), sits with the loan periods and fine rates. You read it through `renewal_limit()`.
- **`renew`:** two checks now run after "the loan is returned" and before "too early":
  - A limit of 0 is refused with "DVDs can't be renewed".
  - A loan that has used up its renewals is refused with "loan L0001 has already been renewed 2 times".

  So a DVD or a used-up loan is refused whatever the date, and nothing changes before the checks pass.
- **Tests:** one new test in `tests/test_renewals.py` for each ticket checkbox. The tests for "two renewals are granted" and "a returned DVD is refused as returned" passed before the fix; they pin the order of the checks.
- **README:** the **Renew** entry now gives the renewal limit: books twice, DVDs never.

**Code review**
- **Standards:** no breaches of the documented standards, and the renewal-limit wording is used throughout. From the possible smells it raised, I fixed three:
  - added a `d1_out` fixture to match the existing `b1_out`;
  - made the third-renewal test check the refusal reason;
  - re-wrapped a README line.

  I kept the plural names ("DVDs") for refusal reasons in `service.py` rather than `policy.py`, because they're wording, not circulation numbers. I left `renewal_limit()` as a thin lookup to match `loan_limit()`.
- **Spec:** no gaps, scope creep or wrong behaviour found. The parent spec's "still refused when `ann` owes 5.00" case belongs to ticket 03.

**Left uncommitted on purpose:** the `GLOSSARY.md` edit that was already there when I started (the "Loans / Renew" entry), the tracked `.pyc` files and `.scratch/`. The glossary has no "Renewal limit" entry yet. That could be added with `/domain-modeling`, or alongside the existing edit when you commit it.

### [F3:implement:03] operator

/implement .scratch/renewals/issues/03-only-paid-up-members-renew-and-not-while-someone-waits.md

### [F3:implement:03] agent

Ticket 03 ("Only paid-up members renew, and not while someone is waiting") is done and committed as `fd4cc05` on `main`. All 166 tests pass, pyright reports no errors, and no existing test was changed.

**What `renew` now does** (`src/lending/service.py`):
- **Balance check:** after the "too early" check, a member owing anything is refused with `AccountBlocked`, carrying the 0.01 threshold. It uses the same blocking check as `checkout` and `place_hold`. The threshold is `RENEWAL_BLOCKING_THRESHOLD = 0.01` in `src/lending/policy.py`, the same for adults and children.
- **Waiting-hold check:** after the balance check, any `WAITING` hold on the loan's title refuses the renewal with `RenewalRefused`, found with the repository's existing waiting-holds query. A `READY` hold doesn't count.
- **README:** the Renew entry now states both rules and why they're checked in that order.

**Tests:** I added 10 to `tests/test_renewals.py`, covering every scenario in the ticket's checklist, including the four ordering cases. A shared helper now checks that every failed renewal, blocked or refused, leaves the due date, renewal count and balance unchanged, as the spec asks.

**Review fixes** (from the code review, made before committing):
- The `renew` docstring and README had said every refusal that paying can't fix comes before the balance check. That's not true of the waiting hold, which comes after it. They now give the spec's reason: a waiting hold is temporary.
- README's Expire entry said no-show fees count towards "both" blocking thresholds; there are now three, so it says "every".
- I reworded a code comment that seemed to contradict ADR-0001.
- I left two minor style points as they were.

**Left out of the commit:**
- `GLOSSARY.md` and `.scratch/renewals/` were already uncommitted before I started.
- The `__pycache__/*.pyc` files are tracked in git, so running the tests modifies them; you may want to untrack them and add them to `.gitignore`.
- I didn't change the ticket's `Status:` line, because tickets 01 and 02 were left at `ready-for-agent` too.

The `tdd` skill isn't installed here, so I did test-first by hand: the five new behaviour tests failed before the change and passed after it.

### [F3:implement:04] operator

/implement .scratch/renewals/issues/04-renewing-an-overdue-loan-settles-its-fine.md

### [F3:implement:04] agent

Ticket 04 is done: renewing an overdue loan now charges the fine built up so far. It's committed to `main` in two commits. All 177 tests pass, the 166 existing ones unchanged, and pyright is clean.

- **`cca0764` Pass the fine's reason into the fine-charging step.** This is the refactor the ticket asked for first, with no change in behaviour. Returns still record "late return of <copy_id>". I committed it on its own and confirmed the original 166 tests pass against it.
- **`af54349` Renewing an overdue loan settles its fine.** It covers all 10 acceptance criteria:
  - **Where it happens:** in `renew`, after every check and before the due date moves. A refused renewal therefore charges nothing, and the fine is counted from the old due date.
  - **What gets charged:** the same calculation as a return, so the child exemption applies and fines from earlier renewals count towards the replacement-cost cap.
  - **README:** the Renew and Fine entries now describe this.

**Code review:**
- **Spec:** no findings. The reviewer also checked the date arithmetic in the tests by hand.
- **Standards:** one real problem. The README's Fine entry still said fines are charged only on return; I fixed that.
- **Smaller points I fixed:** the `renew` docstring now mentions the fine, and the late-return reason test moved to `tests/test_fines.py`.
- **Left as is:** the reviewer suggested building the reason text inside the fine step, but the ticket asks for it to be passed in.

Things you might trip over:
- **New test fixture:** I added a `repo` fixture in `tests/conftest.py` so tests can check the recorded fine entry (reason, loan, start date). Until now tests only went through the service, and there's no public way to read entries.
- **Not committed:** `GLOSSARY.md`, the `.scratch/renewals/` folder and the existing `__pycache__` changes were already in your working tree, so I left them out. I also didn't mark the ticket done, since none of the earlier tickets were. I deleted the `uv.lock` and extra pycache files my own test runs created.
- **Skipped:**
  - The `tdd` skill isn't installed, so I worked test-first by hand: the first renewal test failed, then passed once the change was in.
  - One extra check, deliberately moving the fine before the checks to confirm the tests catch it, needed a permission I didn't have.
- **Ruff:** it reports warnings about variables named `l`, and the repo isn't ruff-formatted. That's all in code I didn't touch, so I left it.
