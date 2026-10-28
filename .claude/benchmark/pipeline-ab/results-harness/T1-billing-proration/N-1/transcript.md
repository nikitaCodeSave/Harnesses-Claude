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

I've read the whole package (service, store, periods, tests). There's no `GLOSSARY.md` or `docs/adr/` yet, so I'll create both as part of this work. The suite passes (20 tests).

Before I write the spec, I need some decisions from you. Each one has my recommendation, so you can answer "all recommended" or override by number.

**1. When do downgrades take effect?**
- **(a) Recommended:** at the end of the current period. Nothing is billed now, so the call returns `None`. The subscription stores a *scheduled change* that `renew_due` applies, and the renewal invoice uses the new plan and interval. This avoids negative invoices and refunds, which the package doesn't have today (`cancel` gives no refund either).
- (b) Immediately, with a credit, which means issuing an invoice with a negative total.

**2. What counts as an upgrade vs a downgrade?** This matters when the interval also changes.
**Recommended:** price the change as if it happened today, as credit for unused days plus the new charge.
- Net > 0: it's an upgrade and applies now.
- Net < 0: it's a downgrade and is scheduled for period end.
- Net = 0 (same price, different plan): applies now, returns `None`.

Under this rule, basic monthly → pro monthly applies now. Pro → basic is scheduled. Any monthly → annual switch applies now. Annual → monthly is normally scheduled.

**3. How is an immediate change priced?** Recommended:
- Same interval: the period dates stay the same. The invoice has two lines:
  - a credit of −(old price × remaining days ÷ period days)
  - a charge of +(new price × remaining days ÷ period days)
- Interval switch: a new period of the new interval starts today. The invoice has the same credit line plus the full price of the new period.
- Days are calendar days: remaining = `period_end − today`. Each line is rounded half-up to cents on its own. The invoice is dated today.

**4. Scheduled changes:** a later `change_plan` replaces a pending downgrade. An upgrade clears it. Requesting the current plan and interval clears it and returns `None`. `cancel` makes it irrelevant. Recommended: all of the above. If the target plan is retired after the change was scheduled, the change still applies at renewal, because the sale already happened.

**5. During a free trial:** recommended: swap the plan and/or interval right away, bill nothing, keep the trial end date, return `None`. The first paid period then uses the new plan and interval.

**6. Rejections:**
- Canceled subscription → `SubscriptionNotActive`
- Unknown plan → `PlanNotFound`
- Retired target plan → `PlanNotAvailable`. This includes changing only the interval while staying on a retired plan; I'm treating that as a new sale. Do you agree?
- Same plan and interval with nothing pending → `InvalidPlanChange`
- Renewal overdue (`period_end <= today`, `renew_due` not run yet) → recommended `InvalidPlanChange`, rather than silently catching up first.

