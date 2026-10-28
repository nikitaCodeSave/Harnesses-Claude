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

I've read the whole package. There's no glossary, no ADRs, and no `specs/` directory yet, and all 20 existing tests pass. Before I write the spec I need some billing-policy decisions that the code can't answer. Each question has my recommendation, so you can reply "all recommended" or change only the ones you disagree with.

**1. When does each kind of change take effect?**
- **Recommended:** upgrades take effect **today** and are billed now. Downgrades are **scheduled for the end of the current period**: nothing is billed now, so `change_plan` returns `None`, and the next renewal bills the new plan.
- Why: there's no credit balance or refund mechanism in the package. An immediate downgrade would need a negative invoice or a stored credit, and both are new concepts.
- Alternative: everything takes effect immediately, with a negative-total invoice for downgrades.

**2. What counts as an upgrade?**
- **Same interval:** the new plan's price for that interval is higher. A lower or equal price is scheduled for the end of the period.
- **Monthly → annual:** always immediate. A new annual period starts today, and you're billed the new annual price minus a credit for the unused monthly days. If that credit is larger than the annual price (possible only with odd pricing), the change is scheduled for the end of the period instead.
- **Annual → monthly:** always scheduled for the end of the annual period. Applying it now would mean refunding most of a year.

**3. How is proration calculated?**
- **Recommended:** by day, using the half-open period `[period_start, period_end)`.
  - Unused fraction = `(period_end − today) / (period_end − period_start)`.
  - Same-interval upgrade: the period dates stay the same.
- **Invoice layout:** two lines, each rounded half-up to the cent:
  - a negative credit line, "Unused time on Basic (monthly) …"
  - a positive charge line, "Remaining time on Pro (monthly) …"
- The alternative is a single net line. Two lines are easier to audit, but the total can differ by a cent from rounding the net amount once.

**4. Changes during a free trial?**
- **Recommended:** apply the new plan or interval immediately, bill nothing (return `None`), and keep the trial end date. The first paid period then uses the new plan and interval.

**5. What happens to a scheduled change on later requests?**
- **Recommended:**
  - A new request replaces the scheduled change.
  - An immediate upgrade clears it.
  - Asking for the current plan and interval while a change is scheduled cancels the scheduled change (returns `None`).
  - Asking for the current plan and interval with nothing scheduled raises `InvalidPlanChange`.

