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

I've read the whole package and its tests. Some facts that shape the questions:

- Nothing here holds a credit balance and nothing issues refunds. `cancel` says "No refund".
- A period is half-open `[start, end)` and is billed on `start`. Period lengths vary (28–31 days, 365/366).
- Retired plans can't be sold, but existing customers on them keep renewing.
- `Subscription` only describes the current period. It has no way to hold a "scheduled" change yet.

Each question below has my recommended answer. Reply "all defaults" or just list the numbers you'd change.

**Core proration**

1. **Unit of proration.** I'd prorate by calendar day over the actual length of the current period. Example: `unused = days in [today, period_end) ÷ days in [period_start, period_end)`. The day of the change counts as a day on the new plan. *Recommend: yes.*
2. **Rounding.** Each prorated line is rounded once to cents, half-up, from the exact fraction. The invoice total is the sum of its lines. The invoice shows the credit for the old plan and the charge for the new plan as separate lines, not one net amount. *Recommend: yes.* Example: basic→pro on Jan 25 in the period Jan 15–Feb 15 has 21 of 31 days left. That gives a credit of −6.77, a charge of +20.32 and a total of 13.55.

**Upgrade vs downgrade** (the core decision)

3. With no credit balance, a downgrade can't be "paid back" right away. I'd decide by the net amount:
   - **The change costs money today:** it takes effect today. We invoice the difference and return that invoice.
   - **The change would produce a credit:** it is scheduled for the end of the current period. Nothing is billed now and we return `None`. The next renewal bills the new plan and interval at full price.

   This keeps the no-refund policy and still means nobody pays twice. *Recommend: yes.* Alternatives: issue a negative invoice (a credit note), or carry the credit forward into future renewals. Both need a credit concept that doesn't exist today.
4. **Net amount exactly zero** (for example, two plans with the same price): apply it immediately with no invoice and return `None`. *Recommend: yes.*

**Interval switches**

5. If the interval stays the same, the billing anchor stays the same: `period_start`/`period_end` don't move. If the interval changes and the change happens immediately, a new full period of the new interval starts today. It is charged at the full new price minus the credit for unused days of the old period. Example: monthly→annual on day 10 gives a new year starting today, at the annual price minus the unused monthly days. *Recommend: yes.*
6. Under rule 3, annual→monthly will almost always be scheduled for the end of the annual period. *OK?*

**Scheduled (deferred) changes**

7. A subscription has at most one scheduled change, and a new `change_plan` call replaces it. Asking to go back to the current plan and interval while a change is scheduled cancels the scheduled change and returns `None`. Canceling the subscription drops any scheduled change. *Recommend: yes.*
8. **Should other code be able to see a scheduled change** on the `Subscription`, for example to show "switches to Basic on Mar 15"? *Recommend: yes, readable as the target plan, the target interval and the effective date.*

**Edge cases and errors**

