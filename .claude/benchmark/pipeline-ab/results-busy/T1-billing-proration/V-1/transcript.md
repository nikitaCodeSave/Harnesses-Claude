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

I've added `BillingService.change_plan(subscription_id, new_plan_code, new_interval=None) -> Invoice | None` with the interface you specified, plus `InvalidPlanChange(BillingError)`. The full suite passes: 38 tests, including 18 new ones in `tests/test_change_plan.py`. I haven't committed anything.

**How a change is priced:** the days left in the current period are credited at the current plan's price. That credit is set against the new charge:
- **Same interval:** the new plan is charged for the same remaining days, and the period dates stay the same. For example, moving Basic $10 → Pro $30 with 21 of 31 days left gives an invoice of −$6.77 / +$20.32 = **$13.55**.
- **Interval switch:** a full new period starts today and is charged in full. Monthly → annual is a $100 charge minus the unused monthly days.

**Decision for you: downgrades never refund.** The store has no refund or credit-balance concept, and a negative invoice could be mistaken for a charge by whatever collects payment. So:
- **Upgrades:** if the new charge is more than the credit, the change happens now and the invoice for the difference is returned.
- **Downgrades:** if the new charge is less than the credit, nothing is billed and `None` is returned. The change is saved on the subscription (a new optional `scheduled_change` field) and applied at the next renewal. The customer keeps what they paid for until the period ends. Annual → monthly therefore takes effect when the paid year ends.
- **Undoing:** asking for the current plan and interval again cancels a scheduled downgrade.

If you'd rather downgrades apply immediately with a credit carried to the next renewal, that's a contained change, but it needs a stored credit balance.

**Other behaviour:**
- **Trials:** the plan or interval switches straight away, nothing is billed, and the trial continues. The first paid period bills the new terms.
- **Equal net cost** (e.g. two plans with the same price): the change applies now, with no invoice, and `None` is returned.
- **Overdue renewal:** if the period has already ended but `renew_due` hasn't run yet, that renewal is billed first, as `renew_due` would bill it, and then the change is worked out. The result is the same whether or not the daily job ran first. Those renewal invoices go into the store, but only the change invoice is returned.
- **Errors:**
  - `InvalidPlanChange` when nothing would change.
  - `SubscriptionNotActive` for canceled subscriptions.
  - `PlanNotFound` / `SubscriptionNotFound` for unknown ids.
  - `PlanNotAvailable` for moving to a retired plan. This includes switching interval on a retired plan you're already on, because I treated that as a new sale. Customers can still move off a retired plan.

**Other files touched:**
- `_renew` in `src/billing/service.py` now applies scheduled changes.
- `renew_due` now shares the catch-up loop with `change_plan`.
- `README.md` explains how plan changes are priced.
- `InvalidPlanChange` and `ScheduledChange` are exported from the package.

The new `scheduled_change` field on `Subscription` will need a column in the production database-backed store.