**6. Which requests are rejected, and with what error?**
- **Recommended:**

  | Request | Error |
  |---|---|
  | Unknown subscription | `SubscriptionNotFound` |
  | Canceled subscription | `SubscriptionNotActive` |
  | Unknown plan | `PlanNotFound` |
  | Retired target plan | `PlanNotAvailable` |
  | No-op request (see 5) | `InvalidPlanChange` |
  | Renewal is overdue (`today >= period_end`, `renew_due` hasn't run yet) | `InvalidPlanChange` |

- Leaving a retired plan is allowed.

**7. Storage**
- Scheduled changes need to live somewhere. **Recommended:** add two optional fields to `Subscription`, `scheduled_plan_code` and `scheduled_interval`, both defaulting to `None`.
- The store has no new methods, but the database-backed production store will need to persist these two fields. Is that acceptable, or should scheduled changes be kept outside `Subscription`?

**8. Recording decisions**
- I'll record "downgrades take effect at period end; no credits or refunds" as an ADR, since later work has to follow it. I'll also start `GLOSSARY.md` with the terms upgrade, downgrade, scheduled change, proration and credit line. OK?

### [build] user

Answers by number.

1. Agreed. Upgrades take effect today and are billed now. Downgrades wait for the period end, with nothing billed, refunded or credited at the request, and change_plan returns None.

2. I disagree with your recommendation.
- Upgrade vs downgrade is decided only by the plans' monthly list price, whichever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade. Switching interval on the same plan is neither.
- Every interval switch waits for the end of the period, in both directions. Nothing is billed at the request. The renewal on the period end starts a period of the new interval and bills that interval's full price. So monthly -> annual is not immediate, and we never refund unused annual time.
- A request that upgrades the plan and also switches interval is split. The upgrade happens now, prorated at the current interval's prices, and the interval switch happens at the period end.
- A move to a cheaper plan waits for the period end, even when combined with an interval switch.

3. Mostly agreed.
- Proration is by real calendar days. The fraction is remaining days over days in the period, where remaining days run from the change date (inclusive) to the period end (exclusive).
- The two-line layout is right. Each line is computed exactly as price x remaining days / period days, with no rounded daily rate, and rounded half-up to the cent on its own. The total is the sum of the two rounded lines, not a rounded net difference.
- Both lines use the prices of the interval the customer is currently on.
- Example: Pro -> Premium on Mar 11 in a Mar 1-Apr 1 period gives -20.32 and +50.81, total 30.49.

4. Agreed, with one addition. Any change during a trial (up, down or interval) applies immediately and returns None, with no invoice. The trial end doesn't move, and at trial end the customer is billed the full price of the plan and interval they're on by then.

5. Agreed. An immediate upgrade also clears whatever was scheduled, unless that same request schedules an interval switch. A scheduled change hasn't happened yet, so an upgrade requested while a downgrade is scheduled is prorated from the current plan, not the scheduled one.

6. The table is fine. Moving to a retired plan raises PlanNotAvailable, and leaving a retired plan is allowed. I don't mind how you handle overdue requests. Rejected requests must change nothing: no invoice and the subscription untouched.

7. I don't mind where scheduled changes are stored. Go with your recommendation.

8. OK. Write the ADR and the glossary.

### [build] agent

Mid-cycle plan changes are in. `BillingService.change_plan` follows the rules from your answers. All 52 tests pass: the 20 existing ones unchanged, plus 32 new ones.

```
$ python3 -m pytest -q
....................................................                     [100%]
52 passed in 0.02s
```

**How it behaves:**
- **Upgrades** (higher monthly list price) take effect today. They issue an invoice with a credit line and a charge line, each worked out exactly at the current interval's prices and rounded on its own. Your example comes out as -20.32 and +50.81, total 30.49.
- **Downgrades and interval switches** return `None` and bill nothing. They're stored on the subscription as a scheduled change. The renewal at the period end applies it and bills that plan and interval's full price.
- **During a trial**, every change applies immediately and bills nothing. The trial end doesn't move.
- **Rejected requests** change nothing. Overdue requests (renewal due but `renew_due` hasn't run) raise `InvalidPlanChange`.

I wrote the tests first and checked that all 32 failed before writing the code.

**Edge cases I decided, which you didn't specify:**
- **Same monthly price, different plan:** treated like a downgrade, so it waits for the period end and bills nothing.
- **Negative upgrade invoice:** a plan that costs more per month but less per year still counts as an upgrade. An annual customer moving to it gets an invoice that totals a negative amount. That's your rule as written, and a test covers it. Say if you'd rather such requests be rejected or wait for the period end.

**Decision needed:** a scheduled downgrade to a plan that gets retired before the period ends is still applied at renewal. That sells a retired plan to someone who wasn't on it. The review flagged this and the spec doesn't cover it. Should the renewal drop the scheduled change instead, or keep applying it because the customer asked while the plan was still on sale?

**Also from the review:**
- I fixed one cleanup finding: the "nothing scheduled" value was a shared mutable dict and is now a helper.
- I left two findings as they are:
  - **Overdue error order:** an overdue request naming an unknown or retired plan gets that plan error rather than `InvalidPlanChange`. You said overdue handling was up to me.
  - **Unchecked interval type:** the new scheduled interval isn't type-checked, matching the existing `interval` field, which isn't either.
- **Compiled `.pyc` files:** they're committed to the repo and every test run rewrites them, so they show up in the diff. Adding a `.gitignore` and untracking them is a separate one-off clean-up.

**Database store:** `Subscription` gains two fields, `scheduled_plan_code` and `scheduled_interval`, and the production store must save them.

**Files:**
- `specs/plan-changes.md`
- `docs/adr/0001-plan-changes-upgrade-now-defer-the-rest.md`
- `GLOSSARY.md`
- `README.md`
- `src/billing/errors.py`, `subscriptions.py`, `service.py`, `__init__.py`
- `tests/conftest.py`: adds a Premium plan at 75.00/750.00
- `tests/test_plan_changes.py`

Nothing is committed.
