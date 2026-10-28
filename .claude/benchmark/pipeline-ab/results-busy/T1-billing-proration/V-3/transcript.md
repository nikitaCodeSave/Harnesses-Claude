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

I added `BillingService.change_plan(subscription_id, new_plan_code, new_interval=None)` and `InvalidPlanChange` with the interface you specified. The full suite passes (39 tests, 19 of them new in `tests/test_change_plan.py`). Nothing is committed yet.

**How a change is billed** (proration counts days in the current period):
- **The old plan:** the days left in the period are credited at its price. Changing on day 11 of a 31-day monthly Basic plan ($10) credits 10 × 21/31 = −$6.77.
- **Same billing interval:** the new plan is charged for those same remaining days, so Pro ($30) costs +$20.32. The renewal date stays the same, and the next renewal bills the new plan at full price.
- **Switching monthly ↔ annual:** a new period of the new interval starts today and is charged in full; the old plan's unused days are still credited.
- Both lines go on one invoice dated today, recorded in the store and returned. Zero-amount lines are left off. If no lines are left (e.g. moving between two free plans), no invoice is issued and the method returns `None`.
- **During a free trial:** nothing has been paid, so the plan and interval are swapped with no invoice, returning `None`. The trial end date doesn't move, and the first paid period is on the new plan and interval.
- Changing plan twice on the same day nets to zero: the two credits and charges cancel out exactly.

**Decisions you should check:**
1. **Downgrades produce an invoice with a negative total**, i.e. a credit owed to the customer (for example Pro → Basic on that same day is −$13.55). Annual → monthly usually ends up negative too. The package has no customer balance, so I couldn't carry the credit forward to the next renewal. If anything downstream tries to charge the invoice total, it needs to treat a negative total as a refund or credit. The alternative is to store a pending credit on the subscription, which changes the schema of the production store.
2. **Changing plan when a renewal is due but hasn't been billed yet raises `InvalidPlanChange`.** In that state there are no unused days left to credit, and the renewal is still owed, so `renew_due` has to run first.
3. **A retired plan can't be the target of a change, even just to switch its interval (`PlanNotAvailable`).** I treated that as selling the plan again. Customers can still move off a retired plan.
4. **Asking for the plan and interval the subscription is already on raises `InvalidPlanChange`.**

The existing errors are reused where they fit: `SubscriptionNotFound`, `PlanNotFound` and `SubscriptionNotActive` (for canceled subscriptions). The service change is in `src/billing/service.py`; I also exported `InvalidPlanChange` from `billing/__init__.py` and updated the README.
