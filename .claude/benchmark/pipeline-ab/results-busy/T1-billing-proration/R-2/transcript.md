### [spec] operator

Customers can't change plan right now: support has to cancel and resubscribe them by hand.
Add mid-cycle plan changes to the billing package: upgrades and downgrades, optionally
switching between monthly and annual billing, prorated so nobody pays twice for the same days.

Interface (other code will call exactly this):
- `BillingService.change_plan(subscription_id: str, new_plan_code: str, new_interval: Interval | None = None) -> Invoice | None`
  in `src/billing/service.py`. `new_interval=None` keeps the subscription's current interval.
- Return the invoice issued for the change (recorded in the store like every other invoice),
  or `None` when nothing is billed at the moment of the request.
- Add `InvalidPlanChange(BillingError)` to `src/billing/errors.py` for change requests that
  can't be honoured; keep using the existing error classes where they already fit.

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim.

### [spec] agent

I've read the whole package (about 700 lines). Some things the code already settles, so I won't ask about them:

- **Errors that already fit:** unknown subscription → `SubscriptionNotFound`. Canceled subscription → `SubscriptionNotActive`. Unknown target plan → `PlanNotFound`. Retired target plan → `PlanNotAvailable`.
- **What we have to work with:** money is in whole cents, rounded half-up. Periods are half-open `[start, end)` and use real calendar months. Invoice lines can already be negative.
- **A constraint:** the store has a production database version "with the same methods". So anything that needs new persisted state, like a stored credit balance or a pending change on `Subscription`, is a schema change. Several of the questions below depend on that.

Each question has my recommendation. Answering "agree" is fine.

**1. Downgrades (the change is worth less than the unused time already paid for).** This is the biggest decision.
- **A.** Switch now and issue an invoice with a negative total. Something outside this package handles the refund.
- **B.** Switch now and keep the surplus as account credit, taken off future renewals. This needs a stored balance, plus rules for when the credit outlasts renewals or the customer cancels.
- **C.** Keep the current plan until the period ends, then switch at renewal. Nothing is billed now, so the method returns `None`. This needs one stored "pending change" on the subscription.

*I recommend C:* it's the only option where a downgrade never creates money to give back. **A** only works if something downstream can pay out negative invoices. Can anything?

**2. Switching between monthly and annual.** *I recommend:* the new period starts today. The customer pays the full price for the new interval, minus a credit for the unused days of the current period. (If that comes out negative, it counts as a downgrade under Q1.) When the interval stays the same, the period dates don't change and the customer pays only for the remaining days.

**3. Trial subscriptions.** *I recommend:* the plan and/or interval change right away, the trial end date stays the same, nothing is billed, and the method returns `None`.

