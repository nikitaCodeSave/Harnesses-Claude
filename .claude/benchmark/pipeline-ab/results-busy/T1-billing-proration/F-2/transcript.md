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

I've read the package. Some facts that shape my questions:

- A renewal is billed on `period_end` and dated on the new period's start. There's no customer credit balance anywhere.
- `LineItem` accepts negative amounts, so an invoice total can go negative, though nothing creates one today.
- Retired plans keep renewing, and subscriptions can be `TRIALING`.

First round covers the policy decisions. Each has my suggested default, so you can just reply "agree" to any of them.

**1. Proration basis.** I'd prorate by day. The unused part of the current period is `period_end − today` days out of `period_end − period_start`. The customer gets credit for the unused share of what they paid and is charged the new plan's price for the same share. Cents round half up, line by line. The change takes effect today. OK, or do you want something coarser, like whole months?

**2. Upgrade, same interval.** Should the period dates stay the same, with an invoice issued today that has a credit line (old plan, unused days, negative) and a charge line (new plan, same days)? Or one net "difference" line?

**3. Downgrade, same interval.** This decides the most. Options:
   - (a) Takes effect immediately. The credit is bigger than the charge, so the invoice total is negative. That needs a decision on where the money goes (see Q4).
   - (b) Scheduled for the end of the period. Nothing is billed now (`None`), and the next renewal bills the new plan. This needs a "pending change" stored on the subscription.

   The phrase "or `None` when nothing is billed at the moment of the request" in your interface hints at (b). Is that what you meant?

**4. Money owed back to the customer.** This covers any case where credit exceeds charge, such as a downgrade if it applies immediately, or annual → monthly. Should we issue a negative-total invoice (a credit note recorded like any other invoice)? Carry a credit balance onto the next renewal? Or forbid it and schedule the change instead? There's no credit-balance concept today, so carrying a balance would be new scope.

**5. Interval switches.**
   - Monthly → annual: I'd start a new annual period today, credit the unused monthly days, and charge the full annual price.
   - Annual → monthly: crediting the unused annual time immediately gives a large negative invoice. I'd schedule it for the end of the annual period instead, which returns `None`. Agree?

**6. How we tell an upgrade from a downgrade** when the interval changes or prices are close. I'd compare the price per month, so annual price ÷ 12 against the monthly price. Or is it simpler: any change that makes the customer owe money now is immediate, and everything else is scheduled?

Once I have these answers I'll ask a shorter second round on edge cases: trials, retired plans, a renewal that's due but hasn't run, repeated changes in one period, free plans, and which error applies to which case.

### [spec] user

1. Agree on by-day proration, but days are real calendar days in the current period (28-31 for a month, 365/366 for a year). Remaining days count from the change date inclusive up to period end exclusive. Round half-up to cents on each line separately.

2. Same period dates, no change to start or end. Invoice dated on the change date with exactly two lines: a negative credit for the unused part of the old plan and a positive charge for the same days on the new plan, both at the prices of the interval the customer is currently on. Compute each line exactly (price x remaining days / period days, no rounded daily rate) and round each line on its own. The total is the sum of the two rounded lines, not a rounded net difference. The next renewal on the usual date bills the new plan at full price.

3. (b). Downgrades wait for the end of the period. Nothing is billed, refunded or credited at the request, and change_plan returns None. The renewal moves them to the cheaper plan and bills its full price. A pending change stored on the subscription is fine.

4. No negative invoices, no credit balance, nothing owed back. Anything that would give money back is scheduled for the period end instead.

5. Interval switches both ways wait for the end of the period, returning None. We never refund unused annual time. The renewal starts a period of the new interval and bills that interval's full price. So monthly -> annual is not immediate either. If an upgrade comes together with an interval switch, split it: the upgrade happens now, prorated at the current interval's prices, and the interval switch happens at the period end.

6. Not by price per month or by who owes money. Upgrade vs downgrade is decided by comparing the plans' monthly list prices only (monthly_price), regardless of the interval. A more expensive plan is an upgrade, a cheaper one a downgrade. Switching interval on the same plan is neither.

### [spec] agent

Clear. Second round covers the edge cases. Again, each has a suggested default.

**7. Trials.** Nothing has been paid during a trial, so there's nothing to prorate. I'd apply any plan or interval change immediately, upgrade or downgrade, and return `None`. The trial end date stays the same, and the first paid period bills the new plan and interval at full price. Agree?

**8. Several requests in one period.**
   - (a) A new request replaces any pending change. The latest request wins.
   - (b) Upgrading while a downgrade is pending: the upgrade is prorated against the *current* plan, and the pending downgrade is dropped.
   - (c) `new_interval=None` means "keep the current interval". If an interval switch is pending and the customer then upgrades with `None`, I'd treat `None` as "no opinion" and keep the pending switch. An explicit interval equal to the current one would cancel it. Or should `None` always mean "stay on the current interval" and drop the pending switch?
   - (d) Asking for the current plan and interval while a change is pending cancels the pending change and returns `None`. With nothing pending, the same request raises `InvalidPlanChange`.
   - (e) Several upgrades in one period: each is prorated from the plan the customer is on at that moment, over the days left. That follows from your rules; I'll just state it.

**9. Same monthly price, different plan.** It's neither an upgrade nor a downgrade. I'd schedule it for the end of the period, return `None`, and bill nothing now. Agree?

**10. Retired plans.**
   - Target plan retired: `PlanNotAvailable`.
   - Customer on a retired plan switching interval on that same plan: I'd allow it, since it's the plan they already have and not a new sale. Allow or reject?
   - A scheduled downgrade whose target is retired before the renewal: I'd still apply it, because it was valid when requested.

