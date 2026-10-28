### [spec+build] operator

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

Interview me until you could write the spec, then write it to SPEC.md. The spec says what and why (acceptance criteria as checkable statements, non-goals), not how. Copy any interface my request fixes (module paths, signatures, error classes) into it verbatim. Then build it. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [spec+build] agent

I've read the whole package (~700 lines): `subscribe`, `renew_due`, `cancel`, frozen dataclasses, whole-cent `Decimal` money, half-open periods, and retired plans that can't be sold. The test suite is 20 tests. Before I write the spec I need your decisions on these. Each has my recommendation, so you can answer "agree" or just correct the ones you disagree with.

**1. When changes take effect**
- **Upgrades** (the new plan costs more per day): take effect immediately. The customer gets credit for the unused part of the current period and is charged for the new plan for the same remaining days. Both go on one invoice issued today.
- **Downgrades** (cheaper per day): I recommend **scheduling them for the end of the current period**. Nothing is billed now, so the call returns `None`. The next renewal then bills the new plan and interval. The package has no credit balance and no refunds today, so an immediate downgrade would produce a negative invoice. Do you want that instead (immediate downgrade, negative invoice treated as a refund)?

**2. Interval switches**
- **Monthly→annual:** I recommend treating this as an upgrade. It happens now, and a **new annual period starts today**. The customer is credited for the unused monthly days and charged the full annual price.
- **Annual→monthly:** the credit for the unused annual days would usually be larger than one month's charge. I recommend handling it like a downgrade: it takes effect at the end of the annual period. OK?
- Does "upgrade vs downgrade" mean comparing the price per day (price for the period ÷ days in it)? Or should it be decided by plan price alone, with interval changes handled by their own rule?

**3. How proration is calculated**
- I recommend counting by days: amount = price × (days left in the current period ÷ total days in the period). Days left run from today to `period_end`.
- Each line is rounded to the cent (half up). The credit and the charge are separate lines on the invoice.

**4. Edge cases.** Here's what I'd do:
- **Same plan and same interval:** raise `InvalidPlanChange`.
- **Target plan retired:** raise `PlanNotAvailable`. There's one exception: switching interval while staying on your own retired plan. Should that be allowed or rejected?
- **Canceled subscription:** raise `SubscriptionNotActive`. **Unknown subscription or plan:** raise `SubscriptionNotFound` / `PlanNotFound`.
- **Trialing subscription:** switch the plan and interval right away, bill nothing and return `None`. The trial end date stays the same.
- **Renewal is due but `renew_due` hasn't run yet** (today ≥ `period_end`): raise `InvalidPlanChange` so we never prorate a period that's already over. The alternative is to run the renewal first and then apply the change.
- **A second change while a downgrade is pending:** the new request replaces the pending one. Asking to go back to the current plan and interval clears it and returns `None`. Cancelling a subscription also drops any pending change.

**5. Out of scope.** I plan to leave out credit balances, refunds or negative invoices, plan changes on a future date, quantities or seats, and taxes. Correct?

### [spec+build] user

1. Upgrades: agree, immediate, one invoice today. Downgrades: agree, they wait for the period end. Nothing billed, returns None, and the renewal moves them to the cheaper plan at its full price. No negative invoices.

2. Don't use price per day, and don't treat interval switches as upgrades. Upgrade vs downgrade is decided by the plans' monthly list price only, whatever interval the customer is on or moving to. A more expensive plan is an upgrade, a cheaper one a downgrade. Switching interval on the same plan is neither.
- Any interval switch (monthly->annual or annual->monthly) waits for the period end. Nothing is billed at the request, and the renewal starts a period of the new interval at its full price. We never refund unused annual time. So monthly->annual is NOT immediate with a new annual period.
- If an upgrade comes together with an interval switch, split it. The upgrade happens now, prorated at the current interval's prices. The interval switch happens at the period end.
- A downgrade combined with an annual switch also waits for the period end.

3. Days: agree, but be precise. Remaining days count from the change date inclusive to the period end exclusive. The period length is real calendar days (28-31 for a month, 365/366 for a year). The upgrade invoice has exactly two lines, a credit for the current plan and a charge for the new plan for the remaining days, both at the current interval's prices. Compute each line exactly as price x remaining / period days, with no rounded daily rate in between. Round each line half-up to the cent on its own. The total is the sum of the two rounded lines. Example: Pro->Premium on Mar 11 in a Mar 1-Apr 1 period gives -20.32 and +50.81, total 30.49.

