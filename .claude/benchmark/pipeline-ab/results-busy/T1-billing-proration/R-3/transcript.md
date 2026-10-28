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

I've read the package. Some facts that shape the questions:

- An invoice counts as the charge. There's no payment status, no customer credit balance, and no refund path (`cancel` says "No refund").
- `LineItem` doesn't reject negative amounts, so an invoice could technically total less than zero.
- Subscriptions can be `TRIALING`, `ACTIVE` or `CANCELED`. Plans can be retired or free (price 0). `renew_due` catches up overdue periods.

**Round 1: the core money policy**

1. **Downgrades: immediate or at period end?** When the customer moves to something cheaper, their unused credit is bigger than the new charge. With no credit balance or refunds today, the leftover has to go somewhere. Options:
   - (a) **Schedule downgrades for the end of the current period.** Nothing is billed now, so we return `None`. The next renewal bills the new plan and interval at full price. Nobody overpays and no credit mechanism is needed. *(My recommendation. It also explains why the interface allows `None`.)*
   - (b) Apply immediately and issue a negative-total invoice, i.e. a credit note.
   - (c) Apply immediately and add a stored credit balance that later invoices consume. This is much bigger scope.
   
2. **What counts as an upgrade?** I'd define it by money: a change is an upgrade if the new plan/interval's prorated charge for the time left is greater than the credit for the unused current period. Switching to a more expensive plan at the same interval is the obvious case. Is a monthly→annual switch on the *same* plan an upgrade, billed now? Is annual→monthly a downgrade, scheduled?

3. **Upgrade mechanics.** For a same-interval upgrade, I assume the period dates stay the same and we charge the price difference prorated over the remaining days. When the interval changes (e.g. monthly basic → annual pro), I assume a **new period starts today**: credit the unused part of the current period, charge the full new annual price, one invoice with both lines. OK?

4. **Proration unit:** I propose calendar days. Remaining days = `period_end − today`, divided by the total days in the current period, each line rounded half-up to cents. The day of the request counts as unused, so a change on `period_start` gives a full credit. Agree, or do you want the request day charged at the old plan?

### [spec] user

1. Agreed, option (a). A downgrade waits for the end of the period. Nothing is billed or refunded at the request, and `change_plan` returns `None`. The renewal on the period end moves the customer to the cheaper plan and bills its full price. This also holds when the downgrade comes with a switch to annual.

2. I don't want it defined by prorated money. Upgrade or downgrade is decided only by the plans' monthly list price (`monthly_price`), whatever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade. Switching interval on the same plan is neither. It waits for the period end in both directions (monthly→annual and annual→monthly). Nothing is billed at the request, and the renewal starts a period of the new interval at that interval's full price. We never refund unused annual time.

3. The same-interval upgrade is right: it applies today, the period dates don't move, and the next renewal bills the new plan at full price. The interval-change assumption is wrong, though. We never start a new period early. If an upgrade comes with an interval switch, split it. The upgrade happens now, prorated at the prices of the interval the customer is currently on. The interval switch happens at the period end.

The upgrade invoice has exactly two lines. One is a negative credit for the unused part of the current plan. The other is a positive charge for the same remaining days on the new plan. Both use the current interval's prices. Each line is computed as price × remaining days ÷ period days, with no rounded daily rate in between. Each line is rounded half-up to cents on its own, and the total is the sum of the two rounded lines.

4. Calendar days, agreed. Use the real length of the period, so 28–31 days for a month and 365 or 366 for a year. Remaining days run from the change date, inclusive, up to the period end, exclusive. The customer gets the new plan for the whole request day, so a change on `period_start` gives a full-period credit and a full-period charge.

Example: Pro→Premium on Mar 11 in a Mar 1–Apr 1 period leaves 21/31. The lines are -20.32 and +50.81, so the total is 30.49.

### [spec] agent

Your example works: Premium at 75.00/month gives 30 × 21/31 = 20.32 and 75 × 21/31 = 50.81. Your answers settle the main rule: only upgrades are billed at the request. Every other change waits for the period end and returns `None`. That leaves the edge cases.

**Round 2: pending changes and edge cases**

5. **Overlapping requests.** A change can now be waiting for the period end: a downgrade, an interval switch, or both. What happens when another request arrives before the period ends? I propose the newest request replaces anything pending:
   - A pending downgrade to Basic followed by an upgrade to Premium: Premium applies now and the downgrade is dropped.
   - A pending downgrade followed by a request for the current plan and interval clears the pending change. This works as "undo my downgrade" and bills nothing.
   - A request for the current plan and interval with nothing pending raises `InvalidPlanChange`.
   
   Agree?

6. **Two different plans with the same `monthly_price`.** Is that an upgrade (applies now), a downgrade (waits), or rejected with `InvalidPlanChange`?

7. **A negative or zero upgrade total.** Upgrades are classified by monthly price but billed at the current interval's prices. So an annual customer could "upgrade" to a plan with a higher monthly price but an equal or lower annual price. Do we reject that with `InvalidPlanChange`, issue the two-line invoice anyway (zero or negative total), or treat it as a change that waits?

