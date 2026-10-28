### [grill] operator

/grill-with-docs Customers can't change plan right now: support has to cancel and resubscribe them by hand.
Add mid-cycle plan changes to the billing package: upgrades and downgrades, optionally
switching between monthly and annual billing, prorated so nobody pays twice for the same days.

Interface (other code will call exactly this):
- `BillingService.change_plan(subscription_id: str, new_plan_code: str, new_interval: Interval | None = None) -> Invoice | None`
  in `src/billing/service.py`. `new_interval=None` keeps the subscription's current interval.
- Return the invoice issued for the change (recorded in the store like every other invoice),
  or `None` when nothing is billed at the moment of the request.
- Add `InvalidPlanChange(BillingError)` to `src/billing/errors.py` for change requests that
  can't be honoured; keep using the existing error classes where they already fit.

### [grill] agent

I've read the whole package. It has no `GLOSSARY.md` or ADRs yet, and I'll create them once terms and decisions are settled. Some facts from the code shape the questions below:

- Periods are half-open `[period_start, period_end)`. A renewal is billed on `period_end`, and `renew_due` catches up missed periods.
- `Invoice` allows negative lines and a negative total. There's no customer credit balance anywhere.
- Retired plans can't be sold, but customers already on one keep renewing on it.
- A trialing subscription's current period is the free trial, and it has no invoice.

Round 1 covers the decisions everything else depends on.

---

❓ **Q1** - **When a change takes effect**: Should every plan change (upgrade, downgrade or interval switch) take effect **today**, with the unused part of the current period credited and the new plan charged?

The alternative is the common "upgrades now, downgrades at the end of the period" pattern. That needs a scheduled change stored on `Subscription`, `renew_due` would have to apply it, and you'd need a rule for what counts as a "downgrade". Comparing a monthly price with an annual price makes that rule unclear. Your brief asks for downgrades to be prorated too, which points to applying them immediately.

➡️ Yes. Every change applies today. We never need to sort changes into "upgrade" or "downgrade", because the proration math handles both directions the same way.

---

❓ **Q2** - **How proration is measured**: Should proration use calendar days, with the fraction = `(period_end − today) / (period_end − period_start)` and today counted as **unused**? Each line would be rounded to cents (half up) on its own.

Example: a Basic monthly subscription runs Jan 15 to Feb 15 (31 days) and moves to Pro on Jan 25. That leaves 21 unused days, so the credit is 10.00 × 21/31 = −6.77.

➡️ Yes. Count calendar days and treat the change day as the first day on the new plan.

---

❓ **Q3** - **Changes during a trial**: Should a `TRIALING` subscription simply switch to the new plan and/or interval, keep its trial end date, have nothing billed, and return `None`? The first paid period would then be billed at trial end on the new plan through the normal `renew_due`.

➡️ Yes.

---

❓ **Q4** - **Requests that are rejected**: Do you accept this error mapping?

- Unknown subscription → `SubscriptionNotFound`. Canceled subscription → `SubscriptionNotActive`.
- Unknown target plan → `PlanNotFound`. Retired target plan → `PlanNotAvailable`.
- Same plan **and** same interval (a no-op) → `InvalidPlanChange`.
- Same plan with a different interval (e.g. Pro monthly → Pro annual) → allowed, treated as an interval switch.
- A customer on a **retired** plan who only wants to switch interval → `PlanNotAvailable`. Their current terms can keep renewing, but the plan isn't sold on new terms.

➡️ Yes to all.

---

❓ **Q5** - **Subscription with an unbilled ended period**: Suppose `period_end <= today` because `renew_due` hasn't run yet, so the customer is in a period that hasn't been billed. Should `change_plan` reject this with `InvalidPlanChange` ("renew first")?

The other option is for `change_plan` to catch up the renewals itself first. That would issue extra invoices that the caller never sees in the return value. It would also bill a full period at the old price only to credit it straight back when the change happens on the renewal day.

➡️ Yes, reject it. This keeps `change_plan` limited to the current, already-billed period, and the renewal job stays the only thing that bills new periods.

### [grill] user

