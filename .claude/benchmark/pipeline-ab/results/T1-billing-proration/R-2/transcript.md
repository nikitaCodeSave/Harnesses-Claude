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

I've read the whole package. A few facts from the code affect the questions:

- There's no customer credit or balance anywhere. `LineItem` doesn't forbid negative amounts, but nothing today issues refunds (`cancel` says "No refund").
- A `Subscription` has only one plan and interval. There's nowhere to store a change scheduled for a later date.
- Billing periods can be any length (trials, month clamping), and a subscription can be overdue (`period_end <= today` before `renew_due` has run).

**Round 1: the money model**

1. **Proration unit.** I'd prorate by calendar days: unused value = price paid for the current period × (days left ÷ days in the period), with today counted as a day left. Rounding would be once per line, to cents, half up. OK?

2. **Upgrades** (the new plan costs more for the rest of the period). Do they take effect immediately, with one invoice today showing a credit line for the unused old plan and a charge line for the new plan's remaining days? The period dates would stay the same and the next renewal would bill the new plan at full price.

3. **Downgrades** (cheaper). Since there's no credit balance, which of these?
   - (a) **Apply at the next renewal.** The customer keeps the current plan until `period_end`, nothing is billed now (return `None`), and the renewal bills the new plan. This needs the subscription to store a pending change. It's the simplest option with no refunds, and the most common in practice.
   - (b) **Apply immediately and issue a negative-total invoice** (a credit note) today.
   - (c) **Apply immediately and carry the credit** onto the next renewal invoice as a negative line.

   I recommend (a).

4. **Interval switches.**
   - Monthly → annual: I'd make it immediate. A new annual period starts today, and today's invoice charges the full annual price minus a credit for the unused monthly days.
   - Annual → monthly: I'd treat it like a downgrade, so it's scheduled for the end of the annual period. Otherwise it creates a large credit.

   Agree?

5. **What counts as "pays more".** When the interval changes, I'd compare the cost of the remaining days, not the list prices. The rule would be: if the charge for the new plan from today is at least the credit, bill it now; otherwise schedule it. Or do you want an explicit rule instead, such as "any switch to annual is immediate, any switch to monthly is scheduled"?

### [spec] user

1. Calendar days, yes, but be precise: remaining days = days from the change date (inclusive) to period end (exclusive), over the real number of days in that period (28-31 for a month, 365/366 for a year). Each line is price × remaining / period days, computed exactly and rounded half-up to cents on its own line. Total is the sum of the two rounded lines.

2. Yes. Upgrade is immediate, one invoice dated the change date with exactly two lines: a negative credit for the unused old plan and a positive charge for the same remaining days on the new plan, both at the prices of the interval the customer is currently on. Period dates stay the same and the next renewal bills the new plan in full. Upgrade vs downgrade is decided by the plans' monthly list price, whatever the interval.

3. (a). Downgrades wait for the period end: change_plan returns None, nothing billed or credited, the customer keeps the current plan, and the renewal moves them to the cheaper plan at its full price. That includes a downgrade combined with a switch to annual.

