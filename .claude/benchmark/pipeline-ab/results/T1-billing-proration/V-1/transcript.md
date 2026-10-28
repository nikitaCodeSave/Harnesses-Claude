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

I added `BillingService.change_plan` and `InvalidPlanChange` with the interface you specified. The full suite passes: 40 tests, 20 of them new in `tests/test_change_plan.py`. Nothing is committed.

**How the billing works**
- **Same interval:** the billing period stays the same. The invoice has two lines: a credit for the old plan's unused days and a charge for the same days at the new plan's rate. Both are worked out as a share of the full period. For example, Basic → Pro ($10 → $30) with 21 of 31 days left gives −$6.77 + $20.32 = **$13.55**.
- **Repeated changes:** because every change uses the same calculation, a second change in the same period credits exactly what was charged for the days being given back. A test covers basic → pro → basic within one period and checks that each day is billed once.
- **Monthly ↔ annual:** the unused part of the current period is credited, and a new period on the new interval starts today and is charged in full. Monthly Basic → annual Pro on day 10 gives −$6.77 + $300.00.
- **Trial:** the plan and interval are switched with no charge, and the call returns `None`. The first paid period after the trial uses the new plan and interval.
- **Free plans:** credit or charge lines of $0.00 are left off. If no lines remain (free plan → free plan), the change is saved and the call returns `None`.

**Decisions you may want to change**
1. **Downgrades produce invoices with a negative total.** Annual Pro → monthly Basic halfway through the year comes to −$141.23. There is no customer credit balance in the package, so the negative invoice is the only record of what's owed back. Whatever processes invoices must treat a negative total as a refund or credit, not a charge. If you'd rather downgrades wait until the period ends with no refund, that's a small change.
2. **If a renewal is due but hasn't been billed yet, `change_plan` bills it first** (for example, a request on renewal day before `renew_due` has run). It issues the same renewal invoice `renew_due` would have, then applies the change. That way the result doesn't depend on when the renewal job last ran. The renewal invoice is saved like any other but is not the one returned.
3. **Error cases:**
   - Changing to the plan and interval the customer already has raises `InvalidPlanChange`; it isn't treated as a no-op.
   - A canceled subscription raises `SubscriptionNotActive`.
   - Moving to a retired plan raises `PlanNotAvailable`. That includes switching a retired plan from monthly to annual, which I counted as a new sale. Moving away from a retired plan is allowed.
4. **Rounding:** each line is rounded half up to the cent separately, so totals over several changes can be off by a cent or two from the exact figure. A line never credits more than was charged for those days.

I also exported `InvalidPlanChange` from `billing/__init__.py` and added `change_plan` to the README layout section.

### [build] user

Several of these don't match what I want, so please change them.

1. Downgrades: Yes, they should wait. A move to a cheaper plan is decided by the plans' monthly list price, whichever interval is involved. Nothing is billed, refunded or credited at the request, so change_plan returns None and records no invoice. The customer stays on the current plan until the period end. The renewal then moves them to the cheaper plan and bills its full price. This also applies to a downgrade combined with a switch to annual.

2. Interval switches: These also wait for the period end, in both directions. I never refund unused annual time. Nothing is billed at the request. The renewal starts a period on the new interval and bills that interval's full price. If an upgrade comes with an interval switch, the upgrade happens now, prorated at the current interval's prices. The interval switch happens at the period end.

3. Upgrades: The billing period must not move. It keeps the same start and end, and the next renewal bills the new plan at full price. Proration uses real calendar days in the current period. Remaining days count from the change date inclusive to the period end exclusive. The invoice has exactly two lines. One is a negative credit for the unused part of the current plan and the other is a positive charge for the same days on the new plan. Each line is price x remaining days / period days, rounded half-up to cents on its own. The total is the sum of the two rounded lines. Pro -> Premium on Mar 11 in a Mar 1-Apr 1 period gives -20.32 and +50.81, total 30.49. Your Basic -> Pro example is therefore right on the amounts, but only for a change inside the same period.

4. Scheduled changes: There is only one at a time. Each request states the full target and replaces anything scheduled. An upgrade that applies now also discards what was scheduled. An upgrade is prorated from the current plan, not from a scheduled one.

5. Same plan and interval: If a change is scheduled, this cancels it and returns None. If nothing is scheduled, raise InvalidPlanChange.

6. Trials: Any change applies immediately in full, returns None and records no invoice. The trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they're on by then.

7. Your renewal-first behaviour: I don't mind it. Rejected requests must leave everything untouched, though, including the subscription.

8. Retired plans: Moving to one raises PlanNotAvailable. I don't mind how you handle switching interval while staying on a retired plan.

Please rework it to match this.

### [build] agent

I've reworked `change_plan` to follow all eight of your rules. The full suite passes: 53 tests, 33 of them in `tests/test_change_plan.py`. Nothing is committed.

**How it works now**
- **Scheduled change:** a `Subscription` can now hold one pending change (new `scheduled_change` field holding a plan code and interval). The renewal applies it: the new period runs on that plan and interval and is billed at its full price. `renew_due` is the only thing that applies it, so it doesn't matter whether the period ends on its own or a request arrives late.
- **Upgrades:** the billing period keeps its start and end. The invoice has exactly two lines (credit, then charge), each rounded on its own at the current interval's prices. Your Pro → Premium example is a test and gives −20.32 / +50.81 = 30.49. If the upgrade comes with an interval switch, the switch is stored as the scheduled change.
- **Downgrades and interval-only switches:** nothing is billed or refunded and the call returns `None`. The change is stored and the renewal applies it at full price. The cheaper plan is judged by monthly list price only: a test covers a plan that is cheaper per month but dearer per year, and it waits.
- **Same plan and interval:** this clears a scheduled change and returns `None`, or raises `InvalidPlanChange` if nothing is scheduled.
- **Trials:** every change applies at once in full, records no invoice, and leaves the trial end date where it was.
- **Rejected requests:** the request is checked against what the subscription will look like after any due renewal, without saving anything. Renewals are only billed once the request has been accepted. A test covers a renewal that is due plus an already scheduled change, with three kinds of rejected request. In each case the subscription and its invoices stay exactly as they were.

**Decisions you may want to change**
1. **Same monthly price, different plan:** a move to a plan with the *same* monthly price is treated as an upgrade, so it applies now and is prorated. Your rule only defined "cheaper", so this is my reading. At annual prices the two lines may not cancel out.
2. **Retired plans:** switching interval while staying on a retired plan raises `PlanNotAvailable`, as you left that open. Cancelling a scheduled change while on a retired plan is allowed.
3. **Plan retired after scheduling:** if a scheduled plan is retired before the period ends, the renewal still moves the customer onto it. I treated the sale as made when the request was accepted. Say if you'd rather the renewal drop the change instead.
4. **Production store:** the production store needs a new column for `scheduled_change`. The in-memory store already saves whole subscriptions, so it needed no change.

I also exported `ScheduledChange` from `billing/__init__.py` and added a short paragraph on plan changes to the README's conventions section.
