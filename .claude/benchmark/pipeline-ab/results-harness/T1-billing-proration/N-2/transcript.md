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

I've read the whole package. There's no `GLOSSARY.md`, no ADRs and no `specs/` yet, so I'll create them as part of this work. Per CLAUDE.md, this change needs an interview before I write the spec. These are the decisions I can't take from the code. Each has my recommendation, so you can answer "all as recommended except N".

**1. How proration is calculated.** I'd prorate by calendar day over the length of the current period (Jan 15 → Feb 15 is 31 days). The day of the change counts toward the new plan, which matches the half-open periods.
- A **credit** line for the old plan: `−old_price × days_left / period_days`
- A **charge** line for the new plan: `new_price × days_left / period_days`
- Each line is rounded half-up to cents on its own.

This also stays correct for several changes in one period, because the credit uses the same rate the customer was charged.

**2. Switching between monthly and annual.** I'd start a new period today: credit the unused part of the old plan and charge the full price of the new interval. The usual alternative is to keep the old period end, but that doesn't work for monthly → annual. Same-interval changes keep the current period.

**3. Downgrades: this is the main decision.** When the credit is bigger than the charge (for example annual Pro → monthly Basic), the options are:
- **(a)** Apply it now and issue an invoice with a negative total, a credit note that someone settles or refunds outside this package. **Recommended:** it's the simplest option and needs no new concepts.
- **(b)** Schedule the downgrade for the end of the period and bill nothing now, so `change_plan` returns `None`. This needs a "pending change" field on `Subscription`, and `renew_due` would apply it.
- **(c)** Apply it now and keep the credit as a balance that reduces later invoices. This adds an account-balance concept the package doesn't have yet.

Your note that the method returns `None` "when nothing is billed at the moment of the request" made me wonder whether you meant (b).

**4. Changes during a free trial.** I'd switch the plan and interval right away, keep the trial end date, bill nothing and return `None`.

**5. Requests that get rejected:**
- Canceled subscription → `SubscriptionNotActive`
- Unknown plan → `PlanNotFound`
- Retired target plan → `PlanNotAvailable`. This includes a customer on a retired plan who only wants to switch interval, which I'd treat as a new sale.
- Same plan and same interval → `InvalidPlanChange`
- A renewal is already due but `renew_due` hasn't run yet (today ≥ `period_end`) → `InvalidPlanChange`. The alternative is to run the renewal first, but then one call would issue two invoices.

**6. Where the decision is recorded.** The proration policy (1–3) goes in `docs/adr/0001-plan-change-proration.md`. The terms *proration*, *credit line* and *plan change* go in `GLOSSARY.md`.

Once you've answered, I'll write `specs/plan-change.md` with your interface copied verbatim, then build it with tests in this session. I expect it to fit in one session.

### [build] user

Answers by number:

1. Mostly right, with two corrections. Remaining days run from the change date, inclusive, to the period end, exclusive. Period days are real calendar days: 28-31 for a month, 365 or 366 for a year. Compute each line exactly as price x remaining days / period days, with no rounded daily rate in between. Round each line half-up to cents on its own. The total is the sum of the two rounded lines. Example: Pro -> Premium on Mar 11 in a Mar 1-Apr 1 period gives 21/31 left, lines -20.32 and +50.81, total 30.49. The upgrade happens right away, and the billing period doesn't move. The next renewal bills the new plan at full price.

2. Not as recommended. Switching between monthly and annual never starts a new period now, and we never refund unused annual time. The switch waits for the period end. Nothing is billed at the request. The renewal on the period end starts a period of the new interval and bills that interval's full price. If an upgrade comes with an interval switch, split it. The upgrade happens now, prorated at the current interval's prices. The interval switch happens at the period end.

3. Option (b), but wider than a downgrade. Upgrade versus downgrade is decided by the plans' monthly list price, whatever interval the customer is on or moving to. A cheaper plan is a downgrade. Downgrades wait for the end of the period. Nothing is billed, refunded or credited at the request. `change_plan` returns `None` and no invoice is recorded. The customer keeps the current plan until the period end, and the renewal moves them to the cheaper plan and bills its full price. This includes a downgrade combined with a switch to annual. Switching interval on the same plan is neither an upgrade nor a downgrade. There are no negative-total invoices and no balances.

