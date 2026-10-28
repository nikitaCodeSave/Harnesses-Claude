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

Before writing the spec I need some decisions from you. Here's what the codebase already gives us: periods are half-open `[start, end)`, money is cents rounded half-up, there are no refunds and no credit balance, `LineItem` accepts negative amounts, and the errors `PlanNotFound`, `PlanNotAvailable` and `SubscriptionNotActive` already exist. Each question below has my recommendation, so you can just answer "yes" or override it.

**1. Upgrades (same interval, new plan costs more).** Do they take effect immediately, keeping the same period end? The invoice would credit the unused part of the old plan and charge the new plan for the days left. Day counts are whole days: days left = `period_end − today` (today is billed on the new plan), divided by total days in the period. Each line is rounded to cents half-up. *Recommend: yes, one invoice with two lines (a negative credit and a positive charge).*

**2. Downgrades (same interval, new plan costs less).** Since we have no refunds or credit balance, I recommend scheduling them for the next renewal. Nothing is billed now, so `change_plan` returns `None`, and the subscription stays on the old plan until `period_end`. Or do you want them immediate, with a negative invoice?

**3. Same-price switch (lateral).** Should it be treated like a downgrade (scheduled, returns `None`)? Or immediate with no invoice?

**4. Monthly → annual.** *Recommend: immediate.* A new annual period starts today. The invoice credits the unused monthly days and charges the full annual price of the new plan. If that net would be zero or negative (for example, switching to a free annual plan), it's handled like a downgrade instead.

**5. Annual → monthly.** *Recommend: always scheduled for the end of the current annual period.* Doing it immediately would mean refunding most of a year.

**6. Pending scheduled changes.** If a change is already scheduled and a new request comes in, *recommend:* the new request replaces it. An immediate upgrade also clears it. Requesting the plan and interval the subscription is already on simply cancels the pending change and returns `None`. Should `cancel()` drop a pending change too?

**7. Trials.** Changing plan or interval during a trial *recommend:* switches immediately, bills nothing, returns `None`, and leaves the trial end date unchanged. The first paid period then uses the new plan and interval.

**8. Rejections.** *Recommend:*
- Unknown plan → `PlanNotFound`
- Retired target plan → `PlanNotAvailable`, even if it's the customer's current retired plan with a different interval
- Canceled subscription → `SubscriptionNotActive`
- Same plan and same interval with nothing pending → `InvalidPlanChange`
- Period already ended but `renew_due` hasn't run yet → `InvalidPlanChange`, because charging for "remaining days" of a period that's over makes no sense

Should the last one instead catch up the renewal first and then apply the change?

**9. Invoice date and line descriptions.** Is the invoice dated today, with descriptions like `"Unused Basic (monthly) 2026-01-20 to 2026-02-15"` and `"Pro (monthly) 2026-01-20 to 2026-02-15"`? Does anything downstream depend on description format?

**10. Non-goals.** *Recommend:* no refunds or credit balances, no changing the period anchor date for same-interval changes, no taxes or currencies, no admin overrides, no history or audit of plan changes beyond the invoices. Anything to add?

### [spec+build] user

Mostly agreed, but Q4 is wrong. Interval switches (monthly->annual and annual->monthly) always wait for period end; nothing is billed at request and we never refund unused annual time. At renewal a new period of the new interval starts at that interval's full price. If the request is also an upgrade, split it: the upgrade applies now, prorated at the current interval's prices, and the interval switch happens at period end.

Q1: yes. Upgrade vs downgrade is decided by monthly list price regardless of interval. Each line is price x remaining days / period days, computed exactly, rounded half-up on its own; the total is the sum of the two rounded lines (don't round the net). Use real calendar days; today counts as billed on the new plan.
Q2: yes, scheduled. Renewal moves them to the cheaper plan at its full price; this includes a downgrade combined with a switch to annual.
Q3: don't mind.
Q5: yes.
Q6: yes, the new request replaces the pending one, and an immediate upgrade clears it (unless the same request schedules an interval switch). Same plan and interval as now cancels the pending change and returns None. An upgrade requested while a downgrade is pending is prorated from the current plan, not the scheduled one. Don't mind about cancel().
Q7: yes. Any change in a trial, including interval, applies immediately, returns None, no invoice, trial end unchanged; at trial end they're billed full price of the plan and interval they're on by then.
Q8: fine. Customers on a retired plan can move off it like anyone else. Rejected requests change nothing (no invoice, subscription untouched). Don't mind about requests after period end or the retired-plan interval case.
Q9: invoice dated the change date; don't mind descriptions.
Q10: fine, nothing to add.

### [spec+build] agent

Customers can now change plan without support stepping in. The spec is in `SPEC.md`, `BillingService.change_plan` is built to it, and the full test suite passes:

```
$ python3 -m pytest -q
..........................................................               [100%]
58 passed in 0.02s
```

That's the 20 existing tests plus 38 new ones in `tests/test_plan_change.py`. Each new test is tagged with the numbers of the spec criteria it checks, and every criterion 1–22 has at least one test.

**How it behaves**
- **Upgrade** (higher monthly list price): takes effect today, with the same period dates. The invoice has two lines, a credit for the unused days of the old plan and a charge for the same days on the new one, both at the current interval's prices. Each line is rounded on its own and the total is their sum. One test pins this: basic to pro with 3 of 31 days left gives −0.97 + 2.90 = 1.93, where rounding the net would have given 1.94.
- **Downgrade or monthly/annual switch**: nothing is billed and `change_plan` returns `None`. The change is saved on the subscription and applied at the next renewal at full price. An upgrade combined with an interval switch is split: the upgrade is billed now and the interval changes at renewal.
- **Trial**: any change applies at once, with no invoice and the trial end unchanged.
- **Rejections**: a rejected request leaves the subscription and its invoices exactly as they were.

**Where you said you didn't mind, I chose:**
- A same-price switch is scheduled like a downgrade.
- A request made after the period has ended, before `renew_due` has run, raises `InvalidPlanChange`.
- The retired-plan check only applies when moving to a different plan, so someone on a retired plan can still switch its interval.
- `cancel()` leaves any scheduled change in place; it has no effect because canceled subscriptions never renew.

**What changed in the code**
- `errors.py` has the new `InvalidPlanChange`.
- `Subscription` has a new optional `scheduled_change` field, and the renewal code applies it and then clears it. The production database-backed store will need to save this field.
- `money.py` has a new `prorate()` helper that does the price × days arithmetic exactly before rounding.
- I added one line to the README about `change_plan`.

Nothing is committed yet.
