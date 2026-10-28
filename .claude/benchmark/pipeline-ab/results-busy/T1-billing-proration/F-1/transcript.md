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

I've read the whole package (service, store, periods, money, tests layout). Before I write anything, here are the decisions that shape the spec. For each one I've put my recommendation in **bold**, so you can just answer "agree" where it fits.

**1. When does each kind of change take effect?**
- (a) **Upgrades take effect immediately and are billed now. Downgrades also take effect immediately, and the unused part of the old plan comes back as a credit.**
- (b) Upgrades take effect immediately, but downgrades are scheduled for the next renewal (`period_end`). In that case `change_plan` returns `None` and nothing changes until then.

The "returns `None` when nothing is billed" in your request makes me think (b) may be what you have in mind. Which is it?

**2. What counts as an upgrade and what counts as a downgrade?**
**Compare what the customer would pay per day for the rest of the period: the new plan's price at the new interval, prorated, against the old plan's price at the old interval, prorated.** If the new one is higher, it's an upgrade. Or do you want something simpler, such as comparing monthly list prices?

**3. How is proration calculated?**
**Use calendar days. Credit = old price × (days left in the current period ÷ days in the current period). Today counts as a "new plan" day, and the credit is rounded half-up to the cent.** Is that right, or do you use a different basis, such as 30-day months or prorating to the second?

**4. What happens when the net amount is negative (a downgrade, or switching from annual to monthly)?**
The codebase has no customer credit balance. The options are:
- (a) Issue an invoice with a negative total, i.e. a credit note. The invoice and line-item code already accept negative amounts.
- (b) Floor the amount at zero and lose the credit (bad: the customer pays twice).
- (c) Add a credit balance that is used up against future invoices.

I'd go with **(a) for now and leave (c) out of scope**. Does finance accept negative invoices?

**5. What happens to the billing period when the interval changes?**
**The billing cycle restarts today. Monthly → annual: credit the unused part of the month and charge a full year starting today, so the new period is [today, today + 12 months). Annual → monthly: credit the unused part of the year and charge a full month starting today.** And when the interval stays the same, should the existing period dates stay the same, with only the remaining days charged at the new plan?

I'll ask about edge cases next: trials, overdue renewals, retired plans, no-op changes and repeated changes within one period.

### [spec] user

1. It's (b). Upgrades take effect right away. Downgrades wait for the end of the period. Nothing is billed, refunded or credited when the customer asks, and `change_plan` returns `None`. At `period_end` the renewal moves them to the cheaper plan and bills its full price. This also applies to a downgrade combined with a switch to annual.

2. Don't compare prorated amounts. Use the plans' monthly list price (`monthly_price`), whichever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade. Switching interval on the same plan is neither.

3. Calendar days are right, but the details matter. The fraction is remaining days divided by days in the period. Remaining days run from the change date, inclusive, to the period end, exclusive. Days in the period are the real calendar days: 28-31 for a month, 365 or 366 for a year. Rounding is half-up to the cent, applied to each line separately.

4. No negative invoices and no credit balance. Nothing is credited at the request, because downgrades and interval switches wait for the period end. An upgrade invoice has exactly two lines: a negative credit for the unused part of the current plan, and a positive charge for the same remaining days on the new plan. Both use the prices of the interval the customer is currently on. Each line is computed exactly as price × remaining days ÷ period days and rounded half-up on its own. The total is the sum of the two rounded lines. For example, Pro → Premium on Mar 11 in a Mar 1-Apr 1 period is 21/31 of the period left. That gives lines of -20.32 and +50.81, total 30.49.

5. The billing period does not restart. Interval switches, monthly to annual or annual to monthly, wait for the period end. We never refund unused annual time. Nothing is billed at the request, and the renewal starts a period of the new interval at that interval's full price. For an upgrade made together with an interval switch, split it. The upgrade happens now as described above, prorated at the current interval's prices. The interval switch happens at the period end. When the interval stays the same, an upgrade keeps the same period start and end. The next renewal bills the new plan at its full price.

### [spec] agent

That settles the core behaviour. Your example checks out: a $30 Pro and a $75 Premium give 30 × 21/31 = 20.3226 → 20.32 and 75 × 21/31 = 50.806 → 50.81.

