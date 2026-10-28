### [build] operator

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

### [build] agent

I've read the whole package. There's no `GLOSSARY.md`, `docs/adr/`, or `specs/` yet, so I'll create them as part of this work. Per CLAUDE.md, this is a non-trivial change, so I need some decisions from you before I write the spec. Each question has my recommendation; you can answer "go with your defaults" or override any of them.

**Proration mechanics**

1. **Day basis.** I'd use the actual days in the current period. Credit = old price × days left ÷ days in period, and the new plan is charged with the same fraction. Both lines go on one invoice issued today, each rounded half-up to cents. Monthly periods run 28–31 days and annual ones 365 or 366, so for example Jan 15 → Feb 15 is 31 days. *Alternative:* a fixed 30/360-day basis.
2. **Credit amount.** I'd base it on the old plan's list price. Prices can't change once a plan is in the store, so this matches what the customer paid. After a second change in the same period, the credit uses the plan they're on at that point. That keeps repeated changes consistent, give or take a cent of rounding.

**Downgrades** (this is the main fork)

3. When a change makes the net amount negative, what should happen?
   - **(a) Immediate:** apply the change now and issue an invoice with a negative total (a credit note). Simple, but nothing in the code tracks a customer balance, so whatever consumes invoices has to handle negatives.
   - **(b) Deferred (my recommendation):** record a pending change on the subscription that `renew_due` applies at `period_end`. Return `None` and charge nothing now. The customer keeps the higher plan for days they've already paid for, so nobody pays twice and nobody gets a refund. My guess is that's why the interface allows `None`. This adds a `pending_plan_code`/`pending_interval` to `Subscription`.
   - **(c) Credit carried forward:** apply the change now and deduct the credit from the next renewal invoice. This needs a stored credit balance.

**Switching interval**

4. **Monthly → annual.** I'd apply it now: credit the unused monthly days, start a new annual period today, and charge the full annual price of the new plan. The billing date moves to today.
5. **Annual → monthly.** With (b) I'd defer it to the end of the annual period, since crediting the unused annual days usually gives a large negative amount. Should every interval switch that nets negative go through the same rule as question 3?

**Edge cases**

6. **During a trial:** swap the plan and/or interval, leave the trial end date alone, bill nothing and return `None`. The first paid period uses the new plan and interval.
7. **Rejections:**
   - Canceled subscription → `SubscriptionNotActive`
   - Unknown plan → `PlanNotFound`
   - Retired plan as the target → `PlanNotAvailable`. This includes a customer on a retired plan who only wants to switch interval.
   - Same plan and same interval → `InvalidPlanChange`
   - Renewal overdue (`period_end <= today`, `renew_due` not yet run) → `InvalidPlanChange`. *Alternative:* catch the subscription up by renewing it first.
8. **Pending change already recorded (if 3b):** a new request replaces it. A request that matches the current plan and interval cancels it and returns `None`.
9. **Net zero (for example free → free):** change it, return `None`, issue no invoice.

**Process**

This fits in one session. I'll write `specs/plan-change.md` and an ADR for the proration and downgrade policy (it's hard to reverse, and later invoicing work will have to follow it), and add the glossary terms *proration*, *credit line* and *pending change*. Then I'll write failing tests first and implement against them.

### [build] user

Most of your defaults are fine. Questions 3, 4 and 5 need correcting, and 7 and 8 need a few additions.

1. Day basis: agreed, use real calendar days in the current period. Remaining days run from the change date, inclusive, to the period end, exclusive. Each line is price × remaining days ÷ period days, computed exactly. Round each line to cents half-up on its own, and the total is the sum of the two rounded lines. Don't round the net difference.

2. Credit amount: fine. Both lines use the prices of the interval the customer is currently on. After a second change, the credit is for the plan they're actually on.

3. Upgrade or downgrade: don't decide this from whether the net amount is negative. Compare the two plans' monthly list prices, whichever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade.
- Upgrade: it applies right away. The period start and end don't move. The invoice has exactly two lines, a negative credit and a positive charge, issued on the change date. The next renewal bills the new plan at its full price.
- Downgrade: your (b), deferred. Nothing is billed, refunded or credited at the request, and change_plan returns None. The renewal at period end moves them to the cheaper plan and bills its full price. This holds for any move to a cheaper plan, including one combined with a switch to annual.

4. Monthly → annual: don't apply it now. Interval switches wait for the period end, in both directions. Nothing is billed at the request. At the period end, a new period of the new interval starts and bills that interval's full price. We never refund unused annual time.
- Upgrade plus interval switch: split it. The upgrade happens now, prorated at the prices of the current interval. The interval switch happens at the period end.