**11. Renewal due but not run** (`today >= period_end`, `renew_due` not called yet). I'd raise `InvalidPlanChange` and leave it to the caller to run renewals first, rather than having `change_plan` renew implicitly.

**12. Other errors.** I'd reuse what exists: unknown subscription → `SubscriptionNotFound`, canceled → `SubscriptionNotActive`, unknown plan → `PlanNotFound`. A failed request changes nothing (no invoice, no state change). Cancelling a subscription drops any pending change. Agree?

**13. Upgrading from a free plan** (monthly price 0). The credit line would be 0.00. Keep exactly two lines, including the 0.00 credit? I'd say yes, for consistency.

**14. Pending change visibility.** Should callers be able to see the pending change on `Subscription`, so support can show "switches to Basic on Nov 30"? If so, should the spec fix the field names, or leave them to the implementer?

### [spec] user

7. Agree. Any change during a trial (up, down, interval) applies immediately in full and change_plan returns None, with no invoice. The trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they are on by then.

8. (a) Agree, the latest request replaces whatever was scheduled. Each request states the full target (plan + interval). (b) Agree: the upgrade is prorated from the current plan, because a scheduled change hasn't happened yet. Example: on Pro, Basic scheduled on Mar 5, Premium requested on Mar 11 gives an invoice of 30.49 (from Pro). (c) Not your suggestion. None always means "keep the current interval", so the request's full target is the current interval and anything previously scheduled is replaced. An upgrade that applies now also discards anything scheduled, unless the same request itself schedules an interval switch. (d) Agree. (e) Agree.

9. I don't mind, use your recommendation.

10. Target plan retired gives PlanNotAvailable. Customers on a retired plan may move off it like anyone else. Switching interval while staying on a retired plan: I don't mind, your choice. For a scheduled downgrade whose target is retired later, I don't mind, your call.

11. I don't mind, your recommendation is fine.

12. Agree on the errors: canceled gives SubscriptionNotActive, unknown plan gives PlanNotFound, and unknown subscription uses the existing error. A rejected request changes nothing: no invoice, subscription untouched. I don't mind about dropping a pending change on cancel.

13. I don't mind, your choice. Note the upgrade invoice should still follow the two-line rule in general.

14. I don't mind, how it's stored and exposed is up to you.

### [spec] agent

I've written the spec to `SPEC.md`. It's uncommitted, and I haven't touched any code.

It has the interface copied verbatim from your request, a rules table for active and trialing subscriptions, 29 numbered acceptance criteria, worked examples and non-goals.

**Two things to check:**

- **The 30.49 example.** The test fixtures have no Premium plan, so I worked backwards. If Premium costs 75.00/month and the period runs 2026-03-01 → 2026-04-01 (21 of 31 days left on Mar 11), the lines are −20.32 and +50.81, which sum to 30.49. Rounding the net difference instead would give 30.48, so the example also shows the per-line rounding rule. If you had different figures in mind, tell me and I'll fix that row. I calculated all the examples with the exact formula you gave.
- **My calls where you said "don't mind".** They're listed in their own section of the spec:
  - A change to a plan with the same monthly price is scheduled for the period end.
  - Customers on a retired plan may switch interval on it.
  - A scheduled downgrade still applies if its target plan is retired before the renewal.
  - A request made after the period has ended raises `InvalidPlanChange`; the caller runs renewals first.
  - Cancelling drops any scheduled change.
  - An upgrade from a free plan keeps a 0.00 credit line.

**Two smaller additions:**

- `InvalidPlanChange` is also exported from the `billing` package, like the other errors.
- `subscribe`, `renew_due` and `cancel` must behave exactly as before, and the existing tests must pass unchanged.

How the scheduled change is stored and exposed is left to the implementer, and the spec lists it as a non-goal.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

`BillingService.change_plan` is built as SPEC.md describes, and the full test suite passes.

```
$ python3 -m pytest -q
........................................................................ [ 94%]
....                                                                     [100%]
76 passed in 0.05s
```

That's the 20 existing tests, unchanged, plus 56 new ones in `tests/test_change_plan.py`. Every acceptance criterion (1–29) and all four worked examples have at least one test. The first example's total is checked as 30.49, not the 30.48 a rounded net difference would give.

**What changed**
- **`errors.py` / `__init__.py`:** added `InvalidPlanChange(BillingError)` and exported it from the package. I also exported a new `ScheduledChange` type.
- **`subscriptions.py`:** a subscription can now hold one scheduled change: a frozen `ScheduledChange(plan_code, interval)` stored in a new `scheduled_change` field, which defaults to `None`.
- **`service.py`:**
  - **`change_plan`** checks everything before saving anything, so a rejected request leaves the subscription and invoices exactly as they were. During a trial, changes apply immediately and nothing is billed.
  - **Upgrades** switch plan now and issue an invoice with two lines (credit and charge), each rounded on its own at the current interval's prices. An interval switch in the same request waits for the next renewal.
  - **Everything else** (downgrades, equal-price plan changes, interval switches) is scheduled for the next renewal.
  - **Renewals** apply a scheduled change and then clear it, so when several missed periods are caught up it only affects the first. Cancelling discards a scheduled change.
  - **Rounding:** prorated amounts are calculated in whole cents with integer arithmetic, so half-cent cases round up exactly (a February test covers this).

**One case the spec doesn't spell out:** a plan can have a higher monthly price but a lower annual price. Upgrading to it from an annual subscription would produce a negative invoice. Following criterion 15 ("any change that would give money back is scheduled"), I schedule that change for the period end instead, and a test covers it. If the prices are equal at the current interval, it is still treated as an immediate upgrade with a 0.00 invoice.

Nothing is committed. Running the tests also leaves untracked `__pycache__/` folders, since the repo has no `.gitignore`.