Since downgrades and interval switches now wait for the period end, a subscription can carry a **pending change**. Most of the remaining questions are about that, plus a few edge cases. My recommendations are in **bold** again.

**6. Changes during a trial.** Nothing has been paid yet, so there is nothing to prorate. **Apply any change (plan and/or interval) immediately, bill nothing, return `None`, and leave the trial end date alone. The first paid period then bills the new plan and interval at full price.** Or should trials follow the same upgrade-now / downgrade-later rules?

**7. Repeated requests while a change is pending:**
- **A new request replaces any pending change. There is only ever one pending change.**
- **If the customer upgrades while a downgrade is pending, the upgrade happens now and the pending downgrade is dropped.** If the upgrade request keeps the interval (`new_interval=None`), does a pending interval switch survive? **I'd say yes: `None` means "don't touch the interval", and a pending switch counts as part of the interval.**
- **If the customer asks for their current plan and current interval while something is pending, the pending change is cancelled and the call returns `None`.**
- **If they ask for their current plan and interval with nothing pending, raise `InvalidPlanChange`.**

**8. Same `monthly_price`, different plan (a sideways move).** It's neither an upgrade nor a downgrade. **Treat it like a downgrade: switch at the period end, bill nothing now.** Or should it be rejected?

**9. Upgrades that come out negative.** You compare by `monthly_price` but prorate with the current interval's prices. Take an annual customer moving from plan A (monthly 10, annual 120) to plan B (monthly 12, annual 100). By `monthly_price` that's an upgrade, but the invoice would be −120f + 100f < 0, which is a negative invoice. Do you want to:
- (a) **raise `InvalidPlanChange`**,
- (b) defer it like a downgrade, or
- (c) allow it?

**10. Retired plans:**
- If the target plan is retired, **raise `PlanNotAvailable`**, whether it's an upgrade or a deferred downgrade.
- If the target is retired between the request and the renewal, **the pending change still applies**, because the customer bought it while it was on sale. Agree?
- A customer on a retired plan who only wants to switch interval: **allowed**. They stay on their plan and aren't buying a new one. Agree?

