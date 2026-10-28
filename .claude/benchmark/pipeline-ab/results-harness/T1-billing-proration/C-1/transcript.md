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

I've read the code and tests (20 pass right now). There's no `GLOSSARY.md`, no `docs/adr/` and no `specs/` yet, so I'll create them as I go. Before I write the spec I need you to decide a few things. Each one has a recommended answer, so a reply like "all as recommended except 3" is enough.

**1. How proration is counted.** Count by days. The change starts today, so today is billed at the new plan. Remaining days = `period_end − today`, out of the current period's length in days.
- Credit line: −(old price × remaining / period days)
- Charge line: +(new price × remaining / period days)
- Each line is rounded to cents on its own, half up. The invoice is dated today.

**2. Which changes happen now and which wait.** I recommend one rule that covers every case: work out the prorated amount for doing the change today.
- **The customer would owe money:** apply it now, issue the invoice and return it.
- **It comes out at exactly zero:** apply it now and return `None`.
- **We would owe the customer money:** don't apply it yet. Save it as a pending change, return `None`, and apply it at the next renewal, which then bills the new plan.

This means we never need a credit balance, which the model doesn't have. In practice:
- An upgrade on the same interval applies now.
- A downgrade on the same interval waits until the period ends.
- Annual → monthly almost always waits.

Alternative: classify by plan price instead, so the outcome doesn't depend on the date.

**3. What an interval switch does when it applies now.** The current period ends today and a new full period of the new interval starts today, which moves the renewal date. The invoice credits the unused part of the old period and charges the full price of the new interval. Monthly → annual works this way. Annual → monthly is immediate only in the rare case where rule 2 says the customer owes money.

**4. Trials.** During a trial, any change (plan and/or interval) applies at once and bills nothing, so it returns `None`. The trial end date stays the same, and the first paid period uses the new plan and interval.

**5. Pending changes.**
- A new `change_plan` call replaces any pending change.
- Asking for the current plan and interval while a change is pending cancels the pending change and returns `None`.
- A change that applies now also clears any pending one.

**6. Errors.**
- Unknown subscription → `SubscriptionNotFound`
- Unknown plan → `PlanNotFound`
- Retired target plan → `PlanNotAvailable`
- Canceled subscription → `SubscriptionNotActive`
- Same plan and interval with nothing pending → `InvalidPlanChange`

Customers on a retired plan may still move off it. If a pending target is retired before the renewal, it still applies, because it was sold while it was available.

**7. A change requested on or after `period_end` before `renew_due` has run.** I recommend raising `InvalidPlanChange` ("renewal pending"). The alternative is to renew that subscription first and then apply the change. Which do you want?

**8. Out of scope:** credit balances or refunds, scheduling a change for a future date, proration for cancellations, and price changes on existing plans (the store has no way to change a price anyway).

One consequence to flag: pending changes need two new optional fields on `Subscription` (`pending_plan_code` and `pending_interval`). The production store would need matching columns. I'll record that in an ADR.

### [build] user

Answers by number:

1. Mostly right, with two corrections. Remaining days run from the change date, inclusive, to the period end, exclusive. "Days in the period" are real calendar days: 28-31 for a month, 365 or 366 for a year. Each line is exact (price x remaining / period days) and rounded half-up on its own. The total is the sum of the two rounded lines. Example: Pro -> Premium on Mar 11 in a Mar 1-Apr 1 period gives 21/31, lines -20.32 and +50.81, total 30.49.

2. No, don't use the "owe money" rule. Classify by the plans' monthly list price, whatever interval the customer is on or moving to.
- A more expensive plan is an upgrade and applies right away. The billing period doesn't move, and the next renewal bills the new plan at full price.
- A cheaper plan is a downgrade. It waits for the period end, with nothing billed or credited now. change_plan returns None and no invoice is recorded. This holds even when combined with a switch to annual.
- A switch of interval on the same plan is neither. It also waits for the period end, in both directions. We never refund unused annual time. The renewal then starts a period of the new interval at its full price.
- An upgrade combined with an interval switch is split. The upgrade happens now, prorated at the current interval's prices. The interval switch happens at the period end.

3. No. An interval switch never applies mid-period, so the period dates never move early. See 2.

4. Agreed. During a trial any change applies immediately, with no invoice, and change_plan returns None. The trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they're on by then.

5. Agreed on all three. Each request states the full target (plan and interval) and replaces whatever was scheduled. An upgrade that applies now also discards anything scheduled, unless that same request schedules an interval switch. A scheduled change hasn't happened yet. If a downgrade is scheduled and the customer then requests an upgrade, prorate from the current plan, not the scheduled one. Requesting the current plan and interval cancels a scheduled change, returns None and bills nothing.

