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

I've added `BillingService.change_plan` with the interface you specified, plus `InvalidPlanChange` in `errors.py` (also exported from `billing`). All 36 tests pass: the 20 existing ones and 16 new ones in `tests/test_change_plan.py`. Nothing is committed yet.

**How a change is billed** (it always takes effect the day it's requested):
- **During a trial:** the plan and interval are swapped, the trial end date stays the same, and it returns `None`. The first paid period is billed at the new price when the trial ends.
- **Same interval, different plan:** the current period is kept. One invoice gives a credit for the unused days at the old price and charges the remaining days at the new price. Example: basic→pro on Feb 1, in a Jan 15 – Feb 15 period, is −4.52 + 13.55 = 9.03. The next renewal charges the full new price.
- **Switching monthly ↔ annual:** the unused days are credited and a full period of the new interval starts today. This moves the renewal date.

Each amount is rounded to the cent with your existing half-up rule. Changing plans and then changing back on the same day comes to exactly zero.

**Errors:**
- Unknown subscription or plan: `SubscriptionNotFound` / `PlanNotFound`.
- Canceled subscription: `SubscriptionNotActive`.
- Moving to a retired plan: `PlanNotAvailable`. This also blocks switching the interval while staying on a retired plan, since that counts as a new sale. Moving *off* a retired plan is allowed.
- `InvalidPlanChange` covers two cases:
  - the request doesn't change anything (same plan and interval);
  - the current period has ended but `renew_due` hasn't billed the renewal yet. Prorating over a period that's already over would be wrong, so I refuse rather than quietly issuing renewal invoices inside `change_plan`.

**Things to check before relying on this:**
1. **Downgrades can produce an invoice with a negative total.** For example, pro→basic mid-period is −9.03, and annual→monthly with six months left is about −121. There's no account-credit balance in the package, so that negative invoice is the only record that the customer is owed money. If anything downstream assumes invoice totals are positive (such as charging a card), it needs to refund or hold a credit for these.
2. **All changes, including downgrades, apply immediately.** Some billing systems wait until the end of the period for downgrades; supporting that would mean storing a pending change on `Subscription`. I didn't add one.
3. **The refusal on renewal day may annoy users.** If the renewal job runs late on the day a period ends, a plan change requested that day fails until the job has run. If you'd prefer, `change_plan` could bill the pending renewal first and then apply the change; it's a small change.