**7. Scope:** this fits one session. The work: the spec in `specs/plan-change.md`, an ADR for decisions 1–2, glossary terms, tests written first, then the implementation. Not in scope: account credit balances, refunds, customer-specific or discounted prices (credits use the old plan's list price), and changing the billing date of an existing period.

What should I change, if anything?

### [build] user

Several of your recommendations contradict how we want this to work, so here are my answers by number.

1. Downgrades take effect at the end of the period. Nothing is billed, refunded or credited at the request, and `change_plan` returns `None`. I agree with (a). The renewal then moves the customer to the cheaper plan and bills its full price.

2. Your net-price rule is wrong. Upgrade or downgrade is decided only by comparing the plans' monthly list prices, whatever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade. Switching interval on the same plan is neither.

3. Your pricing is wrong in two ways.
   - An interval switch never starts a new period now, and we never refund unused annual time. Monthly -> annual and annual -> monthly both wait for the period end. The renewal then starts a period of the new interval and bills that interval's full price.
   - An upgrade that comes together with an interval switch is split in two. The upgrade happens now, prorated at the prices of the current interval. The interval switch happens at the period end.
   - An upgrade applies immediately and the period does not move: same start, same end. The next renewal bills the new plan at its full price.
   - Proration is by calendar days in the period. The fraction is remaining days / days in the period. Remaining days count from the change date inclusive to the period end exclusive.
   - The upgrade invoice is issued on the change date and has exactly two lines: a negative credit for the unused part of the current plan and a positive charge for the same days on the new plan.
   - Each line is price x remaining days / period days, computed exactly, then rounded half-up on its own. The total is the sum of the two rounded lines.
   - Example: Pro -> Premium on Mar 11 in a Mar 1-Apr 1 period gives -20.32 and +50.81, total 30.49.

4. Only one change can be scheduled at a time.
   - Each request states the full target (plan and interval) and replaces whatever was scheduled before.
   - An upgrade that applies now also discards anything scheduled, unless that same request schedules an interval switch.
   - A scheduled change has not happened yet. An upgrade requested while a downgrade is pending is prorated from the current plan, not the scheduled one.
   - Requesting the current plan and interval cancels anything scheduled and returns `None`. If nothing is scheduled, raise `InvalidPlanChange`.
   - I have no view on what happens to a scheduled change when its target plan is later retired.

5. Free trials: there is no proration at all. Any change during a trial applies immediately in full, whether it's an upgrade, a downgrade or an interval change. It returns `None` and no invoice is issued. The trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they're on by then.

6. Rejections:
   - A canceled subscription raises `SubscriptionNotActive`.
   - An unknown plan raises `PlanNotFound`.
   - A retired target plan raises `PlanNotAvailable`. Customers sitting on a retired plan can move off it like anyone else.
   - Same plan and interval with nothing pending raises `InvalidPlanChange`.
   - I don't mind how you handle an interval-only switch while staying on a retired plan, or a request made after `period_end` before the renewal job has run.
   - A rejected request changes nothing. No invoice is recorded and the subscription is untouched.

7. Scope is fine as you describe it. One session works for me, with the spec, the ADR, glossary terms and tests.

### [build] agent

`BillingService.change_plan` is in place and works the way you described.

```
$ python3 -m pytest -q
.....................................................                    [100%]
53 passed in 0.04s
```

That's 20 existing tests plus 33 new ones. I wrote the new tests first and ran them against stubs, where all 30 initial ones failed. The amounts I worked out by hand all came out right, including your example: −20.32 + 50.81 = 30.49.

**How it behaves**
- **Upgrades** apply now and the period doesn't move. The invoice has the two lines, priced at the current interval's prices.
- **Downgrades and interval switches** are saved as a scheduled change on the subscription and return `None`. `renew_due` applies the scheduled change: it starts the new plan and interval and bills the full price.
- **Upgrade plus interval switch** is split: the upgrade now, the switch at the period end.
- **Trials** take any change immediately and bill nothing.
- **Rejected requests** change nothing.

**Where you had no view, I chose:**
- A different plan at the same monthly price is scheduled for the period end, so nothing is billed now.
- An interval-only switch while staying on a retired plan raises `PlanNotAvailable`.
- A request made after `period_end`, before the renewal job has run, raises `InvalidPlanChange`.
- A scheduled change still applies at renewal if its target plan was retired after it was scheduled.

Each of these has its own test.

**Decision for you:** your rules can produce a negative upgrade invoice. Upgrades are classified by monthly price but prorated at the current interval's prices. So a plan that costs more monthly but less annually, say 30/300 → 35/250, gives an annual customer an invoice of −50.00, and nothing in the package handles that. I followed the rules as given and recorded this in the ADR. Your options are to avoid that price shape in the plan catalogue or to change the rule.

**Reviews**
- A fresh agent checked the change against the spec and found no defects. It flagged two untested cases, and I added tests for both.
- `/code-review` led to one fix: `change_plan` now raises `TypeError` straight away if `new_interval` isn't an `Interval`. Before, a wrong value was stored and only failed inside `renew_due`, where it stopped renewal for every subscription.
- One review finding was wrong: the credit line on a free plan does not show as `-0.00`. My check for it passed before any fix, so I dropped it.
- I skipped the remaining review findings as cosmetic, including one about cancelling: `cancel` leaves the scheduled change on the subscription. It's never applied, but it still shows up.

**Docs added**
- `specs/plan-change.md`, with your interface copied verbatim
- `docs/adr/0001-plan-change-timing.md`
- `GLOSSARY.md`
- README updates

Nothing is committed. Compiled `__pycache__/*.pyc` files are tracked in git, so running the tests modified them; I'd leave them out of any commit and add them to `.gitignore`.
