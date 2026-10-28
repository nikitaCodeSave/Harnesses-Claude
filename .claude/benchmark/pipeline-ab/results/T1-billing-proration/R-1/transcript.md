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

I've read the package. Before writing anything, here are the decisions that shape the spec. Each one has my recommendation, so you can just reply "agree" or override by number.

**Round 1: core behaviour**

1. **Upgrades (the new plan costs more for the rest of the period).** The change takes effect today and the period dates stay the same. One invoice is issued today with a credit line for the unused part of the old plan and a charge line for the new plan over the same remaining days. Is that right?

2. **Downgrades (the new plan costs less).** The existing package has no credit balance and no refunds; `cancel` explicitly gives no refund. My recommendation is that downgrades take effect at the end of the current period. The customer keeps what they paid for, nothing is billed now (`None`), and the next renewal bills the new plan. The alternative is to apply them immediately and carry a credit forward, but that means a customer credit balance applied on future invoices, which is a bigger feature. Which do you want?

3. **Proration unit.** I'd prorate by calendar days: remaining days = `period_end − today`, with today counted as a day on the new plan, divided by the total days in the period. Each line is rounded to cents half-up. Is that OK, or do you need a different rule (e.g. the net amount rounded once)?

4. **Monthly → annual.** I'd make this take effect immediately: credit the unused monthly days, charge a full annual period, and start a new annual period today. Should it instead wait until the monthly period ends?

5. **Annual → monthly.** Applied immediately, this would produce a large credit and we have nowhere to put it. I'd treat it like a downgrade: it's scheduled for the end of the annual period and returns `None`. Agree?

6. **Trials.** If a subscription is still trialing, I'd switch the plan and/or interval right away, keep the trial end date, bill nothing (`None`), and bill the new plan when the trial ends. Agree?

**Round 2: edge cases and errors**

7. **Rejected requests.**
   - Canceled subscription → `SubscriptionNotActive`.
   - Unknown plan → `PlanNotFound`.
   - Retired target plan → `PlanNotAvailable`.
   - Same plan and same interval as now → `InvalidPlanChange`.

   One case is unclear: should a customer on a retired plan be allowed to switch only their interval on that same plan? I'd say no (`PlanNotAvailable`), because it would sell a retired plan/interval combination.

8. **Overdue renewal.** If `period_end <= today` but `renew_due` hasn't run yet, I'd reject with `InvalidPlanChange` rather than silently catching up the renewals. Agree?

9. **Pending scheduled change.** If a downgrade is already scheduled and the customer requests another change, I'd have the newest request replace the scheduled one. If the newest request is an upgrade, it applies immediately and the scheduled downgrade is dropped. Requesting the plan they're currently on would cancel the scheduled change rather than raise. Agree?

10. **Several upgrades in one period.** The second upgrade credits the remaining days at the plan the customer is currently on, which is the plan they actually paid for those days. Agree?

11. **Equal-cost change** (e.g. a different plan at the same price, so the net is 0). I'd apply it immediately and issue no invoice (`None`). Or would you rather have a zero-total invoice as a record of the change?

12. **Out of scope.** These would be non-goals unless you say otherwise:
    - credit balances and refunds
    - taxes
    - quantity or seat changes
    - changes dated in the past or future (the change is always "now")
    - notifying customers
    - undoing a change that has already been applied

Answer whichever you like. Anything you skip I'll take as agreement with my recommendation, and I'll write SPEC.md after your reply.

### [spec] user

Answers by number:

1. Agree, with these details. Upgrade versus downgrade is decided by the plans' monthly list price, whichever interval the customer is on or moving to. The upgrade invoice has exactly two lines, a credit and a charge. Both use the prices of the interval the customer is currently on. Each line is computed exactly (price x remaining days / period days) and rounded half-up on its own. The total is the sum of the two rounded lines.

2. Agree. A downgrade waits for the period end. Nothing is billed or credited at the request, and change_plan returns None. The renewal moves the customer to the cheaper plan and bills its full price. This also holds when the downgrade is combined with a switch to annual.