8. **Trials.** During a trial no period has been paid for, so I'd apply plan and interval changes immediately in every direction and bill nothing (`None`). The trial end date stays the same, and the first paid period uses the new plan and interval. OK?

9. **Overdue renewals.** If `period_end <= today` (`renew_due` hasn't run yet), I'd raise `InvalidPlanChange` rather than silently renewing first. OK?

10. **Retired plans.** A retired target raises `PlanNotAvailable`. Two questions:
    - (a) Can a customer on a retired plan switch interval while staying on it?
    - (b) If a scheduled downgrade's target is retired before the period ends, does the renewal still move them onto it?

11. **Visibility.** Should a pending change be readable on the `Subscription` itself, e.g. so support can see "downgrades to Basic on Apr 1"? Or is that only internal state as far as the spec is concerned?

### [spec] user

5. Agreed on all three. One addition: an upgrade requested while a downgrade is pending is prorated from the current plan, not the scheduled one. On Pro with Basic scheduled on Mar 5, requesting Premium on Mar 11 gives an invoice of 30.49. An upgrade that applies now also discards whatever was pending, unless the same request schedules an interval switch. Each request states the full target (plan and interval) and replaces what was pending.

6. I don't mind. Pick whatever is sensible.

7. By my rule that is still an upgrade, because the classification uses only the monthly list price. It applies now and gets the two-line invoice at the current interval's prices. I don't mind what happens in the odd case where the total nets to 0.00 or less. Handle it however you think best.

8. Agreed. During a trial any change applies immediately in full, `change_plan` returns `None`, and no invoice is recorded. The trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they are on by then.

9. I don't mind. Any sensible behaviour is fine.

10. (a) I don't mind. (b) I don't mind either. Use your recommendation for both.

11. I don't mind. Store it however suits the code.

### [spec] agent

I've written the spec to `SPEC.md`. It has the interface copied verbatim, the rules you set, 28 acceptance criteria with worked amounts, and the non-goals. The example amounts were worked by hand because the sandbox blocked inline Python. They match your Mar 11 figure (−20.32 / +50.81 = 30.49), but it's worth recomputing them once before tests are written against them.

The examples add a **Premium** plan at 75.00/month and 750.00/year to the existing Basic and Pro test plans. 75.00 is the price your Mar 11 figure works out to.

Where you said "don't mind", these are the choices I made:

- **Same monthly price (Q6):** a different plan with an equal `monthly_price` is not an upgrade. It waits for the period end and returns `None`, since there's no price difference to bill now.
- **Upgrade netting to 0.00 or less (Q7):** the two-line invoice is still issued exactly as computed. That keeps "exactly two lines" true with no exceptions.
- **Overdue renewal (Q9):** if `period_end <= today` and `renew_due` hasn't run, the request raises `InvalidPlanChange`.
- **Retired plans (Q10):**
  - A customer on a retired plan can still switch interval on it, or undo a pending change.
  - Any other change to a retired plan raises `PlanNotAvailable`.
  - A downgrade already scheduled onto a plan that's retired before the period ends still takes effect at the renewal.
- **Pending changes (Q11):** how they're stored is up to the implementation. There's no public way to read one, and undoing means requesting the current plan and interval.
- **Error order:** errors are checked in this order: subscription not found, canceled, plan not found, plan retired, overdue, no-op. A rejected request changes nothing, and any pending change survives it.

The spec also covers some cases you didn't rule on:

- **Rounding ties on credits:** the amount is rounded away from zero, so a credit of 5.005 becomes −5.01. Criterion 8 shows this.
- **`new_interval=None`:** it means the subscription's current interval, not a pending one. So it can drop a pending switch to annual (criterion 15).

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've written tests for all 28 acceptance criteria in `tests/acceptance/`, and they fail as expected: 40 of the 41 tests fail, all because the feature doesn't exist yet. Nothing under `src/` was changed.

**Command:**
```
python3 -m pytest -q
```

**Output (summary):**
```
FAILED tests/acceptance/test_change_plan.py::test_ac01_upgrade_invoice_is_returned_and_recorded
FAILED tests/acceptance/test_change_plan.py::test_ac02_upgrade_applies_now_and_renews_at_full_price
...  (40 FAILED lines in total, one per acceptance test except the one below)
FAILED tests/acceptance/test_change_plan.py::test_ac28_cancel_with_pending_change_drops_the_change
40 failed, 21 passed in 0.33s
```

The 40 failures have only two causes:
```
     35  AttributeError: 'BillingService' object has no attribute 'change_plan'
      5  ImportError: cannot import name 'InvalidPlanChange' from 'billing.errors'
```

The 21 passing tests are the 20 existing ones plus `test_ac27_existing_suite_passes_unchanged`. That test checks criterion 27 ("the existing test suite passes unchanged") by running the original suite in a subprocess, so it is meant to pass now and keep passing.

**What's in the tests**
- **`conftest.py`** sets up the spec's three plans (Basic, Pro, Premium) and a clock starting on 2026-01-15. The clock can only move forward, so it starts on the earliest date any example uses. My first version started on 2026-03-01, which made four tests fail for the wrong reason; that's fixed.
- **`test_change_plan.py`** has one or more tests per criterion, named `test_acNN_…`. They only use what the spec names: `change_plan`, `subscribe`, `renew_due` and `cancel` on `BillingService`; `get_subscription`, `invoices_for`, `add_plan` and `retire_plan` on the store; the clock; `Interval`; and the error classes.
- **Expected values:** every amount and date is copied from the spec. I recomputed each proration example by hand and they all add up, including the 184-day annual cases and the 5.005 → 5.01 rounding tie.
- **`InvalidPlanChange`** is imported inside each test rather than at the top of the file. Otherwise the missing class would stop the whole file from loading instead of failing those five tests one by one.
- **Not tied to the implementation:** the tests don't depend on line order or description text (which the spec leaves open), or on how the pending change is stored. "Subscription unchanged" compares the whole subscription only after a rejected request. After a successful one it checks just the plan, interval and dates.

**Beyond the numbered criteria**
- I added four short tests for the check order in the spec's "Rejected requests" table.
- Two behaviours in the spec have no criterion and no test: a scheduled change applying from the first of several missed renewals, and an upgrade invoice that totals 0.00 or less. Say if you want tests for those too.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

`BillingService.change_plan` is built and all tests pass, including every acceptance test.

**Test run:**
```
$ python3 -m pytest -q -p no:cacheprovider tests/acceptance
.........................................                                [100%]
41 passed in 0.12s

$ python3 -m pytest -q -p no:cacheprovider
...............................................................          [100%]
63 passed in 0.12s
```
The full run of 63 tests is the 41 acceptance tests plus the 22 tests in the existing suite. I didn't touch `tests/acceptance/`.

**What changed:**
- **`service.py`**: `change_plan` runs the rejection checks in the order the spec's table gives. After that:
  - **Same plan and interval as now:** this undoes a pending change, or raises `InvalidPlanChange` if nothing is pending.
  - **Trial:** the change applies right away and nothing is billed.
  - **Downgrade or interval switch:** it is scheduled for the period end.
  - **Upgrade:** the plan changes now and an invoice is issued with two lines, a credit for the old plan and a charge for the new one. If the interval is also changing, that part waits for the period end.
  
  At renewal, a scheduled change is applied before billing, so catching up several missed periods uses it from the first one. Cancelling also drops any pending change.
- **`subscriptions.py`**: the pending change is stored as a new optional field on `Subscription`, `scheduled_change: ScheduledChange | None = None`. It defaults to `None`, so existing subscriptions and code are unaffected.
- **`money.py`**: a new `prorate(amount, numerator, denominator)` helper works the line amounts out in whole cents using integers, so there's no rounding step in between. Halves round away from zero, and for a credit that rounds the size of the amount before making it negative.
- **`errors.py`**: adds `InvalidPlanChange(BillingError)`. It and `ScheduledChange` are also exported from `billing/__init__.py`.
- **`README.md`**: the layout section now lists the new pieces, and there's a short note on how plan changes work.

I also added two small unit tests for `prorate` to `tests/test_money_and_periods.py`, which is why the existing suite now has 22 tests. Nothing has been committed yet.

### [review1] operator

Review the changes since commit 79929d24eff009a95ae9dafbd55889b80552ad68 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps. I compared the diff since `79929d2` against every rule in SPEC.md and acceptance criteria 1–28, and nothing needs fixing.

- **Rejected requests:** the checks in `change_plan` (`src/billing/service.py:112-130`) run in the order the spec's table gives. They all run before anything is saved, so a rejected request leaves the invoices, the subscription and any pending change as they were. Only an active subscription is rejected as overdue; a trialing one is not, as the spec says.
- **Replacing a pending change:** every successful path either sets `scheduled_change` to what the new request asks for or clears it.
- **Upgrades:**
  - Whether it counts as an upgrade depends only on the monthly list price.
  - The credit uses the plan the customer is on now, never a pending one.
  - Both lines use current-interval prices.
  - The period dates don't move.
  - If the upgrade also changes interval, the switch is kept as a pending change for the renewal.
  - An invoice that nets to zero or less is still issued, because `Invoice` doesn't check the total.
- **Rounding:** `prorate` (`src/billing/money.py:23`) works from the exact fraction in whole cents and rounds the size of each line half-up before adding the sign. I checked the spec's examples by hand (30.00×21/31 → 20.32, 300×184/365 → 151.23, 10.01×15/30 → 5.01) and they come out right.
- **Renewals:** `_renew` applies the pending change on the first renewal, so a subscription caught up over several missed periods switches from the first one. It doesn't check whether the plan is retired, so a scheduled downgrade onto a plan retired in the meantime still applies.
- **Trials:** a change applies right away with no invoice, and the trial end date doesn't move.
- **Cancel:** canceling now also clears any pending change, so it can never take effect.

I ran the full test suite, including `tests/acceptance`: 63 passed.

FINDINGS: 0