6. Agreed, including that customers on a retired plan can move off it. I have no view on what happens when a pending target gets retired before renewal.

7. I don't mind. Use your recommendation.

8. Agreed.

The two new optional fields on Subscription are fine, and so is the ADR.

### [build] agent

I have two cases left. In both, your rule leaves the outcome open:

**A. A different plan with the same monthly list price.** Your rule doesn't say whether this is an upgrade or a downgrade. I recommend treating it like a downgrade: it's scheduled for the period end, nothing is billed, and `change_plan` returns `None`. Moving now with a zero-total invoice wouldn't really fit the rule that the period never moves early.

**B. An annual customer "upgrades" where the target plan's annual price isn't higher.** Upgrades are decided by monthly price but prorated at the current interval's price. That can produce a zero or negative invoice. Example: from Basic at 10/mo and 100/yr to a plan at 12/mo and 90/yr. A negative invoice would be a refund, which is out of scope. Options:
- (i) Raise `InvalidPlanChange` *(recommended: the price sheet is inconsistent, so support should look at it)*
- (ii) Apply it now with a negative invoice
- (iii) Schedule it for the period end like a downgrade

Two smaller points I'll decide unless you object:
- A pending target that is retired before the renewal still applies at the renewal.
- An upgrade whose two rounded lines happen to cancel out (zero total) still records and returns its invoice. This can only happen with a few cents between prices and a 1-day remainder.

### [build] user

A. Same monthly price is something I don't mind. Your recommendation is fine.

B. My notes don't cover this case, so I accept your recommendation. Raise InvalidPlanChange. Our price sheets shouldn't have this, so I'm not worried about it.

On your two smaller points: a pending target that gets retired before renewal is also something I don't mind, so go ahead. A zero-total upgrade invoice is fine either way too, so decide as you like.

### [build] agent

`BillingService.change_plan` is built as specified in `specs/plan-changes.md`, and the full suite passes:

```
$ python3 -m pytest -q
..........................................................               [100%]
58 passed in 0.04s
```

That's the 20 original tests, 34 for plan changes in `tests/test_plan_changes.py`, and 4 for the new proration helper. The new tests failed before the code existed. Each of the 20 acceptance criteria in the spec has at least one test, and your Pro → Premium example (−20.32, +50.81, total 30.49) is checked as written.

**How it behaves**
- **Upgrades** (higher monthly list price) apply today. They return an invoice with a credit line for the old plan and a charge line for the new one. Each line is rounded half-up on its own, by calendar day, at the current interval's prices. The billing period doesn't move.
- **Waits for the period end:** downgrades, plans with the same monthly price, and interval switches in either direction. They return `None` and bill nothing; the next renewal applies them and bills the full price.
- **Upgrade plus interval switch:** the upgrade is prorated now and the interval switch waits for the period end.
- **Trials:** any change applies at once and bills nothing; the trial end date stays put.
- **Raises `InvalidPlanChange`:**
  - when the customer asks for their current plan and interval and nothing is scheduled;
  - when a renewal is due but hasn't run yet;
  - when an annual customer "upgrades" to a plan whose annual price isn't higher.

The other errors use the existing classes.

**What changed in the code**
- `Subscription` has two new optional fields, `pending_plan_code` and `pending_interval`, which hold the scheduled change. The production store will need two nullable columns for them.
- `money.py` has a `prorate()` helper that uses whole-number arithmetic, so the half-cent rounding is exact.
- `InvalidPlanChange` is added to the errors and exported from `billing`.

**Changes from the review**

`/code-review` found two real problems, which I fixed with a test each:
- A free plan's credit line came out as `-0.00`; it's now `0.00`.
- Canceling a subscription left its scheduled change on record. Canceling now drops it. This is a small change to `cancel()` that you didn't ask for, and I added it to the spec as criterion 20.

I also took a few tidy-ups it suggested. I didn't act on one finding, a raw `ValueError` if the clock reads earlier than `period_start`, because it can't happen: the clock can't go backwards.

**Docs:** the spec, a new `GLOSSARY.md`, and two decision records: `docs/adr/0001-scheduled-plan-change-on-subscription.md` (the new fields) and `docs/adr/0002-plan-change-classification-and-proration.md` (the rules). The README is updated too.

The repo tracks compiled `__pycache__/*.pyc` files, so running the tests shows them as modified. That predates this change and I didn't touch it; you may want a `.gitignore` entry. Nothing is committed.