Only one scheduled change exists at a time. Each request states the full target (plan and interval) and replaces whatever was scheduled before. An upgrade that applies now also discards anything scheduled, unless the same request schedules an interval switch. A scheduled change hasn't happened yet, so an upgrade requested while a downgrade is scheduled is prorated from the current plan. Example: on Pro, Basic scheduled on Mar 5, then Premium requested on Mar 11 gives an invoice of 30.49.

4. Almost right. During a trial, any change (up, down or interval) applies immediately in full. There is no proration, `change_plan` returns `None`, and no invoice is issued. The trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they are on by then.

5. Mostly agreed, with these differences:
- Canceled subscription: `SubscriptionNotActive`. Agreed.
- Unknown plan: `PlanNotFound`. Agreed.
- Retired target plan: `PlanNotAvailable`. Agreed. Customers on a retired plan may move off it like anyone else.
- Same plan and same interval: if a change is scheduled, this cancels it. It returns `None`, nothing is billed, and the renewal continues on the current plan. If nothing is scheduled, raise `InvalidPlanChange`.
- Requests on or after `period_end` before the renewal has run: I don't mind. Your `InvalidPlanChange` is fine.
- Any rejected request changes nothing: no invoice, and the subscription is untouched.

6. Fine. Put the glossary terms and the ADR where you proposed. Add the terms you settle, such as scheduled change, upgrade and downgrade.

Go ahead and write the spec, then build it.

### [build] agent

Plan changes are built as you specified, and `python3 -m pytest -q` exits 0:

```
$ python3 -m pytest -q
.....................................................                    [100%]
53 passed in 0.02s
exit=0
```

That's the 20 existing tests plus 33 new ones in `tests/test_plan_change.py`. The new tests were written first and all failed before I implemented anything. Your two worked examples come out exactly: 30.49 for Pro → Premium on Mar 11, and 30.49 when Basic was scheduled on Mar 5.

**What changed**
- **`change_plan`** in `src/billing/service.py` follows the interface you fixed.
  - Upgrades are invoiced now as a credit line and a charge line.
  - Downgrades and interval switches are scheduled and return `None`.
  - An upgrade combined with an interval switch is split: the upgrade now, the switch at period end.
  - During a trial, any change applies immediately with no invoice.
  - Asking for the current plan and interval cancels a scheduled change.
  - Rejected requests leave the subscription and invoices untouched.
- **`renew_due`** now applies the scheduled change at the period end, starting a period of the new interval and billing its full price.
- **`Subscription`** has a new optional `scheduled_change` field. The production database-backed store will need to save it; nothing else about the store changes.
- **`InvalidPlanChange`** is in `errors.py` and exported from the package.
- **Docs:** the spec is in `specs/plan-change.md`, the decision record is `docs/adr/0001-plan-change-proration.md`, the new terms are in `GLOSSARY.md`, and the README is updated.

**Reviews**
- **Fresh-session review against the spec:** it found no spec violations, but it did find tests that couldn't fail on the bugs they were named for. I fixed them and checked one: I broke the code on purpose and the test caught it.
- **`/code-review`:** the one bug it reported (a `-0.00` credit line when upgrading from a free plan) turned out to be wrong. The other findings either don't apply to this code or were outside the spec. I made one small change from it: a plan change during a trial now explicitly clears any scheduled change.

**Decisions I made that you should confirm** (listed under "Implementer decisions" in the spec):
1. **Different plan, same monthly price:** treated like an interval switch, so it's scheduled for the period end.
2. **Upgrade on annual where the new plan's annual price is lower:** the prorated invoice would come out negative, so the request is rejected with `InvalidPlanChange`.
3. **Retired plans:** a customer on a retired plan can cancel a scheduled change. Switching interval on a retired plan is rejected, because it would sell that plan at a new interval.
4. **Scheduled plan retired before the renewal:** the change still happens. Availability is only checked when the customer makes the request.
5. **Upgrade where the two rounded lines cancel out:** a 0.00 invoice is issued and returned, not `None`.

Nothing is committed. Separately, `__pycache__/*.pyc` files are tracked in git and show up as modified; you may want them gitignored, but I haven't touched that.