Q1: No, that's not right. Upgrade vs downgrade is decided by the plans' monthly list price, whichever interval the customer is on or moving to. Switching interval on the same plan is neither.
- Upgrades apply today and are prorated.
- Downgrades and monthly/annual switches wait for the end of the period. Nothing is billed, refunded or credited at the request, and change_plan returns None. The renewal on the period end moves them to the new plan/interval and bills its full price.
- An upgrade combined with an interval switch is split: the upgrade happens now, prorated at the current interval's prices, and the interval switch waits for the period end.
- Only one scheduled change at a time; each new request replaces it.

Q2: Yes. Calendar days, change day counts as the first day on the new plan, each line computed exactly and rounded half-up on its own.

Q3: Yes. In a trial any change applies immediately, nothing billed, returns None, trial end date unchanged.

Q4: Mostly yes, with one correction. Asking for the plan and interval they already have: if something is scheduled, it cancels it (returns None, nothing billed, renewal continues on the current plan); if nothing is scheduled, raise InvalidPlanChange. Customers on a retired plan can move off it like anyone else. For the retired-plan interval switch, I don't mind your choice. Other mappings are fine.

Q5: I don't mind, go with your recommendation.

### [grill] agent

I've added the settled terms (Upgrade, Downgrade, Interval switch, Scheduled change, Proration, and the existing core terms) to a new `GLOSSARY.md`.

**Decided from your answers, no question needed:**
- **Unbilled ended period (Q5):** if `period_end <= today`, `change_plan` raises `InvalidPlanChange`. This applies to a trial whose end has passed too.
- **Retired-plan interval switch (Q4):** this raises `PlanNotAvailable`. The rule is that the target plan must be active, except for a request for the current plan and interval, which only cancels the scheduled change.
- **Billing period on an upgrade:** the dates stay the same. The upgrade is prorated over `[today, period_end)`, and the renewal date doesn't move.

Your answers create some new edge cases:

---

❓ **Q6** - **Different plan, same monthly list price**: Say "Team" and "Pro" both cost 30.00/month. Should a change between them count as a **downgrade**: a scheduled change, nothing billed now, returns `None`?

The other options are to treat it as an upgrade (applied now, prorated) or to reject it.

➡️ Yes, treat it as a downgrade. Only a strictly higher monthly price makes something an upgrade, so equal prices never trigger a charge mid-period.

---

❓ **Q7** - **An upgrade that prorates to zero or less**: Upgrades are classified by the monthly price but prorated at the current interval's prices. So an annual customer can "upgrade" to a plan with a higher monthly price but an equal or lower annual price. For example, Pro is 30/month and 300/year, and Plus is 35/month and 280/year. The proration nets to ≤ 0.

Should we still issue the invoice exactly as calculated? Its total could be zero or negative (an `Invoice` allows that), and the plan change still applies today.

➡️ Yes, issue it as calculated. This keeps the rule "nobody pays twice". The other choices are to clamp the charge to zero, which overcharges the customer, or to reject the change, which blocks a legitimate upgrade because of how the price list happens to be set up.

---

❓ **Q8** - **Which plan a request is compared to**: Suppose a downgrade from Pro to Basic is scheduled and the customer then asks for "Plus". Should upgrade vs downgrade be decided against the plan they're **currently billed on** (Pro), not the scheduled one (Basic)?

It follows from "each new request replaces it" that an upgrade with no interval switch **clears** any scheduled change. An upgrade combined with an interval switch replaces the scheduled change with (new plan, new interval).

➡️ Yes to both. Compare against the current plan. Every request leaves either no scheduled change or exactly the one it implies.

---

❓ **Q9** - **Scheduled plan retired before the renewal**: Suppose a customer schedules a downgrade to Basic, and Basic is retired before their period ends. Should the renewal still move them to Basic and bill its price?

➡️ Yes. The sale happened when the request was accepted, and retired plans keep billing the customers already committed to them. The renewal job shouldn't fail or quietly ignore a change the customer was told about.

---

❓ **Q10** - **ADR for the change-timing rule**: Should I write `docs/adr/0001-plan-change-timing.md`? It would record that the monthly list price alone decides upgrade vs downgrade, that only upgrades apply immediately and are prorated, and that downgrades and interval switches wait for the renewal with no credits.