3. Agree on calendar days: real days in the period, 28-31 for a month and 365 or 366 for a year. Remaining days count from the change date inclusive up to the period end exclusive. Do not round the net difference once.

4. No, don't do it immediately. Interval switches wait for the period end in both directions, and we never refund unused annual time. Nothing is billed at the request. The renewal starts a period of the new interval and bills that interval's full price. If an upgrade comes with an interval switch, split it. The upgrade happens now, prorated at the current interval's prices. The interval switch happens at the period end.

5. Agree. It is scheduled for the period end and returns None, as in 4.

6. Agree, with one addition. Any change during a trial (up, down or interval) applies immediately in full, with no invoice, and the trial end date does not move. At trial end the customer is billed the full price of the plan and interval they are on by then.

7. Agree on the first four errors. A customer sitting on a retired plan may move off it like anyone else. I don't mind what happens with an interval-only switch on a retired plan. One correction on 'same plan and same interval': if something is scheduled, this cancels the scheduled change and returns None. Only when nothing is scheduled does it raise InvalidPlanChange. Rejected requests change nothing.

8. I don't mind. Your recommendation is fine.

9. Agree. Only one scheduled change exists at a time, and each request states the full target and replaces whatever was scheduled. An upgrade that applies now also discards what was scheduled, unless the same request schedules an interval switch under 4. A scheduled change hasn't happened yet, so an upgrade requested while a downgrade is scheduled is prorated from the current plan, not the scheduled one.

10. Agree, in the sense that each upgrade is prorated from the plan the customer is on at that moment.

11. I don't mind. Your choice is fine.

12. Fine as non-goals.

### [spec] agent

That covers nearly everything. Your rules leave three gaps, and I'd rather ask than guess. I've put my recommendation on each.

**Round 3**

A. **An upgrade by monthly price whose annual proration nets zero or negative.** Example: an annual customer moves from plan X (monthly 10, annual 120) to plan Y (monthly 12, annual 100). By your rule this is an upgrade, so it applies now and is prorated at annual prices. But the charge line is smaller than the credit line, so the invoice total is negative. That gives the customer money back, which contradicts "no credits/refunds." Options:
   - (a) Issue the two-line invoice as computed, even with a negative total.
   - (b) Reject with `InvalidPlanChange`.
   - (c) If the net isn't positive, treat it as a downgrade and schedule it for the period end.

   I recommend **(c)** for a negative net and **(a)** for exactly zero (the invoice records the switch). Alternatively, if your catalogue guarantees annual prices follow the same order as monthly prices, we can state that as an assumption and drop the question.

B. **A different plan with the same monthly price.** You left this to me. I'm reconsidering what I suggested in round 1 (apply now, no invoice). On an annual subscription, two plans with equal monthly prices can still have different annual prices, so "apply now, no invoice" could give someone days on a pricier annual plan for free. My pick is to treat it like a downgrade: scheduled for the period end, returning `None`. OK?

C. **A scheduled target plan that gets retired before the period ends.** I recommend that the scheduled change still happens at renewal, because the plan was available when the customer asked and "retired" only stops new sales. The alternative is to drop the scheduled change, so the customer renews on their current plan. Which do you prefer?

### [spec] user

A. My rule is that upgrade vs downgrade is decided only by the monthly list price, so I don't want a separate rule for this. I'm not going to rule on the negative case myself. Our catalogue doesn't have prices like that, so treat it as out of scope and don't build special handling. Any sensible behaviour is fine.

B. I don't mind. Your pick is fine.

C. I don't mind. Your recommendation is fine.

### [spec] agent

I've written SPEC.md. The interface section is copied verbatim from your request, followed by definitions, 27 numbered acceptance criteria, four worked examples, assumptions and non-goals. I haven't committed it, and no implementation exists yet.