4.
- Same plan and interval: if something is scheduled, this cancels it and returns None with nothing billed. If nothing is scheduled, raise InvalidPlanChange.
- Retired target plan: PlanNotAvailable. Customers on a retired plan can move off it like anyone else. Switching interval while staying on a retired plan: I don't mind.
- Canceled subscription: SubscriptionNotActive. Unknown plan: PlanNotFound. Unknown subscription: use the existing error.
- Trial: agree for any change, up, down or interval. It applies immediately in full, returns None, no invoice, and the trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they are on by then.
- Renewal due but not yet run: I don't mind, your choice.
- Pending change: agree, each request states the full target and replaces whatever was scheduled. An upgrade applied now also discards the pending change, unless that same request schedules an interval switch. An upgrade while a downgrade is pending is prorated from the current plan, not the scheduled one. On Pro with Basic scheduled, then Premium requested on Mar 11, the invoice is 30.49, from Pro. Cancelling dropping the pending change: I don't mind.
- Any rejected request changes nothing: no invoice, subscription untouched.

5. Out of scope: agree.

### [spec+build] agent

That answers almost everything. Your rules leave two cases unclear, and both affect what gets billed:

**A. Annual customers whose plans' annual prices don't follow their monthly prices.** You decide upgrade vs downgrade by monthly price, but an upgrade is prorated at the current interval's prices. Take an annual customer moving from plan A (10/month, 100/year) to plan B (12/month, 90/year). That counts as an upgrade, but the credit is larger than the charge, so the invoice comes out negative. You've ruled out negative invoices. My recommendation: keep the classification by monthly price, and if an upgrade's prorated total would come out below zero, raise `InvalidPlanChange` and change nothing. The alternatives are to schedule it for the period end like a downgrade, or to issue the invoice anyway. Which do you want?

**B. Moving to a different plan with the same monthly price.** It is neither more expensive nor cheaper. My recommendation is to treat it like a downgrade: schedule it for the period end, bill nothing and return `None`.

These are the choices I've made where you said you don't mind:
- **Renewal due but not yet run** (today ≥ `period_end`): raise `InvalidPlanChange`.
- **Cancelling** drops any pending change.
- **Same plan, new interval:** this is allowed even if the plan is retired.
- **Scheduled change to a plan retired before the period ends:** it still applies at renewal. The plan was valid when the change was requested, and retired plans keep renewing anyway.
- **Upgrade that rounds to a 0.00 total** (for example a one-cent price difference with one day left): still issue the two-line invoice. It records the change and the result is never negative.

### [spec+build] user

A: That case isn't something I've thought about, so I don't mind. Go with your recommendation: classify by monthly price, and reject with InvalidPlanChange if the prorated total would be negative, changing nothing.

B: Same monthly price is fine to treat as you suggest.

Your other choices are fine too.

### [spec+build] agent

Plan changes are in. I wrote the spec to `SPEC.md`, built `change_plan` in `src/billing/service.py`, and the full test suite passes.

```
$ python3 -m pytest -q
........................................................                 [100%]
56 passed in 0.02s
```

That's the 20 existing tests plus 36 new ones in `tests/test_change_plan.py`. Each new test is labelled with the spec criterion it checks, and all 23 criteria are covered. To confirm the tests would catch real mistakes, I broke the logic in seven places one at a time, for example counting remaining days without the change date. The tests caught every one, and the code is back to its original state.

**How it behaves:**
- **Upgrades** (higher monthly list price) happen now. The invoice has two lines: a credit for the old plan and a charge for the new one, each worked out exactly and rounded separately. Your example gives −20.32 and +50.81, total 30.49. If rounding the difference had been used instead, the total would be 30.48; a test checks this.
- **Downgrades, same-price plan moves and interval switches** bill nothing and return `None`. They are saved on the subscription and applied at the next renewal, at the new plan's full price.
- **An upgrade combined with an interval switch** is split: the plan changes now at the current interval's prices, and the interval changes at renewal.
- **During a trial**, any change applies straight away, bills nothing, and the trial end date stays the same.
- **Rejected requests** leave the subscription and the invoices exactly as they were. This is tested for each type of rejection.

**What else changed:**
- `InvalidPlanChange(BillingError)` is in `src/billing/errors.py` and exported from the package.
- To remember a change waiting for renewal, `Subscription` has a new optional field, `scheduled_change: ScheduledChange | None` (a plan code and an interval). The production database store will need a column or table for it; its methods stay the same.
- `renew_due` applies the scheduled change and then clears it, and `cancel` drops it.
- I added a Premium plan (75.00 a month, 750.00 a year) to the shared test setup so your example can be checked as written. The existing tests are unaffected.
- The README's file list now mentions `change_plan`.

Everything is uncommitted on `main`.