9. **During a trial:** switch the plan and/or interval immediately, bill nothing, return `None`, and leave the trial end date unchanged. The first paid period is billed on the new plan. *Recommend: yes.*
10. **A renewal is outstanding** (`period_end <= today` but `renew_due` hasn't run yet): raise `InvalidPlanChange`. The current period is over, so there's nothing to prorate against. *Recommend: yes.* The alternative is for `change_plan` to run the renewal first, but then one call would produce two invoices.
11. **Errors:**
    - Unknown subscription → `SubscriptionNotFound`.
    - Canceled subscription → `SubscriptionNotActive`.
    - Unknown plan → `PlanNotFound`.
    - Retired target plan → `PlanNotAvailable`.
    - Same plan and same interval with nothing scheduled → `InvalidPlanChange`.

    *Recommend: yes.*
12. **Retired current plan, interval-only switch** (for example, a customer on retired "basic" asks to go monthly→annual): I'd treat it as a new sale and raise `PlanNotAvailable`. Customers can stay where they are or move to an active plan. *Recommend: reject.* Do you agree?

**Proposed non-goals:** credit balances, refunds and credit notes; seats/quantities; coupons and taxes; changes scheduled for an arbitrary future date; changing trial length; changing plan prices; customer notifications; concurrency and locking.

13. Is anything missing from that list, or anything on it that should be in scope?

### [spec] user

Answers by number:
1. Yes.
2. Yes. Your example is right.
3. No, change this. Upgrade vs downgrade is decided by the plans' monthly list price (whichever interval the customer is on or moving to), not by net amount. A more expensive plan is an upgrade: applies today, with the prorated invoice. A cheaper plan is a downgrade: always waits for period end, nothing billed, change_plan returns None, and the renewal bills the cheaper plan at full price. This holds even when the downgrade comes with a switch to annual.
4. Don't mind how you handle two different plans with the same monthly price. Drop the 'net amount' logic though.
5. No, change this. Switching interval on the same plan is neither upgrade nor downgrade, and it always waits for the period end, in both directions. Nothing is billed at the request; the renewal starts a period of the new interval at that interval's full price. We never refund unused annual time, so no new period starting today. If an upgrade comes together with an interval switch, split it: the upgrade happens now, prorated at the prices of the current interval, and the interval switch is scheduled for the period end.
6. Yes, annual->monthly is always scheduled for period end.
7. Yes. Asking for the current plan and interval while something is scheduled cancels it and returns None. Also, a request that upgrades now discards whatever was scheduled (unless that same request schedules an interval switch). The scheduled change has not happened yet, so an upgrade requested while a downgrade is scheduled is prorated from the current plan, not the scheduled one.
8. Don't mind, store it however suits you.
9. Yes, with one clarification: any change in a trial (up, down or interval) applies immediately, no invoice, returns None, trial end doesn't move. At trial end the customer is billed the full price of the plan and interval they are on by then.
10. Don't mind, your recommendation is fine.
11. Yes.
12. Don't mind, your recommendation is fine.
13. The list is fine, nothing to add.

### [spec] agent

Thanks, that changes things a lot. I'll treat price comparison and interval switching as two separate decisions. Two cases your rules don't settle yet, both involving money:

14. **The prices of a plan pair can point in opposite directions.** Upgrades are classified by monthly price but prorated at the current interval's prices. Suppose plan B costs more per month than plan A, but less per year (A: 10/100, B: 12/90). An annual customer moving A→B counts as an upgrade, yet the prorated invoice comes out negative. *Recommend:* still apply it today and issue the invoice even if it's negative. The rule stays simple and nobody pays twice. The alternative is to treat it as a downgrade and schedule it. Or is this a plan setup you'd prefer to rule out entirely?
15. **A scheduled target plan gets retired before the period ends.** *Recommend:* the change still takes effect at renewal. It was a valid sale when requested, and retired plans keep renewing for the customers on them.

Also, for plans with the same monthly price (which you left to me): I'll handle them like a downgrade, so the change is scheduled and nothing is billed. That way no money moves for a change that isn't a real upgrade.

### [spec] user

14. My rules classify by monthly price and prorate at the current interval's prices, and I have no special rule for the opposite-direction case. Your recommendation fits that: apply it today and issue the invoice, even if it's negative. I don't plan to rule that plan setup out.
15. Haven't thought about it, so I don't mind. Your recommendation is fine.

For same-monthly-price plans, treating them like a downgrade is fine by me.

### [spec] agent

The spec is written to `SPEC.md`. It describes behaviour and acceptance criteria only; no code has been written or changed, and nothing is committed.

The interface you fixed is copied in verbatim. The rest of the spec covers:
- **Terms:** upgrade, downgrade, interval switch, unused fraction and scheduled change.
- **Behaviour:** one section per case (upgrade, downgrade, same-plan interval switch, re-requesting the current plan, scheduled changes, trials), plus an error table.
- **Acceptance criteria:** 27 checkable statements with exact amounts. I computed the amounts from the existing fixtures plus a third plan, `team` (50/500).
- **Non-goals:** your list as agreed, plus one item covering the scheduled change.

Decisions you left to me, now written into the spec:
- **Same monthly price:** a change between two plans with the same monthly price is treated as a downgrade. It's scheduled for period end and nothing is billed.
- **Outstanding renewal:** if `period_end <= today` and `renew_due` hasn't run yet, `change_plan` raises `InvalidPlanChange`.
- **Retired current plan:** switching interval on it raises `PlanNotAvailable`. Moving to an active plan is still allowed. Asking for the current plan and interval still cancels a scheduled change.
- **Retired target plan:** a scheduled change still takes effect even if its target plan is retired before the period ends.
- **Where scheduled changes live:** they must be held in the store, not in the service. Criterion 19 checks this by building a new `BillingService` over the same store. There's no requirement to expose the scheduled change to other code.

Three things I added that you didn't explicitly state:
- A request that raises an error leaves the store unchanged.
- When a request fails for several reasons at once, which error comes first is left unspecified.
- `InvalidPlanChange` is also exported from the `billing` package, like the other errors.

### [build] operator

Build what SPEC.md describes. Done means the test suite passes and the spec's criteria are covered; report the command and its output.

### [build] agent

Plan changes in the middle of a period now work as SPEC.md describes, and the full test suite passes.

```
$ python3 -m pytest -q
....................................................................     [100%]
68 passed in 0.02s
```

That's the 20 tests that were already there, all unchanged and passing, plus 48 new ones in `tests/test_change_plan.py`, with at least one test for each of the 27 acceptance criteria.

**How it works**
- **New error:** `InvalidPlanChange(BillingError)` is in `errors.py` and is exported from `billing`.
- **Scheduled changes:** a new `ScheduledChange(plan_code, interval)` in `subscriptions.py` holds a change that waits for the period end. It's kept in `InMemoryStore` with three methods to set, read and clear it, so a new `BillingService` built over the same store still applies it.
- **`change_plan`** in `service.py` runs every check before it writes anything, so a request that fails leaves the store exactly as it was. Then:
  - Asking for the current plan and interval cancels a scheduled change, or raises `InvalidPlanChange` if nothing is scheduled.
  - During a trial, any change applies at once and nothing is billed.
  - A downgrade, or an interval switch on the same plan, is scheduled for the period end.
  - An upgrade switches plan today and issues an invoice with two lines: a credit for the old plan and a charge for the new one. Both are prorated at the current interval's prices and each is rounded once to cents. If the request also switches interval, that switch is scheduled for the period end.
- **Renewal** applies any scheduled change first, then clears it. When several missed periods are caught up, the change applies to the first one and every later period bills the new plan and interval.
- **Cancel** drops any scheduled change.

**Other changes**
- I added the `team` plan to the shared test fixture, as the spec's fixtures require.
- I updated the README's file layout to mention the new pieces.

Nothing is committed.