This meets all three ADR criteria:
- **Hard to reverse:** customers will be told their renewal date and how they're billed.
- **Surprising:** an annual customer is classified by the *monthly* price.
- **A real trade-off:** the alternative was prorating changes in both directions immediately.

➡️ Yes.

### [grill] user

Q6: Fine with me; any sensible choice works for equal monthly prices.

Q7: Yes, issue it as calculated. The two lines are always computed as described and the plan change still applies today.

Q8: Yes to both. Compare against the plan they're currently on. Each request leaves either nothing scheduled or only what that request itself implies.

Q9: I don't mind, go with your recommendation.

Q10: Fine, write the ADR.

### [grill] agent

I've written `docs/adr/0001-plan-change-timing.md`. I also changed the **Downgrade** entry in `GLOSSARY.md` to "a different plan with a lower or equal monthly list price", following your answer to Q6.

There are no open questions left. Here's the full design for `change_plan(subscription_id, new_plan_code, new_interval=None)`; please confirm it's right before I build anything.

**Validation, in order**
1. Unknown subscription → `SubscriptionNotFound`. Canceled subscription → `SubscriptionNotActive`.
2. Unknown plan → `PlanNotFound`.
3. Current period has ended but isn't billed yet (`period_end <= today`, trials included) → `InvalidPlanChange`.
4. Same plan **and** same interval as now:
   - if a change is scheduled, cancel it and return `None`;
   - otherwise raise `InvalidPlanChange`.
5. Target plan is retired → `PlanNotAvailable`. This includes switching interval on a retired current plan.

**Trialing subscription**
- The plan and/or interval change today.
- The trial end date doesn't change, nothing is billed, and the call returns `None`.

