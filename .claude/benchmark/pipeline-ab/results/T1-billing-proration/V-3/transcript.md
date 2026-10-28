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

I've added `BillingService.change_plan` with the signature you specified, plus the new `InvalidPlanChange` error. All 40 tests pass: the 20 existing ones and 20 new ones in `tests/test_change_plan.py`. Nothing is committed.

**How a change is billed.** Every change takes effect on the day it's requested.
- **Credit for unused days:** the customer gets back the unused days of the current period, at the current plan's price × days left ÷ days in the period. Each line is rounded to the cent separately.
- **Same interval:** the billing period stays the same. The new plan is charged for the rest of it at the same daily rate. Example: basic → pro ($10 → $30 a month) on Jan 25 of a Jan 15 – Feb 15 period gives −6.77 + 20.32 = **13.55**. The Feb 15 renewal then bills $30.
- **Interval switch:** a new full period starts that day and is billed at the new plan's full price, after the credit. For example, switching from monthly to annual bills the full annual price minus the unused monthly days.
- **Changing more than once in a period:** the second credit is at the rate actually paid after the first change. Upgrading and then downgrading on the same day costs nothing extra (a test covers this).
- **During a free trial:** the plan and interval are swapped, the trial end date stays, nothing is billed, and the method returns `None`. The first paid period uses the new plan and interval.
- **When it returns `None`:** whenever every line comes to zero, for example switching between two free plans.

**Rejected requests:**
| Case | Error |
|---|---|
| Unknown subscription or plan | `SubscriptionNotFound` / `PlanNotFound` |
| Canceled subscription | `SubscriptionNotActive` |
| Target plan is retired | `PlanNotAvailable` |
| Same plan and same interval (nothing to change) | `InvalidPlanChange` |
| Current period has already ended but the renewal hasn't been billed yet | `InvalidPlanChange` (run `renew_due` first) |

**Decisions for you to check:**
1. **Downgrades produce a credit invoice with a negative total.** For example, pro → basic on Jan 25 gives **−13.55**, and annual → monthly mid-year gives about −$121. The package has no customer balance, so nothing applies that credit to later invoices. Whatever handles payments has to refund it or carry it forward, or customers won't actually get the money back. The alternative is to switch downgrades at the end of the period. That would need a "pending change" field on `Subscription`, and the database-backed store would have to save it. I avoided that so this change adds no new fields to anything the store saves.
2. **A customer on a retired plan can move off it, but can't switch interval on it.** I treated monthly → annual on a retired plan as selling it again.
3. **A change can't be made while a renewal is outstanding** (the period has ended but `renew_due` hasn't run). If `renew_due` runs daily this is a short window, but support may occasionally hit it.

I also added a short section on plan changes to the README.

### [build] user

Several of these don't match what I need, so please rework them.

1. Downgrades: don't credit them. A move to a cheaper plan, judged by monthly list price whatever the interval, waits for the end of the period. Nothing is billed, refunded or credited at the request, change_plan returns None, and no invoice is recorded. The customer keeps the current plan until the period end. The renewal then moves them to the cheaper plan and bills its full price. A new field on the subscription for the scheduled change is fine. This also applies to a downgrade combined with a switch to annual.

2. Interval switches (monthly<->annual): these also wait for the period end, in both directions. We never refund unused annual time, and nothing is billed at the request. The renewal starts a period of the new interval at its full price. If an upgrade comes with an interval switch, split it. The upgrade happens now, prorated at the current interval's prices, and the interval switch happens at the period end.

3. Upgrades: these apply immediately, but the period doesn't move. It keeps the same start and end, and the next renewal bills the new plan at full price. The invoice has exactly two lines. One is a credit for the unused part of the current plan, and the other is a charge for the same remaining days on the new plan. Both use the current interval's prices. Remaining days count from the change date inclusive to the period end exclusive, over the real calendar days in the period. Each line is price x remaining days / period days. Each line is rounded half-up to the cent on its own, and the total is the sum of the two rounded lines. Example: Pro->Premium on Mar 11 in a Mar 1-Apr 1 period gives -20.32 + 50.81 = 30.49.

4. Only one scheduled change at a time: each request states the full target (plan + interval) and replaces whatever was scheduled before. An upgrade that applies now also discards anything scheduled, unless that same request schedules an interval switch. A scheduled change hasn't happened yet, so an upgrade requested while a downgrade is scheduled is prorated from the current plan, not the scheduled one. Asking for the plan and interval they already have cancels any scheduled change, returning None with nothing billed. If nothing is scheduled, raise InvalidPlanChange.

5. Trials: your handling matches what I want. Any change applies immediately, returns None, and records no invoice. The trial end date doesn't move.

6. Your points 2 and 3: I don't mind either way.

The error cases you listed are fine. A rejected request must change nothing.

### [build] agent

I've reworked `change_plan` to follow your rules. All 47 tests pass: the 20 original ones and 27 rewritten ones in `tests/test_change_plan.py`. Nothing is committed.

**What now happens:**
- **Upgrades** (a higher monthly list price) apply at once and the period keeps its dates. The invoice has exactly two lines: a credit for the unused days of the current plan and a charge for the same days on the new plan, both at the current interval's prices and each rounded on its own. Your example, Pro → Premium on Mar 11 in a Mar 1 – Apr 1 period, gives −20.32 + 50.81 = 30.49, and that exact case is a test. The next renewal bills the new plan at full price.
- **Downgrades and interval switches** (either direction) bill nothing at the request and return `None`. The subscription stays as it is until the renewal moves it to the new plan and interval and bills the full price.
- **An upgrade combined with an interval switch** is split: the upgrade is invoiced now at the current interval's prices, and the switch happens at the period end.
- **One scheduled change at a time:**
  - Each request replaces whatever was scheduled.
  - An upgrade with no interval switch clears the schedule.
  - Upgrades are always prorated from the current plan, never the scheduled one.
  - Asking for the current plan and interval cancels the scheduled change. If nothing was scheduled, it raises `InvalidPlanChange`.
- **Trials:** unchanged. The change applies at once, returns `None`, no invoice is recorded, and the trial end date stays.
- **Rejected requests change nothing.** Every check runs before anything is saved, and the tests confirm the subscription and its invoices are unchanged afterwards.

**Model change:** `Subscription` has a new optional field, `scheduled_change: ScheduledChange | None`, holding the target plan and interval. Renewal applies it and then clears it. The production database-backed store will need to save and load this field. If it doesn't, scheduled changes will be silently lost.

**Edge cases your spec didn't cover, and what I did:**
- **A different plan with the same monthly price** isn't cheaper, so it doesn't strictly count as a downgrade. I schedule it like one, because applying it now could bill or credit the customer.
- **A scheduled plan retired before the renewal** still applies at the renewal, the same way existing customers keep renewing on retired plans.
- **Asking for the current plan and interval to cancel a scheduled change** is allowed even if the current plan has since been retired.
- **An upgrade on annual billing can produce a credit.** That happens if the new plan costs more per month but less per year, because proration uses annual prices. I followed your formula as written rather than adding a guard. Say if you'd rather reject or schedule that case.

The README's section on plan changes is updated to match.