**4. Overdue renewal** (today is on or after `period_end` but `renew_due` hasn't run yet). *I recommend:* reject with `InvalidPlanChange` instead of quietly catching up renewals. Catching up could issue several invoices, and the method only returns one.

**5. Retired plans.** *I recommend:* customers can always move off a retired plan. Moving onto one raises `PlanNotAvailable`, including a customer already on that plan who only wants to change interval.

**6. Requests that change nothing** (same plan, same interval). *I recommend:* `InvalidPlanChange`. If C is chosen: a new request replaces any pending change. A request that matches the current plan and interval cancels the pending change and returns `None`.

**7. How proration is calculated.** *I recommend:*
- Prorate by the actual number of calendar days in the current period.
- The day of the change is billed at the new plan.
- The credit for the old plan and the charge for the new plan go on separate lines, each rounded to cents.
- The invoice is dated today.

**8. Net zero** (for example, two plans with the same price). *I recommend:* switch right away, issue no invoice, and return `None`.

### [spec] user

Answers by number:

1. Agree with C. A move to a cheaper plan waits for the end of the period. Nothing is billed, refunded or credited at the request, and `change_plan` returns `None`. At renewal the customer moves to the cheaper plan and is billed its full price. This also holds when the downgrade comes with a switch to annual. "Cheaper" means the plan's monthly list price is lower, whatever interval the customer is on or moving to. An upgrade is the immediate case: the customer is on the new plan from the day of the request, and the period start and end don't move. The next renewal bills the new plan at full price.

2. I disagree. An interval switch, monthly to annual or annual to monthly, also waits for the period end. We never refund unused annual time. Nothing is billed at the request. At renewal a new period of the new interval starts and bills that interval's full price. If an upgrade comes with an interval switch, split it. The upgrade happens now and is prorated at the current interval's prices. The interval switch happens at the period end.

3. Agree. Any change during a trial applies immediately, the trial end date stays, nothing is billed, and the method returns `None`. At trial end the customer is billed the full price of the plan and interval they are on by then.

4. I don't mind. Use your recommendation.

5. Agree. Customers on a retired plan can move off it, and moving onto one raises `PlanNotAvailable`. I don't mind how a pure interval switch on a retired plan behaves.

6. Agree. Asking for the same plan and interval raises `InvalidPlanChange` if nothing is scheduled. If something is scheduled, the request cancels it and returns `None`. Each request states the full target and replaces anything scheduled before it. An upgrade that applies now also discards anything scheduled, unless the same request schedules an interval switch.

7. Mostly agree, with these specifics:
   - Remaining days run from the change date, inclusive, to the period end, exclusive. The fraction is remaining days over the real calendar days in the period.
   - The invoice has two lines: a negative credit for the old plan and a positive charge for the new plan. Both use the current interval's prices.
   - Compute each line exactly as price × remaining days / period days, with no rounded daily rate in between. Round each line half-up on its own. The total is the sum of the two rounded lines, not a rounded net difference.
   - The invoice is dated the change date and recorded like any other.
   - A scheduled change hasn't happened yet, so an upgrade requested while a downgrade is scheduled is prorated from the current plan.
   - A rejected request changes nothing: no invoice, subscription untouched.

8. I don't mind. Same-monthly-price moves and zero-total invoices can follow your recommendation.

### [spec] agent

Your answers settle almost everything. Two edge cases are still open, and both follow from rules you set.

**9. An "upgrade" that would refund money.** You classify upgrades by monthly list price, but proration uses the current interval's prices. Plans don't have to price consistently across intervals. For example, a customer on Pro annual ($30/mo, $300/yr) moves to a plan priced $40/mo and $250/yr. By your rule that's an upgrade. But the credit (300 × r) is larger than the charge (250 × r), so the invoice total is negative, which breaks "nothing refunded". *I recommend:* treat any immediate change whose invoice would total less than zero as a downgrade, i.e. schedule it for the period end. The other option is to reject it with `InvalidPlanChange`.

**10. A scheduled target that gets retired before renewal.** A customer schedules a downgrade to Basic, and Basic is retired before their period ends. *I recommend:* apply it anyway. It was agreed while Basic could still be sold, the same way existing customers keep renewing on retired plans. The other option is to drop the scheduled change and renew on the current plan.

For the points where you said you don't mind, here's what the spec will say unless you object:
- An overdue renewal raises `InvalidPlanChange`.
- An interval switch alone on a retired plan raises `PlanNotAvailable`.
- A move to a plan with the same monthly price applies immediately with no invoice.
- An upgrade whose two rounded lines sum to exactly zero still applies, issues no invoice and returns `None`.

### [spec] user

Q9 and Q10 aren't covered by my rules, so I don't mind either way. Go with your recommendations: schedule the negative-total change for the period end, and apply the scheduled change even if the plan is retired by then. The defaults you listed for the "don't care" points are fine too.

Write SPEC.md when you're ready.

### [spec] agent

I've written `SPEC.md` (not committed). It has:

- **Interface:** your interface copied word for word, plus a note that `InvalidPlanChange` is also exported from `billing`.
- **Terms:** definitions of upgrade, downgrade, remaining days and so on.
- **Behaviour:** the rules for active subscriptions, scheduled changes and trials, and a table mapping each rejection to its error.
- **Acceptance criteria:** 33 checkable statements, most with exact amounts based on the existing `basic`/`pro` test fixtures. I computed the proration examples with a quick script. AC2 is designed to catch rounding mistakes: the correct total is 1.93, rounding the net difference gives 1.94, and using a rounded daily rate gives 1.95.
- **Non-goals:** refunds and credit balances, prorating interval switches, catching up overdue renewals, taxes and coupons, concurrency, and changing trial length.

Two things to be aware of:

- **A schema change is needed.** Deferring downgrades and interval switches means a scheduled change has to be saved on the subscription. The production database store will need to save and load it too, so the owner of that store should agree its shape. The spec flags this but doesn't design it.
- **One new criterion.** AC12 says that when `renew_due` catches up several missed periods, the scheduled change takes effect from the first one. We never discussed it; I added it because it follows from your rule that the change happens at the next renewal. Tell me if you want it worded differently.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote the acceptance tests in `tests/acceptance/test_change_plan.py`: 39 tests covering AC1–AC33. As expected, 38 of them fail because the feature doesn't exist yet. One passes: AC33, which checks behaviour that already exists.

**Command:**
```
python3 -m pytest tests/acceptance -q -rA
```

**Output (summary):**
```
PASSED tests/acceptance/test_change_plan.py::test_ac33_subscribe_renew_cancel_unchanged_without_scheduled_change
FAILED ...::test_ac1_upgrade_is_prorated_and_applies_now
FAILED ...::test_ac2_lines_are_rounded_separately_without_daily_rate
... (every test for AC1–AC32 fails)
38 failed, 1 passed in 0.28s
```

Every failure is because something is missing. None comes from a wrong value in a test:
```
     31 AttributeError: 'BillingService' object has no attribute 'change_plan'
      6 ImportError: cannot import name 'InvalidPlanChange' from 'billing.errors'
      1 AttributeError: module 'billing.errors' has no attribute 'InvalidPlanChange'
```
The full suite (`python3 -m pytest -q`) gives `38 failed, 21 passed`; the existing tests still pass.

**How the tests are built:**
- **Public interface only:** they call `subscribe`, `renew_due`, `cancel` and `change_plan` on `BillingService`, the store's public methods, and the exported errors. The fixtures are copied from the spec into the test file so it doesn't depend on `tests/conftest.py`.
- **Imports:** `InvalidPlanChange` is imported inside the tests that use it. That way each test fails on its own instead of the whole file failing to load.
- **Scheduled changes:** the spec doesn't say how a scheduled change is stored, so the tests check it through what happens at renewal. For rejections (AC24–AC30), a downgrade is scheduled first. The test then checks that the subscription object and invoice list are unchanged and that the next renewal still applies the downgrade.

**Where I chose values or went beyond the wording:**
- **Line order:** invoice lines are compared as a sorted set of amounts, because the spec gives the two amounts but not their order. Line descriptions aren't checked because the spec leaves the wording open.
- **AC14:** the spec doesn't give numbers for this one. I used a plan priced 10.01 with 1 day remaining, where both lines round to 0.32 and the total is 0.00.
- **AC20:** the spec only gives the −20.32 credit. I also assert the +33.87 charge, which I worked out from rule 1 (50.00 × 21/31).
- **AC30:** I added a case where a trial end is due, because the rejections table in the spec includes it.
- **AC12:** I added a second case where a scheduled switch from monthly to annual is caught up across missed periods.
- **AC33:** this passes now. It's a guard that existing behaviour doesn't change, alongside the existing tests.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

`change_plan` is built and all tests pass: the 38 acceptance tests and the 21 existing tests.

```
$ python3 -m pytest -q
...........................................................              [100%]
59 passed in 0.02s
```

Before the change, the existing 21 passed and all 38 acceptance tests failed. I didn't touch `tests/acceptance/`.

**What changed**
- **`errors.py` / `__init__.py`:** added `InvalidPlanChange(BillingError)` and exported it from `billing`. I also exported the new `ScheduledChange` type.
- **`subscriptions.py`:** a new frozen `ScheduledChange(plan_code, interval)`, and a new field on `Subscription`, `scheduled_change: ScheduledChange | None = None`. Because it defaults to `None`, existing subscriptions and code are unaffected.
- **`service.py`:**
  - `change_plan` checks for problems first: missing subscription, canceled, unknown plan, retired target plan, change date on or after `period_end`.
  - It then handles each case: asking for the current plan and interval clears a scheduled change (or is rejected if nothing is scheduled); trial changes apply at once and bill nothing; downgrades and interval switches are scheduled; upgrades are prorated now.
  - Each proration line is computed exactly and rounded half-up to cents on its own, which gives 1.93 in AC2.
  - At renewal, a scheduled change is applied once and then cleared, even if its plan has been retired since.
- **`README.md`:** added a short note on `change_plan`.

**Decisions for you**
1. **The database store needs the new field.** As the spec warns, `scheduled_change` (a plan code plus an interval, or nothing) is new state the production database store must save and load. I chose that shape, but it should be agreed with whoever owns that store before release.
2. **Undoing a scheduled change on a retired plan is rejected.** Say a customer is on retired `basic` with a downgrade scheduled, and asks to stay on `basic` at the same interval. That raises `PlanNotAvailable`, because I read "target plan is retired" in the spec's table literally. So they can't cancel the scheduled change that way. Allowing it is arguably more sensible, since it sells nothing new. The acceptance tests don't cover this case, and it's a one-line change if you want it.

Nothing is committed yet.

### [review1] operator

Review the changes since commit 10314a46fd4247c9e25e9820bae25858087d37cc (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps. The implementation matches SPEC.md, so nothing needs fixing.

All 59 tests pass. That includes the 37 acceptance tests in `tests/acceptance/test_change_plan.py`, which cover AC1–AC33. I also traced each rule in the spec against `src/billing/service.py` by hand:

- **Rejections (rule 8):**
  - Errors are raised in the order the spec's table lists them, and the "renewal is due" check (`InvalidPlanChange`) comes before any branching (`service.py:115-126`).
  - Every rejection is raised before anything is saved, so the subscription, its scheduled change and the invoices all stay as they were.
- **Same target as now (rule 5):** asking for the current plan and interval clears a scheduled change and returns `None`. If nothing is scheduled it raises `InvalidPlanChange` (`service.py:128-135`).
- **Trials (rule 7):** the plan and interval change at once, the trial end date stays the same, any scheduled change is cleared, and nothing is billed. The first paid renewal then uses the new plan and interval (`service.py:137-146`).
- **Downgrade or interval switch alone (rule 2):** these are scheduled, including a same-plan interval switch (`service.py:148-151`).
- **Upgrades and same-price moves (rules 1, 3, 4):**
  - Both lines are priced at the current interval and calculated exactly with `Decimal`, then each is rounded half-up on its own.
  - A negative total is scheduled instead of applied.
  - A zero total applies the change but issues no invoice.
  - An interval switch in the same request becomes the scheduled change; without one, any earlier scheduled change is discarded (`service.py:153-165`, `193-214`).
  - The upgrade is prorated from the current plan, not from a scheduled one (`current_plan` is looked up from `subscription.plan_code`).
- **Renewals (rules 2, 6, AC12):** a scheduled change is applied once, even if its plan has been retired since, and then cleared. When several missed periods are caught up, it applies from the first one, because each later loop step runs on the renewed copy (`service.py:169-187`).
- **Exports (AC31):** `InvalidPlanChange` is defined in `errors.py` and exported from `billing`.

One item in the spec isn't a code defect but still needs doing: the new `scheduled_change` field has to be saved and loaded by the production database-backed store. The spec asks for that shape to be agreed with whoever owns that store.

FINDINGS: 0