**Active subscription.** Upgrade vs downgrade is decided against the plan the customer is on now, using monthly list prices:
- **Upgrade** (new plan's monthly price is strictly higher):
  - The plan changes today, and the billing period dates stay the same.
  - The call issues an invoice dated today with two lines, priced at the current interval's prices:
    - a negative line for the old plan's unused days `[today, period_end)`;
    - a positive line for the new plan over the same days.
  - Each line is the exact fraction (days left ÷ days in the period) rounded half-up on its own.
  - The invoice is issued as calculated even if its total is zero or negative.
  - If the request also switches interval, the scheduled change becomes (new plan, new interval). Otherwise any scheduled change is cleared.
  - The call returns the invoice.
- **Downgrade** (lower or equal monthly price, different plan) and/or **interval switch**:
  - The scheduled change becomes (target plan, target interval), replacing any earlier one.
  - Nothing is billed, and the call returns `None`.

**Renewal**
- The next renewal in `renew_due` applies the scheduled change.
- The new period runs from the old `period_end` for the length of the new interval and is billed at the new plan's full price. The scheduled change is then cleared.
- This still happens if the scheduled plan was retired in the meantime.
- If several periods are being caught up, the change applies only to the first renewal.

**Implementation shape**
- `Subscription` gets optional `scheduled_plan_code` and `scheduled_interval` fields, so callers can show "moving to X on `period_end`".
- `InvalidPlanChange(BillingError)` goes in `errors.py` and is exported from `billing/__init__.py`.
- Everything is covered by tests in `tests/test_service.py`.

Shall I go ahead and build this?

### [grill] user

The design matches what I want, nothing to correct. Don't build anything yet: this stage is only the interview, and I'll start the next steps myself.

### [grill] agent

Understood, I won't build anything; the interview is finished and the design is agreed.

The only files I changed are two docs, neither committed yet:

- **`GLOSSARY.md`** (new): defines Plan change, Upgrade, Downgrade, Interval switch, Scheduled change and Proration, plus the existing core billing terms.
- **`docs/adr/0001-plan-change-timing.md`** (new): records that only upgrades apply immediately, why the monthly list price is the yardstick even for annual customers, and the rejected alternatives.

The confirmed design itself, from validation order down to the new `Subscription` fields, exists only in my previous message. If you want it saved for the next steps, the repo's convention is `.scratch/plan-changes/spec.md`; I can write it there if you ask.

### [to-spec] operator

/to-spec

### [to-spec] agent

Before I write the spec, please confirm the test seam.

**Proposed seam: just one, and it already exists.** It's the public `BillingService` interface, wired to the real `InMemoryStore` and a `FixedClock`, which is how `tests/test_service.py` already works today.

- **Inputs:**
  - `subscribe` to set up trialing and active subscriptions;
  - `clock.move_to` to choose the day of the change;
  - `store.retire_plan` for retired plans;
  - `change_plan`;
  - `renew_due` to apply a scheduled change at renewal.
- **What tests check:**
  - the return value of `change_plan`, which is an invoice or `None`;
  - which error is raised;
  - the subscription read back from the store: its plan, interval, period dates and scheduled change;
  - the invoices recorded for it, including their dates, line amounts and totals.

**No new seams.** The proration math and the upgrade/downgrade classification would stay private to `BillingService`. Rounding and day counting are tested through `change_plan` invoices, using fixture plans and dates that give known amounts. Examples are Basic monthly Jan 15 to Feb 15 changing to Pro on Jan 25, an annual period that includes Feb 29, and a pair of plans whose annual prices are inverted.

Does that match what you expect? Once you confirm, I'll write the spec to `.scratch/plan-changes/spec.md` with `Status: ready-for-agent`.

### [to-spec] user

Yes, that matches what I expect. Go ahead and write the spec.

### [to-spec] agent

I've written the spec to `.scratch/plan-changes/spec.md` and marked it `Status: ready-for-agent`. It isn't committed, and no code has changed.

It covers:
- **42 user stories:** upgrades, downgrades, interval switches, the split upgrade-plus-interval-switch case, scheduled-change replacement and cancellation, trials, retired plans, errors and catch-up renewals.
- **Implementation decisions:** the `change_plan` contract, the new `InvalidPlanChange` error, the order of validation checks, how upgrade vs downgrade is decided, the proration formula and rounding, the two new optional scheduled-change fields on the subscription, and how `renew_due` applies a scheduled change.
- **Testing decisions:** the single `BillingService` seam you approved, with a worked example to test against. Basic monthly Jan 15–Feb 15 upgraded to Pro on Jan 25 gives a credit of −6.77, a charge of 20.32 and a total of 13.55.

It uses the terms from `GLOSSARY.md` and refers to ADR-0001 for why only upgrades apply immediately.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here's my proposed breakdown into four tickets. The package is small and `BillingService` is already easy to extend, so I don't think a prefactoring ticket is needed.

1. **Prorated upgrade for active subscriptions**
   - **Blocked by:** none, can start immediately.
   - **What it delivers:** `change_plan` and `InvalidPlanChange` exist (the error is exported). An active subscription moving to a plan with a higher monthly list price changes plan today, keeps its billing period, and gets a two-line proration invoice. The invoice is recorded, dated today and returned, and is issued even when the total is zero or negative.
   - **Validation in this ticket:** unknown subscription, canceled subscription, unknown plan, retired target plan, an ended period that hasn't been renewed, and asking for the current plan and interval.
   - **Also:** the README mentions the new operation.

2. **Scheduled downgrades and interval switches, applied at renewal**
   - **Blocked by:** 01.
   - **What it delivers:**
     - A downgrade (including a different plan at the same monthly price) or an interval switch becomes the subscription's scheduled change. It's visible on the subscription, nothing is billed, and the call returns `None`.
     - `renew_due` applies the scheduled change: a full new period of the scheduled interval, billed at full price. It still applies if the plan was retired in the meantime, and only on the first of several catch-up renewals.
     - A new request replaces the scheduled change. Asking for the current plan and interval cancels it.
     - A plan change request on a retired current plan that only switches interval → `PlanNotAvailable`.

3. **Upgrade combined with an interval switch, and upgrades replacing a scheduled change**
   - **Blocked by:** 01, 02.
   - **What it delivers:**
     - An upgrade that also asks for a new interval is prorated at the current interval now, and the scheduled change becomes (new plan, new interval).
     - A plain upgrade clears any scheduled change.
     - Upgrade vs downgrade is always judged against the current plan, never the scheduled one.

4. **Plan changes during a trial**
   - **Blocked by:** 01. It can run in parallel with 02 and 03.
   - **What it delivers:**
     - A trialing subscription moves to the requested plan and/or interval immediately. Nothing is billed, the call returns `None`, and the trial end is unchanged.
     - At trial end, the first paid period is billed on the new plan and interval.
     - The same validation applies as for active subscriptions, including rejecting a trial whose end has passed but hasn't been renewed.

Questions for you:
- Does this granularity feel right? Tickets 02 and 03 could be merged, since 03 is fairly small. I kept 03 separate so the split upgrade-plus-interval-switch case gets its own focused tests.
- Are the blocking edges right? In particular, can 04 depend on 01 only?
- Should any ticket be merged or split further?

### [to-tickets] user

The breakdown looks right to me, and I don't see anything that contradicts what I want. Keep 02 and 03 separate, since the split upgrade-plus-interval-switch case deserves its own tests. 04 depending only on 01 is fine. I wouldn't merge or split anything further. Go ahead and write the tickets.

### [to-tickets] agent

I've written the four tickets under `.scratch/plan-changes/issues/`, one file each, all marked `ready-for-agent`. They aren't committed. I left the spec unchanged.

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Prorated upgrade for active subscriptions | none (can start now) |
| 02 | Scheduled downgrades and interval switches, applied at renewal | 01 |
| 03 | Upgrade combined with an interval switch, and upgrades replacing a scheduled change | 01, 02 |
| 04 | Plan changes during a trial | 01 |

Each ticket has acceptance criteria tied to concrete scenarios, all tested through the public `BillingService` interface. The worked example (Basic → Pro on Jan 25 gives −6.77 / 20.32) appears in both 01 and 03, so the expected amounts are the same in each.

You can start with 01. Once it's done, 02 and 04 can run in parallel, and 03 follows 02.

### [implement-spec] operator

/implement-spec .scratch/plan-changes/spec.md

### [implement-spec] agent

The whole spec is built on the integration branch `plan-changes` (ffa153c, 15 commits ahead of `main`), and all 74 tests pass. That's the 20 original tests plus 54 new ones, all going through `BillingService`. Nothing is pushed and there's no PR, because this repo's tracker is the local markdown files.

**Tickets** (01 first, then 02 and 04 in parallel, then 03):
- **01 (upgrade):** `change_plan` with the validation checks in the spec's order, and the new `InvalidPlanChange` error. An upgrade issues a prorated invoice today; the Jan 25 example gives −6.77 / 20.32, total 13.55.
- **02 (downgrades and interval switches):** these become a scheduled change that the next renewal applies. It still applies if the plan was retired in the meantime, and only the first renewal applies it when several missed renewals are caught up. Asking for the current plan and interval cancels a scheduled change.
- **03 (upgrade with an interval switch):** the upgrade happens now and the interval switch waits for the renewal. A plain upgrade drops any scheduled change.
- **04 (trials):** a change during a trial applies immediately, with nothing billed and the trial end unchanged.

**Code review:** the spec review found nothing missing or wrong. One implementer fixed these findings:
- The README paragraph was wrong about trials; it now says changes during a trial apply immediately.
- A change during a trial now also clears any scheduled change.
- Some code tidying.
- A new test that checks the proration line descriptions.

I left one suggestion out on purpose: bundling the two scheduled-change fields into one type, because the spec asks for two separate optional fields.

**Tracker:** the spec and all four tickets are marked resolved, with their acceptance boxes ticked and a comment pointing to the commits. The subagent worktrees and ticket branches are removed; only `main` and `plan-changes` remain.

**Decision for you:** ADR-0001 says "only upgrades take effect immediately; everything else waits for the renewal", and the GLOSSARY entries for downgrade and interval switch say the same. Neither mentions that trials are an exception, though the spec requires it. The spec says both files are up to date, and they aren't committed to the repo, so I didn't edit them. You may want to add a sentence about trials.
