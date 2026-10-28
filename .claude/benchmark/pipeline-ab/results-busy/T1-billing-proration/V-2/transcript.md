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

I've added `BillingService.change_plan(...)` and `InvalidPlanChange(BillingError)` with the exact interface you gave. The new tests (`tests/test_plan_change.py`) and the existing ones all pass, 40 in total. Nothing is committed.

**How a change is billed**
- **Takes effect today.** The days left in the current period are credited at the current plan's price, by days. If you keep the interval, the period dates stay the same and the new plan is charged for the same remaining days. If you switch between monthly and annual, a new full period starts today and is charged in full.
- **Example:** a monthly Basic customer ($10) who upgrades to Pro ($30) on day 16 of a 31-day period is billed −5.16 + 15.48 = **$10.32**.
- **Return value:** if the change costs more than the credit, an invoice dated today is recorded and returned. Otherwise nothing is billed and it returns `None`. Equal-price switches and changes during a trial also return `None`.
- **Trials:** nothing has been paid yet, so the plan and interval are just swapped. The trial end date doesn't move, and the first paid invoice uses the new plan and interval.

**Downgrades: where the leftover credit goes.** A downgrade, or a switch from annual to monthly, can leave the customer owed money: annual Pro switched to monthly halfway through leaves $121.23. Issuing a negative invoice seemed risky, because cancel says "no refund" and we don't know what downstream payment code does with negative totals. Instead, `Subscription` has a new field, `credit_balance`, which is taken off the subscription's next invoices (renewals or later upgrades) as an "Account credit applied" line, and never takes a total below zero. A test checks that switching up and back on the same day costs exactly one period's price.

**Rejected requests**
- **`InvalidPlanChange`:** the request is for the plan and interval the customer already has, or the subscription is due for renewal (`period_end <= today`). I chose to reject these rather than have `change_plan` quietly run the overdue renewal first.
- **Existing errors:** `SubscriptionNotFound`, `SubscriptionNotActive` (canceled), `PlanNotFound`, `PlanNotAvailable` (retired target plan).
- **Customers on a retired plan** can move to another plan but can't switch the retired plan's interval, since that would be selling it again.

**Decisions for you**
- **The production database store has to save `credit_balance`.** The field defaults to zero, so nothing breaks, but if the store doesn't save and load it, customers' credits will silently disappear.
- **Leftover credit is lost on cancel,** in line with the no-refund policy. If you'd rather refund it, that needs a payout path, which doesn't exist yet.
- **A downgrade leaves no invoice,** only the credit balance. If support needs a record of each change, the next step would be a credit note or a change log.

I also updated `README.md` with the proration rules and exported `InvalidPlanChange` from `billing/__init__.py`.
