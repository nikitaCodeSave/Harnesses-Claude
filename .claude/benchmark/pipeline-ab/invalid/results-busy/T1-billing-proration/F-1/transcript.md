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

I've read the whole package (service, store, periods, money, tests). A few things the code already settles, so I won't ask about them: money is whole cents rounded half up, periods are half-open `[start, end)`, retired plans can't be sold, `cancel` never refunds, and there's no customer credit balance anywhere in the store.

Below are the decisions that change what gets built. Each has a recommendation, so you can just answer "yes" or correct it.

**1. Proration basis.** I'd prorate by calendar days of the actual current period: `unused = days from today to period_end / days in period`. A Feb period then has 28 days and an annual one 365 or 366. The other option is a fixed 30/365-day month. **Recommend: actual calendar days.**

**2. Upgrade, same interval** (e.g. basic monthly → pro monthly on day 10 of 31). It takes effect today and the period end stays the same. The invoice issued today has two lines: a credit (negative) for the unused part of the old plan and a charge for the same days on the new plan. The next renewal bills the new plan at full price. **Recommend: yes.**

**3. Downgrades.** This is the biggest decision, because there's no credit balance and no refunds today. Options:
- (a) The downgrade is **scheduled for period end**. The customer keeps the current plan until the paid period runs out, then renews on the new plan. Nothing is billed now, so it returns `None`.
- (b) It **takes effect immediately** with a negative-total invoice (a credit note). That means someone has to actually refund it or carry it forward, and that machinery doesn't exist.
- (c) It takes effect immediately and the leftover credit is lost. That breaks "nobody pays twice".

**Recommend (a).** It also explains why the interface allows `None`.

**4. What counts as "upgrade" vs "downgrade"**, especially across intervals (pro monthly → basic annual)? Proposal: compare the **per-day cost of the new plan+interval against the current one**. Higher means upgrade (immediate). Equal or lower means downgrade (scheduled). The alternative is to rank plans by monthly price alone and ignore the interval. **Recommend: per-day cost.**

**5. Interval switches.** The current period can't just keep its end date when moving to a different interval length. Proposal: when the interval changes **and it's an upgrade**, a new period starts today with the new interval. The invoice credits the unused part of the old period and charges the full new period. When it's a downgrade (e.g. annual → monthly at the same plan), it's scheduled for the end of the current period, as in 3a. OK?

**6. Pending scheduled changes.** If a downgrade is scheduled and the customer then makes another change before period end:
- A new request **replaces** the pending one.
- Requesting the current plan+interval again **cancels** the pending change and returns `None`.
- Canceling the subscription drops it.

OK? And should a scheduled change be visible on the `Subscription`? That would mean a new optional field such as the pending plan code and interval.

**7. Edge cases.** Proposed rules for each:
- **Trialing:** switch plan/interval immediately, the trial end date doesn't move, nothing is billed, returns `None`.
- **Canceled:** `SubscriptionNotActive`.
- **Unknown plan:** `PlanNotFound`.
- **Retired target plan:** `PlanNotAvailable`, even when only the interval changes on a retired plan the customer is already on. Is that strict enough, or should they be allowed to switch interval on their own retired plan?
- **Same plan + same interval with nothing pending:** `InvalidPlanChange`.
- **Overdue subscription** (`period_end <= today`, `renew_due` hasn't run yet): `InvalidPlanChange` rather than silently renewing first?

**8. Repeated upgrades in one period.** Upgrading basic→pro and then pro→enterprise in the same period: the second credit is based on the current plan's price for the remaining days. The criterion I'd write: **across any sequence of changes in one period, the customer is never charged twice for the same day.** The total billed for the period equals the sum over each day of the price of the plan active that day, within a cent per change for rounding. Is a cent of rounding per line acceptable?

**9. Out of scope (non-goals).** Proposed:
- Quantity/seat changes
- Coupons and taxes
- Actual refunds or payment collection
- Credit balances
- Proration of trials
- Changing the billing anchor date when the interval doesn't change

Anything you'd add or remove?

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

I didn't build anything, because this workspace has no `SPEC.md`.

- **This repo:** the working directory has no `SPEC.md`, and git history has a single commit (`base`) that never contained one. The `README.md` describes the existing billing core (plans, subscriptions, invoices, `subscribe` / `renew_due` / `cancel`) but no new requirements.
- **Elsewhere on the machine:** there is a `SPEC.md` in a similar workspace, `/tmp/pab-work/T1-billing-proration-R-3/ws/SPEC.md`. Judging by the directory name, it's probably a proration spec for this same billing codebase. It belongs to a different workspace, though, and I can't confirm it matches what you want here, so I haven't used it.

How do you want to proceed?
1. Add `SPEC.md` to this workspace (or paste its contents), and I'll build it and run `python3 -m pytest -q`.
2. Confirm that the spec at `/tmp/pab-work/T1-billing-proration-R-3/ws/SPEC.md` is the right one, and I'll copy it in and build from it.