4. No, that's not what I want. Interval switches in both directions wait for the end of the period; we never refund unused annual time. Nothing is billed at the request; the renewal starts a period of the new interval and bills that interval's full price. If an upgrade comes together with an interval switch, split it: the upgrade happens now as in 2 (prorated at the current interval's prices), and the interval switch happens at period end.

5. Neither. Upgrade vs downgrade is purely the monthly list price comparison, and interval switches are always scheduled for period end, so no remaining-days cost comparison is needed.

### [spec] agent

That settles the money model. **Round 2: edge cases.** Each has my recommendation; a plain "yes" accepts it.

6. **Same monthly price, different plan.** Is that an upgrade (immediate; the invoice nets to about zero), a downgrade (scheduled), or an `InvalidPlanChange`? I recommend treating it as a **scheduled** change, so nobody gets a zero-value invoice.

7. **The upgrade invoice can come out ≤ 0.** On an annual subscription, plan B can have a higher monthly price but a lower annual price. Also, with one day left, both lines can round to the same cent. Should we still issue the two-line invoice? I recommend **yes, always issue it**, because the rule stays purely "monthly list price decides". The alternative is `InvalidPlanChange` when the total would be negative.

8. **Trials.** The customer hasn't paid for the trial period, so crediting unused trial days would be wrong. I recommend that any change during a trial applies **immediately with no invoice** (returns `None`), including interval switches. The first paid period then bills the new plan and interval in full.

9. **Pending changes.** There's at most one pending change per subscription, and a new request replaces it. Specifically:
   - Upgrade while a downgrade is pending: the upgrade applies now and the pending downgrade is dropped. An interval switch in the same request stays pending.
   - A request that resolves to exactly the current plan and interval cancels any pending change and returns `None`. With nothing pending, it raises `InvalidPlanChange`.
   - Should the pending plan and interval be readable on `Subscription`? I recommend yes, as optional fields that are `None` when nothing is pending.

10. **Retired plans.** Moving to a retired plan raises `PlanNotAvailable`. If the customer stays on their current retired plan and only switches interval, I recommend **allowing it**, since they're an existing customer, not a new sale.

11. **Other states.**
    - Canceled subscription: `SubscriptionNotActive`.
    - Unknown subscription or plan: `SubscriptionNotFound` / `PlanNotFound`.
    - Overdue subscription (`period_end <= today`, `renew_due` hasn't run): I recommend `InvalidPlanChange`. The caller runs renewals first, because otherwise the change date falls outside any billed period.

12. **Catch-up renewals.** If several overdue periods are renewed at once, the pending change applies at the first of them and every later period bills the new plan and interval. OK?

### [spec] user

6. Same monthly price: I don't mind, go with your recommendation (scheduled).

7. Yes, always issue the two-line invoice. The rule stays purely the monthly list price; do not reject a negative total. If the total is exactly 0.00, I don't mind whether it's recorded.

8. Agreed, with one detail: during a trial any change (up, down or interval) applies immediately in full, returns None, no invoice. The trial end date does not move, and at trial end the customer is billed the full price of the plan and interval they are on by then.

9. Agreed on all three points. An upgrade applying now discards anything pending, and an interval switch in the same request is scheduled for the period end. A request for the current plan and interval cancels what's pending and returns None; with nothing pending it raises InvalidPlanChange. Storage of the pending change is up to you, so optional fields are fine. Also note a pending change has not happened yet: an upgrade requested while a downgrade is pending is prorated from the current plan (e.g. on Pro with Basic pending, upgrading to Premium is prorated from Pro).

10. Yes, allow it. I don't mind that case; customers on a retired plan can move off it like anyone else, and moving to a retired plan raises PlanNotAvailable.

11. Canceled raises SubscriptionNotActive, unknown plan raises PlanNotFound. Unknown subscription and the overdue case: I don't mind, go with your recommendation.

12. I don't mind, your proposal is fine. Just make sure the renewal where the change applies bills the new plan at its full price.

### [spec] agent

I've written the spec to `SPEC.md`. I re-ran the worked example (Pro 30.00 → Premium 50.00, 16 of 31 days left) and it comes to −15.48 + 25.81 = 10.33, as the spec says. Nothing is committed.

It contains:
- the fixed interface, copied verbatim;
- definitions: upgrade means the monthly list price is strictly higher, and remaining days run from the change date (inclusive) to period end (exclusive);
- a table of what each kind of request does now and what happens at the next renewal;
- the trial rules, pending-change rules and a table of rejection errors;
- 19 acceptance criteria and the non-goals.

Where you said "don't mind", I wrote these in as fixed decisions:
- **Overdue subscription** (`period_end` on or before the change date, renewals not yet run): raises `InvalidPlanChange`.
- **Unknown subscription:** raises `SubscriptionNotFound`.
- **A 0.00 upgrade invoice:** it may or may not be recorded, but the return value must match. That's either the recorded invoice or `None`.
- **Catch-up renewals:** a pending change applies at the first overdue renewal, and every later one bills the new plan and interval.

I also added three things you didn't ask for explicitly; check them:
- `InvalidPlanChange` is exported from the `billing` package like the other errors.
- A rejected request changes nothing: no update to the subscription, its pending change or its invoices.
- The two proration lines appear in a fixed order, credit first, then charge.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've written the acceptance tests in `tests/acceptance/`. As you asked, none of the feature is implemented, and every test fails except the four that check existing behaviour still works (criterion 19).

**Command run:**
```
python3 -m pytest tests/acceptance -q
```
**Output (summary line):**
```
73 failed, 4 passed, 6 errors in 0.24s
```

Every failure and error is caused by the feature not existing yet. None comes from a broken test:
```
     64  AttributeError: 'BillingService' object has no attribute 'change_plan'
     14  AttributeError: module 'billing.errors' has no attribute 'InvalidPlanChange'
      1  AttributeError: module 'billing' has no attribute 'InvalidPlanChange'
```
- **The 6 errors:** these are rejection tests that first set up a pending change by calling `change_plan` inside a fixture. That call fails during setup, so pytest reports an error rather than a failure.
- **The 4 passing tests:** these are the criterion 19 checks of `subscribe`, `renew_due` and `cancel`. They pass now on purpose, to catch anything the feature breaks.
- **Existing tests:** run without the new folder (`python3 -m pytest tests --ignore=tests/acceptance -q`), the existing suite still gives `20 passed`.

**Files, by criterion**
- `conftest.py`: overrides the shared fixtures. The clock starts on 2026-01-10, so the spec's example period of 2026-01-10 to 2026-02-10 (31 days) can be set up directly. It also adds test plans for edge cases:
  - `premium` (50/500)
  - `flex` (higher monthly price than Pro, lower annual price)
  - `level` (same annual price as Pro, so the proration nets to zero)
  - `team` (same monthly price as Pro, higher annual price)
  - `plus` (12.33, which lands a line exactly on a half cent)
- `test_plan_change_upgrades.py`: criteria 2–6, 10 and 14.
- `test_plan_change_deferred.py`: criteria 7–9, 11–13 and 18.
- `test_plan_change_trial_and_retired.py`: criteria 15 and 17.
- `test_plan_change_rejections.py`: criteria 1 and 16.
- `test_plan_change_regression.py`: criterion 19.

**How the tests are built**
- **Public interface only:** they use `change_plan`, `subscribe`, `renew_due`, `cancel`, the store's public methods and `FixedClock`. A pending change can't be seen directly, so the tests check it by running the next renewal and looking at what gets billed.
- **Expected values come from the spec's formulas,** with the arithmetic in comments. For example, 30.00 × 16 ÷ 31 = 15.48 and 50.00 × 16 ÷ 31 = 25.81, giving a total of 10.33. Some cases are chosen so a plausible wrong implementation would fail:
  - rounding the total instead of each line gives 10.32;
  - always dividing by 365 in a 366-day year gives 150.41 instead of 150.00;
  - rounding 6.165 to the nearest even cent instead of half up gives 6.16 instead of 6.17;
  - crediting the pending plan instead of the current one gives −5.16 instead of −15.48.
- **Rejections (criterion 16):** each test records every subscription and its invoices before the call and checks they are identical afterwards. Where a pending change existed, it also checks that change still applies at the next renewal.
- **Zero-total invoice:** the spec allows either behaviour, so that test accepts either a recorded invoice or `None` with nothing recorded, as long as the return value matches what was stored.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

`change_plan` is built and all tests pass: the 83 acceptance tests and the 20 existing tests.

```
$ python3 -m pytest -q
........................................................................ [ 69%]
...............................                                          [100%]
103 passed in 0.04s
```

I didn't change anything under `tests/` and I haven't committed.

**What changed**
- **`errors.py` / `__init__.py`**: added `InvalidPlanChange(BillingError)` and exported it from the `billing` package.
- **`subscriptions.py`**: a subscription now carries its pending change as two new fields, `pending_plan_code` and `pending_interval`. Both default to `None`, so existing subscriptions behave as before, and they must be set together or not at all.
- **`service.py`**:
  - **`change_plan`** checks for rejections in the order of the spec's table, so a rejected request saves nothing.
  - **Trials:** the change applies straight away and nothing is billed.
  - **Requesting the current plan and interval:** cancels the pending change if there is one; otherwise it raises `InvalidPlanChange`.
  - **Downgrades and interval switches:** become the pending change.
  - **Upgrades:** switch plan now and issue the two-line proration invoice at the current interval's prices. If the request also switches interval, that switch becomes the new pending change.
  - **Renewals:** a pending change is applied and cleared at the first renewal, before the period length is worked out. When several overdue periods are caught up at once, every one of them uses the new plan and interval.

**One choice the spec left open:** an upgrade that prorates to exactly 0.00 still records its invoice and returns it, rather than returning `None`. The spec allows either, as long as the return value matches what was recorded.

### [review1] operator

Review the changes since commit 33c680983e74e857375f72e7d99d95bebd723877 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md.

I compared the diff since `33c6809` (all of it is uncommitted) with every behaviour row, rejection row and acceptance criterion. The full suite passes: 103 tests, including the new `tests/acceptance/` tests.

What I checked:

- **Rejections** (`src/billing/service.py:115-128`): each error from the table is raised before anything is saved, so a rejected request changes nothing and leaves any pending change as it was. A retired plan is allowed when it is the current plan. The overdue check is `period_end <= today`.
- **Upgrade vs downgrade** (`service.py:141`): an upgrade needs a strictly higher monthly price, judged against the current plan, not the pending one. An equal price, or a switch that changes only the interval, takes the deferred path.
- **Proration** (`service.py:159-180`): both lines use the current interval's prices and the real period length, so annual periods divide by 365 or 366. Each line is rounded on its own with `to_money` (half up). The invoice is issued even when its total is negative, and the recorded invoice is the one returned.
- **Pending changes**:
  - Upgrade with the same interval: anything pending is cleared.
  - Upgrade with an interval switch: the new plan plus the new interval becomes the pending change.
  - Downgrade or interval-only switch: the pending change is replaced.
  - Current plan and interval requested while something is pending: the pending change is cancelled and the method returns `None`.
- **Trials** (`service.py:130-134`): the change applies immediately, nothing is left pending, and the trial end date doesn't move.
- **Renewal** (`service.py:183-189`): a pending change applies at the first overdue renewal and is then cleared. Later catch-up renewals use the new plan and interval, and the period length follows the new interval.
- **Error class**: `InvalidPlanChange` subclasses `BillingError` and is exported from the `billing` package.
- **Existing behaviour**: unchanged when no plan change is requested, because the new pending fields default to `None`.

FINDINGS: 0
