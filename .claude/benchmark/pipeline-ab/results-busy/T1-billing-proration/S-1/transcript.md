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

I've read the package (service, periods, money, tests). Before I write the spec I need your decisions on these. Each one has my recommendation, so you can just answer "yes" or override the ones you disagree with.

**1. Proration basis.** Prorate by calendar days over the current period: unused fraction = (period_end − today) / (period_end − period_start). Each prorated line is rounded to cents half-up, as `to_money` already does. Changing on `period_start` gives full credit.
→ Recommend: yes.

**2. Same interval, plan change (e.g. basic→pro monthly).** Keep the current period dates. The change invoice has two lines: a credit of −(old price × unused fraction) and a charge of +(new price × unused fraction). The next renewal bills the new plan at full price on the original `period_end`.
→ Recommend: yes.

**3. Interval change (monthly↔annual, same or different plan).** A new period of the new interval starts today. The invoice credits the unused part of the old period and charges the full price of the new period. The billing anchor moves to today.
→ Recommend: yes.

**4. Downgrades, where the net amount is negative.** This is the big one. Options:
   - (a) **Immediate.** Issue an invoice with a negative total (a credit note) today. Simple, and nobody pays twice, but it implies a refund or credit that something downstream has to handle.
   - (b) **Scheduled.** The downgrade takes effect at `period_end`, with no proration and no invoice now, so the method returns `None`. The customer keeps what they paid for until renewal, then renews on the cheaper plan or interval. The subscription would need a "pending change" field.
   - (c) **Immediate, with a credit balance carried to future invoices.** This adds a customer balance concept that doesn't exist yet.

   → Recommend **(a)**. It's one uniform rule (always prorate now), and `None` stays reserved for trials. If you want (b), I need to know what "downgrade" means for something like pro-monthly → basic-annual. Is it decided by comparing the net amount?

**5. During a trial.** Switch the plan and/or interval and keep the trial end date. No invoice; return `None`.
→ Recommend: yes.

**6. Errors.**
   - Canceled subscription → `SubscriptionNotActive`
   - Unknown subscription → `SubscriptionNotFound`
   - Unknown plan → `PlanNotFound`
   - Retired target plan → `PlanNotAvailable`. This also covers switching interval while staying on your own retired plan, since that counts as a new sale.
   - Same plan and same interval → `InvalidPlanChange`

   → Recommend: yes. Confirm the retired-plan interval switch case in particular.

**7. Renewal overdue.** Today ≥ `period_end`, but `renew_due` hasn't run yet. Options: (a) raise `InvalidPlanChange` ("renew first"), or (b) run the overdue renewals for that subscription first, then apply the change.
→ Recommend **(a)**. It has no hidden side effects, and the gap only exists until the renewal job runs.

**8. Non-goals I plan to list:** taxes, payment collection/refunds, customer credit balances, scheduled/future-dated changes, quantity/seat changes, coupons, changes to canceled subscriptions, and new `__init__` exports beyond `InvalidPlanChange`.
→ Anything here you actually want included, or anything missing?

### [spec+build] user

Most are fine, but 3, 4 and 8 contradict what I want and 6 needs a fix.

1. Yes. Remaining days run from the change date inclusive to period_end exclusive, using real calendar days. Compute each line exactly (price x remaining days / period days, no rounded daily rate), round each line half-up on its own, and the total is the sum of the two rounded lines.

2. Yes, but only for upgrades. An upgrade applies immediately, the period dates stay, and the next renewal bills the new plan at full price. Upgrade vs downgrade is decided by the plans' monthly list price (monthly_price), regardless of interval: a more expensive plan is an upgrade, a cheaper one is a downgrade.

3. No. Interval switches (monthly <-> annual) wait for the end of the period, in both directions. Nothing is billed at the request, and we never refund unused annual time. The renewal on period_end starts a period of the new interval and bills that interval's full price. If an upgrade comes together with an interval switch, split it: the upgrade happens now, prorated at the current interval's prices, and the interval switch happens at period end. Switching interval on the same plan is neither an upgrade nor a downgrade.

4. Option (b). A downgrade is scheduled for period end: change_plan returns None, nothing is billed, refunded or credited, and no invoice is recorded. The customer keeps the current plan until the renewal, which moves them to the cheaper plan and bills its full price. This holds for any move to a cheaper plan, including one combined with a switch to annual, so pro-monthly -> basic-annual is a downgrade. It is decided by monthly price, not by net amount. Only one scheduled change at a time: each request states the full target (plan + interval) and replaces whatever was scheduled. An upgrade that applies now also discards anything scheduled, unless that same request schedules an interval switch. A scheduled change hasn't happened yet, so an upgrade requested while a downgrade is scheduled is prorated from the current plan.