5. Annual → monthly: deferred, same as above. Every interval switch is deferred, regardless of the net amount.

6. Trial: not quite. Any change during a trial applies immediately, whether it's an upgrade, a downgrade or an interval switch. change_plan returns None and no invoice is recorded. The trial end date doesn't move. At trial end, the customer is billed the full price of the plan and interval they are on by then.

7. Rejections:
- Canceled, unknown plan, retired target: correct as you have them. A customer on a retired plan can move off it like anyone else.
- Same plan and interval: this only raises InvalidPlanChange when nothing is scheduled. If a change is scheduled, the request cancels it and returns None.
- Overdue renewal and retired-plan interval switch: I don't mind, use your recommendation.
- Rejected requests change nothing, with no invoice and the subscription untouched.

8. Pending change:
- Each request states the full target and replaces whatever was scheduled. Matching the current plan and interval cancels it, as you said.
- An upgrade that applies now also discards anything scheduled, unless the same request schedules an interval switch.
- An upgrade while a downgrade is scheduled is prorated from the current plan, because the scheduled change hasn't happened yet. Example: on Pro, Basic is scheduled on Mar 5, then Premium is requested on Mar 11. The invoice is 30.49, from Pro.

9. Net zero: I don't mind, use your recommendation.

The process is fine: spec, ADR, glossary, then build.

### [build] agent

`BillingService.change_plan` is in place with the interface you specified, and the full suite passes:

```
$ python3 -m pytest -q
.....................................................                    [100%]
53 passed in 0.02s
```

I wrote the 26 new behaviour tests before the code and saw all of them fail first. I then ran `/code-review high`, which led to three more failing checks and their fixes.

**How it works** (`src/billing/service.py`):
- **Upgrades** apply immediately. The invoice is issued on the change date with exactly two lines, a credit and a charge. Each is price × remaining days ÷ days in period at the current interval's prices, worked out exactly and rounded half-up on its own. The period dates don't move. Your example gives 30.49 (−20.32 + 50.81), assuming Premium is 75/month and the Pro period runs Mar 1–Apr 1.
- **Downgrades and interval switches** are stored as a pending change on the subscription (a new `scheduled_change` field). `renew_due` applies it at the period end and bills the full price of the new plan and interval. An upgrade combined with an interval switch is split: the upgrade is billed now and the switch waits for the period end.
- **Trials**: any change applies at once, nothing is billed, and the trial end date stays the same.
- **Rejections** change nothing: canceled subscription, unknown plan, retired target plan, same plan and interval with nothing scheduled, or a renewal that's due but hasn't been billed yet.
- **Rounding helper**: `prorate()` in `money.py` works in whole cents, so the half-up rounding is exact.

**Two decisions I made after the review.** Both are recorded in the ADR; tell me if you want either changed:
- **Same-price plan changes wait for the period end.** These are moves to a different plan with the same monthly price, which you hadn't covered. I first applied them immediately without billing. But then a later upgrade would credit a price the customer never paid: for example, annual Team at 280 moved free to Pro at 300, then upgraded, gets a 300 credit.
- **An upgrade whose two rounded lines cancel out** still applies, but issues no invoice and returns `None`. That's the net-zero default you accepted.

**Decision needed:** because upgrades are classed by monthly price but prorated at the current interval's prices, a plan that costs more monthly but less annually produces a negative invoice for annual customers. For example, Pro (30/300) to a plan priced 31/250 on the first day of the period comes to −50.00. None of today's plans are priced like that, so I followed your rules as written and didn't add a test for it. It's listed as an open question in the spec. Possible answers are to ban that pricing, defer those changes like a downgrade, or allow the credit.

**Also new:**
- `specs/plan-change.md`, with your interface copied verbatim
- `docs/adr/0001-plan-change-proration-and-deferral.md`
- `GLOSSARY.md`
- `InvalidPlanChange` and `ScheduledChange` added to the package exports
- `README.md` updated
- Tests in `tests/test_plan_change.py`, plus new `prorate` tests in `tests/test_money_and_periods.py`

**Not done:**
- **Spec review:** your CLAUDE.md asks for a fresh session to review high-stakes changes against the spec, and this one changes billing invariants. I haven't started that session.
- **Commit:** nothing is committed.
- **Compiled `.pyc` files** are already tracked in the repo, so running the tests shows them as modified. That predates this change; I'd untrack them and add them to `.gitignore` as a separate change.
