### [build] operator

/harness:task Customers can't change plan right now: support has to cancel and resubscribe them by hand.
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

I've read the whole package (no GLOSSARY.md or ADRs yet). Before I write the spec I need a few decisions. Each question has my recommendation, so you can just say "go with your recommendations" and correct only the ones you disagree with.

**1. When a change takes effect: now, or at the end of the period?**
- **Recommendation:** a change that costs the customer more for the rest of the period takes effect **now** and is invoiced now. Any other change (cheaper, same price, annual→monthly) is **scheduled for the end of the current period** and returns `None`. The customer keeps what they already paid for, and we never need refunds or a credit balance, which the package doesn't have.
- Alternative: every change is immediate, and downgrades produce invoices with a negative total.

**2. Proration math for an immediate change on the same interval**
- **Recommendation:** the period dates stay the same. The invoice issued today has two lines:
  - a credit of `−old_price × remaining_days / period_days`
  - a charge of `+new_price × remaining_days / period_days`
- `remaining_days` = `period_end − today`, so today is billed on the new plan. `period_days` is the actual length of the current period.
- Each line is rounded to cents, half up.

**3. Monthly→annual (or any immediate interval switch)**
- **Recommendation:** credit the unused part of the current period (same formula as in 2). Charge the full new-interval price for a new period that starts today. The subscription's period becomes `[today, today + interval)`.
- Under rule 1, annual→monthly will almost always land in "scheduled".

**4. Scheduled changes**
- **Recommendation:** the subscription stores the pending plan and interval. `renew_due` applies them at the period boundary and bills the new plan and interval.
- A later `change_plan` replaces the pending change.
- Asking for the current plan and interval while a change is pending cancels the pending change and returns `None`.
- `cancel` discards the pending change.

**5. During a free trial**
- **Recommendation:** switch the plan and interval right away with no invoice (`None`). The trial end date doesn't change, and the first paid period is billed on the new plan.

**6. Which requests get rejected**
- **Recommendation:**
  - `SubscriptionNotFound` / `PlanNotFound`: unknown id or plan code.
  - `SubscriptionNotActive`: the subscription is canceled.
  - `PlanNotAvailable`: the target plan is retired, including an interval switch on a retired plan the customer is already on.
  - `InvalidPlanChange`:
    - the target is the same plan and interval and no change is pending;
    - the current period has already ended but `renew_due` hasn't run yet. We don't silently issue renewal invoices from `change_plan`.

**7. Bookkeeping**
- I'll start `GLOSSARY.md` (proration, upgrade/downgrade, scheduled change).
- I'll write an ADR for the proration policy, since invoices will depend on it.
- OK?

### [build] user

Mostly agreed; two corrections.

1. Upgrade vs downgrade is decided only by the plans' monthly list price (monthly_price), whichever interval the customer is on or moving to: more expensive plan = upgrade, applies now; cheaper = downgrade, waits for period end (also when combined with a switch to annual). Switching interval on the same plan is neither. ANY interval switch, either direction, waits for period end; we never refund unused annual time. Upgrade combined with an interval switch: split it. Upgrade happens now, prorated at current-interval prices; the interval switch is scheduled for period end.

2. Agreed. Compute each line exactly (price x remaining days / period days, no rounded daily rate), round each half-up on its own, total = sum of the two rounded lines. Both lines use the current interval's prices. Example: Pro->Premium Mar 11 in Mar 1-Apr 1: -20.32 and +50.81, total 30.49. Next renewal bills the new plan at full price.

3. Wrong, drop it. There is no immediate interval switch, no credit, no new period starting today. Interval switch is scheduled; at period end a period of the new interval starts and bills that interval's full price.

4. Mostly fine. Each request states the full target (plan+interval) and replaces whatever was scheduled. An upgrade applying now also discards anything scheduled (unless the same request schedules an interval switch). A scheduled change hasn't happened yet: an upgrade is prorated from the current plan, not the scheduled one (on Pro, Basic scheduled, Premium requested Mar 11 -> 30.49). Same plan+interval while something is scheduled cancels it, returns None, nothing billed. Discarding on cancel is fine.