Where you left the choice to me, I decided:
- **Same monthly price, different plan:** treated like a downgrade, so it waits for the period end and returns `None`.
- **Scheduled plan retired before renewal:** the change still applies, because the plan was available when the customer asked.
- **Overdue renewal** (`period_end <= today` but `renew_due` hasn't run): rejected with `InvalidPlanChange`. This applies to trials too.

Points written down as stated decisions:
- **Inverted catalogue prices:** if a plan's monthly price is higher but its annual price is lower, the outcome isn't defined. The spec lists this as a catalogue assumption and requires no special handling.
- **Interval-only switch on a retired plan:** either accepting it or raising `PlanNotAvailable` is acceptable.
- **`new_interval=None`** means "keep the current interval". Because each request replaces what was scheduled, it also drops a previously scheduled interval switch (criterion 17).
- **`InvalidPlanChange`** is exported from the `billing` package like the other errors (criterion 26). You didn't ask for this explicitly; it follows the existing convention.

The first worked example is a case where rounding each line separately gives 11.62 but rounding the net once would give 11.61. A test of that example will catch an implementation that rounds the net.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I've written 91 acceptance tests under `tests/acceptance/` covering all 27 acceptance criteria and the four worked examples. All but one fail for now, each because the feature doesn't exist yet. I didn't change anything under `src/`, and the existing 20 tests still pass.

## Command and output

```
$ python3 -m pytest tests/acceptance -q
...
70 failed, 1 passed, 20 errors in 0.22s
```

I grouped the failure messages to check that every failure comes from the missing feature, not from a broken test:

```
 72  AttributeError: 'BillingService' object has no attribute 'change_plan'
 17  ImportError: cannot import name 'InvalidPlanChange' from 'billing.errors'
  1  AttributeError: module 'billing' has no attribute 'InvalidPlanChange'
```

- **The 20 "errors":** these tests stop during setup rather than in the test itself, because they need `InvalidPlanChange` or a downgrade scheduled beforehand. I load `InvalidPlanChange` inside each test rather than at the top of the file, so its absence fails tests one by one instead of stopping pytest before it runs any of them.
- **The 1 pass:** `test_subscribe_renew_cancel_unchanged_without_plan_change` checks criterion 27: `subscribe`/`renew_due`/`cancel` behave as before when no change is ever requested. It should pass now and keep passing. The other criterion-27 test checks that one subscription changing plan doesn't affect another subscription, and that one fails as it should.

## Files

| File | Criteria |
|---|---|
| `conftest.py` | Plans built around the worked examples, clock set to 2026-10-01 |
| `test_change_plan_rejections.py` | 1–7 |
| `test_change_plan_trial.py` | 8–9 |
| `test_change_plan_upgrades.py` | 10–14, plus the per-line rounding, leap-year and upgrade-with-interval-switch examples |
| `test_change_plan_scheduled.py` | 15–20, plus the downgrade example |
| `test_change_plan_renewal.py` | 21–24 |
| `test_change_plan_general.py` | 25–27 |

## Choices worth checking

- **Expected values** come from the spec's formula, rounded half-up, line by line. I checked the formula by reproducing the spec's examples exactly (−2.90 / 14.52 / 11.62 and −32.79 / 81.97 / 49.18) before using it for the other cases, such as February's 28 days or the first and last day of a period.
- **Exact half cent:** one test makes the charge land on exactly half a cent (23.345 → 23.35). I only test this on the charge line. On a negative credit line, "half-up" could mean rounding away from zero or towards zero, and the spec doesn't say which.
- **Scheduled changes** aren't exposed anywhere, which the spec intends. The tests check them only through what renewal bills. To check that a change is cleared after it applies, a test asks for the current plan and interval again and expects `InvalidPlanChange` (criterion 6).
- **Line order** on an upgrade invoice isn't fixed by the spec, so the tests compare the two line amounts sorted rather than in order.
- **Retired plan, interval-only switch:** the spec accepts either outcome, so there is no test for it. Annual prices running opposite to monthly prices are out of scope per the spec, so no test either.
- **A few implied rules:** some tests check rules that follow from combining criteria rather than from one criterion alone. Examples: asking for your own retired plan raises `InvalidPlanChange`, not `PlanNotAvailable` (4 + 6), and a change is allowed again once `renew_due` has caught up (5). Each one is labelled with the criterion it comes from.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

I've added `BillingService.change_plan` as SPEC.md describes, and the acceptance tests and the existing suite both pass. I didn't modify anything in `tests/`.

```
$ python3 -m pytest -q
........................................................................ [ 64%]
.......................................                                  [100%]
111 passed in 0.04s
```

That is 91 acceptance tests and the 20 tests that were already there (I also ran each set separately and both passed in full).

**What changed** (all in `src/billing/`):
- **`errors.py` and `__init__.py`:** new `InvalidPlanChange(BillingError)`, exported from the package.
- **`subscriptions.py`:** a subscription can now carry one optional `scheduled_change` (a plan and an interval), which is empty by default. Subscriptions that never request a change look exactly as before.
- **`money.py`:** new `prorate(amount, remaining_days, period_days)` helper. It works in whole cents and rounds half-up, so each line is computed exactly and rounded on its own (e.g. 23.345 becomes 23.35).
- **`service.py`:**
  - `change_plan` checks the request in this order: subscription exists, not canceled, plan exists, plan not retired (unless it's the current plan), renewal not overdue, target actually differs.
  - During a trial, any change applies immediately with no invoice.
  - An upgrade on a paid period applies today and issues one invoice with a credit line and a charge line, both at the current interval's prices. If it also asks for an interval switch, that switch is scheduled.
  - Downgrades and interval switches are scheduled. Each new request replaces whatever was scheduled, and asking for the current plan and interval cancels it.
  - At renewal, the scheduled change is applied to the first period being renewed and then cleared, even if its target plan has been retired since.

**Two choices the spec left open:**
- A customer on a retired plan can switch interval only (keeping that plan); the spec allows accepting or rejecting this.
- The scheduled change is stored on the subscription itself, so a database-backed store would need to save that field too.

I haven't committed anything. Running the tests also created an untracked `src/billing/__pycache__/` folder.

### [review1] operator

Review the changes since commit 7f9866c310e508fcbc0cfd97a8bbafc09f7c9e1d (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md, so there's nothing to fix.

I read the full diff and the surrounding modules and checked each acceptance criterion. All 111 tests pass, including the ones in `tests/acceptance/`.

- **Rejected requests (1–7):** Each error is raised in the right case. Every check runs before anything is saved. In `_upgrade` (`src/billing/service.py:157`), both invoice lines are built before the subscription is saved, so a rejected request leaves nothing changed.
- **Trial (8–9):** A change on a trialing subscription switches the plan and interval right away and leaves `period_end` alone. Nothing is billed, and the next renewal bills the full price of whatever plan is current.
- **Upgrades (10–14, 18, 20):** Both lines are priced on the current interval. Each line is rounded half-up on its own in integer cents (`prorate`, `src/billing/money.py:23`). A requested interval switch is scheduled for the new plan, and any other scheduled change is discarded. I worked the two rounding examples by hand: 31 days gives −2.90 + 14.52 = 11.62, and the leap-year annual case gives −32.79 + 81.97 = 49.18. Both match the spec.
- **Scheduled changes (15–17, 19):** Downgrades, same-price plan changes and interval switches replace any earlier scheduled change. `new_interval=None` resolves to the current interval, and asking for the current plan and interval cancels the scheduled change.
- **Renewal (21–24):** The scheduled change applies on the first renewal of a catch-up. The new period uses the scheduled interval and is billed at the scheduled plan's full price, dated on the period start. It still applies if that plan has been retired, and canceled subscriptions are skipped.
- **General (25–27):** All invoices go through `_issue_invoice`. `InvalidPlanChange` is exported, and subscriptions that never change plan renew exactly as before.

FINDINGS: 0