**11. Overdue subscription** (`period_end <= today` because `renew_due` hasn't run yet): **raise `InvalidPlanChange`** rather than quietly catching up the renewals. Or should `change_plan` run the overdue renewals first?

**12. Other existing errors, just to confirm:** unknown subscription → `SubscriptionNotFound`; unknown plan → `PlanNotFound`; cancelled subscription → `SubscriptionNotActive`. **Cancelling discards any pending change.**

**13. Upgrade invoice details:** `issued_on` is today. Do the line descriptions need specific wording, or is it enough that each line names its plan and date range? Also, upgrading from a free plan gives a −0.00 credit line. **Keep exactly two lines anyway.**

### [spec] user

6. Agree, with one addition. Any change during a trial applies immediately: the plan and interval switch now, `change_plan` returns `None`, and no invoice is recorded. The trial end date does not move. At trial end the customer is billed the full price of the plan and interval they are on by then.

7. Replace-only is right: each request states the full target (plan + interval) and replaces whatever was scheduled. Two of your recommendations contradict that.
- An upgrade that applies now also discards anything scheduled. The only exception is when the same request itself schedules an interval switch, as in the split upgrade-plus-switch case. So a pending interval switch does not survive an upgrade that passes `new_interval=None`.
- Until the period end the customer is still on the current plan. An upgrade requested while a downgrade is scheduled is prorated from the current plan. Example: on Pro, Basic scheduled on Mar 5, then Premium requested on Mar 11 gives an invoice of 30.49.
- Asking for the current plan and interval cancels whatever is scheduled. It returns `None`, nothing is billed, and the renewal continues on the current plan. With nothing scheduled, raise `InvalidPlanChange`. Agree.

8. I don't mind. Any sensible choice is fine.

9. I don't have a rule for that, so I'll accept your recommendation.

10. Agree on all three:
- Moving to a retired plan raises `PlanNotAvailable`.
- Customers on a retired plan may move off it like anyone else.
- I don't mind about switching interval while staying on a retired plan.
I haven't decided anything about a target that is retired between the request and the renewal, so use your recommendation.

11. I don't mind. Use your recommendation.

12. Agree. Canceled subscriptions raise `SubscriptionNotActive`, an unknown plan raises `PlanNotFound`, and an unknown subscription uses the existing error. Any rejected request changes nothing: no invoice is recorded and the subscription is untouched. I haven't decided what cancelling does to a pending change, so use your recommendation.

13. I don't mind about the wording. Keep exactly two lines on an upgrade invoice, issued on the change date.

### [spec] agent

SPEC.md is written at the repo root. It isn't committed, since you didn't ask for that.

It has the fixed interface copied verbatim, numbered behaviour rules, about 30 checkable acceptance criteria and a non-goals list. I worked out every number by hand because the sandbox wouldn't let me run inline Python. Your Mar 11 example comes out at 30.49 with per-line rounding and 30.48 if only the total were rounded, so it pins that rule down. Rounding half-up by size is checked with a 10.01 plan, where 15/30 of the price is 5.005 and rounds to a −5.01 credit. The 365- versus 366-day year is checked with annual periods in 2026–27 and 2027–28.

**Where you didn't mind or hadn't decided, the spec says:**
- **Same `monthly_price`, different plan:** the move waits for the period end, like a downgrade.
- **Upgrade that would produce a negative invoice:** if the target plan costs more by `monthly_price` but less at the customer's current interval, `change_plan` raises `InvalidPlanChange`. If the two prices at that interval are equal, the upgrade still goes ahead with a 0.00 invoice.
- **Overdue subscription** (`period_end <= today` before `renew_due` has run): raises `InvalidPlanChange`. `change_plan` does not catch up renewals itself.
- **Target plan retired after the request:** the scheduled change still applies at renewal.
- **Cancelling** discards any scheduled change.
- **Retired plans:** a customer on one can switch interval and stay on it.

**Additions that follow from your answers:**
- `PlanNotAvailable` only applies when the target is a different plan from the current one. Otherwise a customer on a retired plan couldn't undo a scheduled interval switch by asking for their current plan and interval.
- If several renewals are caught up at once, a scheduled change applies at the first one.
- `InvalidPlanChange` is exported from `billing`, like the other errors.
- Non-goal: no public way to look up a scheduled change.

Say so if any of these should go the other way.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

`change_plan` is built and the full test suite passes: the 20 existing tests plus 42 new ones.

```
$ python3 -m pytest -q
..............................................................           [100%]
62 passed in 0.02s
```

**What changed**
- **`src/billing/errors.py`, `__init__.py`**: added `InvalidPlanChange(BillingError)` and exported it from `billing`.
- **`src/billing/subscriptions.py`**: a pending change is stored on the subscription as a new optional `scheduled_change` field (a plan plus an interval). Because it lives on the `Subscription` record, the database-backed store only needs to save one more field and nothing touches store internals.
- **`src/billing/money.py`**: new `prorate()`. It does the day-based maths in whole-cent integers, so there are no Decimal precision issues, and rounds half-up by size (−5.005 becomes −5.01).
- **`src/billing/service.py`**:
  - `change_plan` checks in this order: subscription exists and isn't canceled, plan exists, renewal isn't overdue, target plan isn't retired, then same plan and same interval (cancel the scheduled change, or raise if nothing is scheduled).
  - During a trial, any change applies straight away. Otherwise downgrades and lateral moves are scheduled, and upgrades go through the prorated two-line invoice. An interval switch on an upgrade is scheduled for the period end.
  - Every check runs before anything is saved, so a rejected request changes nothing.
  - `_renew` applies a scheduled change and then clears it; it still works if that plan was retired in the meantime. `cancel` also clears it.
- **`tests/test_change_plan.py`**: covers every acceptance criterion with the spec's catalog and exact amounts. That includes −20.32/+50.81, the 365- and 366-day years, −5.01/+15.00, the −0.00 line from Free, the overdue catch-up, retired-plan customers, the A→B case on both intervals and the trial cases. Each rejection test also checks that the subscription, its scheduled change and its invoices are unchanged.
- **`README.md`**: one line describing plan changes.

**Two choices where the spec is unclear**
1. **Rule 16 doesn't apply during trials.** It exists to stop a negative invoice, and trial changes never produce one. So a trialing annual customer on A can switch to B immediately. Rule 15 (retired plans) does apply during trials, because the spec says so explicitly.
2. **Rule 17 (overdue renewal) applies during trials too.** If a trial has ended but `renew_due` hasn't run yet, the request is rejected.

Nothing is committed; the changes are in the working tree.