5. Agreed: any change in a trial (up, down, interval) applies immediately, None, no invoice, trial end doesn't move; at trial end bill the full price of the plan and interval they're on by then.

6. Agreed, noting customers on a retired plan may still move off it; only moving TO a retired plan raises PlanNotAvailable. Rejected requests change nothing (no invoice, subscription untouched). I don't mind the retired-plan interval-switch case or requests after period_end.

7. OK, go ahead with glossary and ADR.

### [build] agent

Thanks. Your example checks out: Premium at $75/month gives 75 × 21/31 = 50.806 → 50.81, and Pro gives 30 × 21/31 = 20.32.

One case is still open:

**Lateral move: a different plan with the same `monthly_price`.**
- It's neither an upgrade nor a downgrade under your rule.
- **Recommendation:** treat it like a downgrade. It's scheduled for the end of the period, returns `None` and bills nothing now.
- The alternative is to switch now with no invoice, since the proration lines would cancel to 0.00.

For the two cases you left to me, unless you object:
- **Request on or after `period_end` before `renew_due` has run:** raise `InvalidPlanChange` and change nothing.
- **Retired plan:** an interval switch on the retired plan the customer is already on is allowed. Only a *different* retired target raises `PlanNotAvailable`.
- **Plan retired while a downgrade to it is scheduled:** the scheduled change still applies at renewal, because the customer chose it while the plan was still for sale.

### [build] user

All fine by me: I don't mind how same-price plans, the retired-plan cases, or requests after period_end are handled, so go with your recommendations. Go ahead and write the spec.

### [build] agent

`change_plan` is built and every criterion in the spec has a test; the full suite passes. Nothing is committed yet.

```
$ python3 -m pytest -q
....................................................                     [100%]
52 passed in 0.04s
```

That is 21 existing tests plus 31 new ones in `tests/test_plan_changes.py`. All the new behaviour tests failed before `change_plan` existed. Your example comes out as specified: Pro→Premium on Mar 11 gives −20.32 and +50.81, total 30.49, both with and without Basic scheduled.

**What changed**
- **`src/billing/service.py`:** adds `change_plan` with your exact signature.
  - Upgrades are invoiced now, prorated as agreed.
  - Downgrades, same-price changes and interval switches are scheduled and return `None`.
  - Changes during a trial apply immediately.
  - `renew_due` applies the scheduled change at the period end, and `cancel` discards it.
- **`src/billing/subscriptions.py`:** a subscription now carries an optional `ScheduledChange` (plan and interval).
- **`src/billing/errors.py`:** adds `InvalidPlanChange(BillingError)`. It is also exported from `billing`.
- **New docs:** the spec in `specs/plan-changes.md` (with your interface copied verbatim), `GLOSSARY.md`, and the decision record `docs/adr/0001-plan-change-proration.md`. The README is updated.

**Review fixes:** I ran `/code-review` and fixed three issues:
- If recording the upgrade invoice failed, the subscription had already been moved to the new plan. It is now saved only after the invoice is recorded.
- Upgrading from a free plan produced a credit line of `-0.00`. It now shows `0.00`.
- The comment on `Subscription` and the README didn't say that same-price changes are scheduled too.

I also added tests for these and for an upgrade discarding a scheduled interval switch.

**Decision for you:** upgrades are decided by monthly price but prorated at the current interval's prices, as you specified. If a plan has a higher monthly price but a lower annual price, an annual customer upgrading to it gets an invoice with a negative total, which is in effect a refund. Today's plans aren't priced that way, and I've noted the assumption in the ADR. If you want it enforced, there are two options: reject such plans when they're created, or reject such upgrades with `InvalidPlanChange`.

**Already in the repo:** `__pycache__/*.pyc` files are tracked in git, so running the tests changes them. Untracking them and adding `.gitignore` is a separate cleanup, which I didn't do.

Your CLAUDE.md asks for a fresh-session review against the spec for high-stakes changes. Money-calculation rules arguably count, so I can start that review if you want it.