5. Yes, with two details. Any change in a trial (up, down or interval) applies immediately, returns None and records no invoice. The trial end date doesn't move, and at trial end the customer is billed the full price of the plan and interval they're on by then.

6. Yes, with one correction. Asking for the plan and interval they already have raises InvalidPlanChange only if nothing is scheduled. If something is scheduled, it cancels the scheduled change: returns None, nothing billed, and the renewal continues on the current plan. Moving off a retired plan is allowed like for anyone else; only moving to a retired plan raises PlanNotAvailable. I don't mind how you handle switching interval while staying on a retired plan. Any rejected request changes nothing: no invoice and the subscription is untouched.

7. I don't mind, go with (a).

8. Scheduled changes are in scope, so take that one off the list. The rest of the list is fine.

### [spec+build] agent

Thanks, that settles most of it. Three gaps are left that your rules don't cover:

**A. Same monthly price, different plan.** Say `pro` and a hypothetical `team` are both 30.00/month. A move between them is neither an upgrade nor a downgrade under the monthly-price rule.
→ Recommend: treat it like a downgrade. It's scheduled for period end, returns `None`, and nothing is billed now. Alternative: reject it with `InvalidPlanChange`.

**B. An upgrade by monthly price on an annual subscription where the new plan's *annual* price is lower or equal.** For example, old plan 30/mo and 300/yr, new plan 35/mo and 290/yr. Prorating at annual prices would give a zero or negative invoice, which is effectively a refund.
→ Recommend: still apply it now and issue the invoice exactly as computed, even if the total is ≤ 0. The rule stays mechanical and the case is rare. Alternatives: reject it with `InvalidPlanChange`, or skip the invoice when the total is ≤ 0.

**C. The target plan of a scheduled change gets retired before the renewal.**
→ Recommend: the scheduled change still applies at renewal. It was a valid sale when it was requested, and retired plans keep renewing for existing customers.

For the case you left to me, switching interval while staying on a retired plan, I'll allow it. The customer isn't moving *to* a retired plan, and retired plans keep renewing anyway.

### [spec+build] user

A. I don't mind, go with your recommendation.

B. Yes, apply the upgrade now and issue the invoice as computed. Whether an invoice is recorded when the two rounded lines net to exactly 0.00 is your call.

C. I don't mind, go with your recommendation.

Retired plan with an interval switch: allowing it is fine.

### [spec+build] agent

Customers can now change plan mid-cycle with `BillingService.change_plan`, and the full test suite passes:

```
$ python3 -m pytest -q
..............................................................           [100%]
62 passed in 0.02s
```

That's the 20 tests that were already there plus 42 new ones in `tests/test_change_plan.py`. Each new test is tagged with the `SPEC.md` criterion it checks, and all 27 criteria are covered.

**Spec.** `SPEC.md` has the interface you fixed, copied word for word, plus definitions, 27 acceptance criteria and the non-goals.

**How it behaves:**
- **Upgrades** (a plan with a higher monthly price) apply right away and keep the current period dates. The invoice has two lines: a credit for the unused days of the old plan and a charge for the same days on the new plan, each worked out exactly and rounded on its own.
- **Downgrades, same-price moves and interval switches** wait until the period ends. They return `None`, bill nothing, and the next renewal moves the customer and bills the full new price.
- **An upgrade combined with an interval switch** is split: the upgrade is billed now at the current interval's prices, and the interval switch happens at the next renewal.
- **During a trial**, any change applies immediately with no invoice, and the trial end date stays the same.

**Decisions you left to me:**
- An upgrade that nets to exactly 0.00 still records and returns an invoice.
- A move between two plans with the same monthly price is scheduled, like a downgrade.
- A scheduled change still applies at renewal even if its target plan was retired in the meantime.
- Switching interval while staying on a retired plan is allowed.
- A change requested on or after the period end, before the renewal job has run, raises `InvalidPlanChange`.

**Code changes:**
- `src/billing/service.py`: the new `change_plan`, and renewals now apply a scheduled change before billing.
- `src/billing/subscriptions.py`: subscriptions have two new optional fields, `scheduled_plan_code` and `scheduled_interval`, both empty by default. A database-backed store in production will need to save these.
- `src/billing/errors.py` and `src/billing/__init__.py`: the new `InvalidPlanChange` error, also exported from the package.
- `README.md`: a short note on plan changes.

Nothing is committed. Running the tests created untracked `__pycache__/` folders, since the repo has no `.gitignore`.
