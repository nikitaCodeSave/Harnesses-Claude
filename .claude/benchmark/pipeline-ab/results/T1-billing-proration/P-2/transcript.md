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

I read the whole billing package (about 800 lines). Facts that matter for this design:

- There's no credit or account-balance concept. However, `LineItem` accepts negative amounts and `Invoice` doesn't check that its total is ≥ 0, so a credit line, or even a negative invoice, is technically possible today.
- Renewal is lazy. A subscription can sit past its `period_end` until `renew_due()` runs.
- A trial is stored as the current period with status `TRIALING`.
- There's no `GLOSSARY.md` and no `docs/adr/` yet. I'll create them as terms and decisions get settled.

Fixtures for the examples below: basic costs 10 a month or 100 a year, pro costs 30 a month or 300 a year, and today is 2026‑01‑15.

---

❓ **Q1** - **What happens when a change leaves the customer with money owed back to them?** Some changes are worth less than the unused part of what the customer already paid. For example, pro monthly → basic monthly halfway through the period, or pro annual → basic monthly in month 2 (about 250 of annual unused against a 10 charge). Options:
- (a) **Defer:** schedule the change to take effect on `period_end`. The customer keeps the current plan until then, nothing is billed now, and the method returns `None`. The renewal then bills the new plan and interval. This needs a "pending change" on the subscription.
- (b) **Credit note now:** apply the change immediately and issue an invoice with a negative total.
- (c) **Account credit:** apply immediately and carry a credit balance forward against future invoices. This adds a new concept and changes how renewals work.
- (d) **Forfeit:** apply immediately and refund nothing. The customer never pays twice for the same days, but they lose money.

➡️ (a). It's the only option that adds no money-moving concept. It fits the brief's "`None` when nothing is billed at the moment of the request", and it means downgrades never need refunds.

---

❓ **Q2** - **How should proration count time?** Prorate by actual days. The current period is `[period_start, period_end)`, and the remaining time is `[today, period_end)`. Unused credit is `old_price × remaining_days / period_days`, and the charge is calculated the same way with the new price. Each amount is rounded to cents with half-up rounding. Example: pro monthly bought Jan 15 and switched on Jan 25 has 21 of 31 days left, so the unused credit is 30 × 21/31 = 20.32.

➡️ Yes: actual days in the current period, with each amount rounded half-up on its own.

---

❓ **Q3** - **How should the change invoice be laid out?** One option is two lines: a negative "unused time on Basic (monthly) Jan 25 → Feb 15" credit and a positive "remaining time on Pro (monthly) Jan 25 → Feb 15" charge. The other is a single line for the net amount. Either way it's issued today and recorded with `_issue_invoice`.

➡️ Two lines. The customer can see they aren't paying twice, and the invoice total is still the net amount.

---

❓ **Q4** - **What happens to a change during a trial?** Nothing has been paid yet, so the change only swaps the plan and/or interval. The trial end date stays the same, nothing is billed, and the method returns `None`. The first paid period then bills the new plan.

➡️ Yes.

---

❓ **Q5** - **What happens if a renewal is overdue?** If `period_end <= today` and `renew_due()` hasn't billed the next period yet, the "current period" in the store is already over. Options:
- reject with `InvalidPlanChange` ("renewal pending")
- catch up the renewals inside `change_plan`, which issues extra invoices the return type can't report
- treat the change as starting at the next period

➡️ Reject with `InvalidPlanChange`. The caller runs `renew_due()` and tries again.

---

❓ **Q6** - **Which errors should each invalid request raise?**
- Unknown subscription → `SubscriptionNotFound` (raised by the store)
- Canceled subscription → `SubscriptionNotActive`
- Unknown target plan → `PlanNotFound`
- Retired target plan → `PlanNotAvailable`
- Same plan and same interval → `InvalidPlanChange`

Customers on a retired plan can still move *off* it, but can't move to a different interval on the same retired plan, because that counts as selling it again.

➡️ Yes to all of these, including blocking an interval switch on a retired plan.

---

The next round depends on Q1. If you choose deferral, I'll ask how to tell which changes apply now and which wait, what happens to a pending change when a second request comes in, and whether a monthly → annual switch starts a new year today.

### [grill] user

Q1: Deferral is right for downgrades, but draw the line differently from 'money owed back'. Upgrade vs downgrade is decided by the plans' monthly list price, whatever interval the customer is on or moving to. Upgrades apply right away with the same period dates, prorated per Q2/Q3; the next renewal bills the new plan in full. Any move to a cheaper plan waits for period end, including one combined with a switch to annual. Interval switches (monthly<->annual) always wait for period end too, in both directions; we never refund unused annual time. An upgrade combined with an interval switch is split: the upgrade happens now, prorated at the current interval's prices, and the interval switch happens at period end. Deferred changes bill nothing at the request and return None; the renewal moves the customer to the new plan/interval and bills its full price.

Q2: Yes. Remaining days count from the change date inclusive up to period end exclusive. Each line is computed exactly and rounded half-up on its own, with no daily rate in between.

Q3: Yes, two lines. Both use the prices of the interval the customer is currently on. The total is the sum of the two rounded lines; don't round the net difference instead.

Q4: Yes. Any change during a trial (up, down or interval) applies immediately, trial end date unchanged, returns None, no invoice. At trial end they're billed the full price of the plan and interval they're on by then.

Q5: I don't mind, rejecting with InvalidPlanChange is fine.

Q6: Errors are as you listed, with one correction on same plan and same interval. If a change is scheduled, the request cancels it: returns None, nothing billed, the renewal continues on the current plan. Only if nothing is scheduled, raise InvalidPlanChange. Switching interval on a retired plan: I don't mind, your proposal is fine. A rejected request must change nothing: no invoice, subscription untouched.

### [grill] agent

I've created `GLOSSARY.md` with the terms settled so far: Upgrade and Downgrade are defined by monthly list price, plus Interval switch, Scheduled change, Proration, Unused-time credit and Remaining-time charge, along with the core terms already used in the code.

Your answers raise these follow-ups. Fixtures: basic costs 10 a month or 100 a year, pro costs 30 a month or 300 a year.

---

❓ **Q7** - **What about a change between plans with the same monthly price?** Say "team" costs 30 a month or 270 a year, the same monthly price as pro. Moving pro → team is neither an upgrade nor a downgrade under your rule. Options:
- (a) treat it like a downgrade and schedule it for period end, so no money moves
- (b) apply it now, prorated like an upgrade, which means an annual customer gets a negative total (300 → 270)
- (c) reject it with `InvalidPlanChange`

➡️ (a). It becomes a scheduled change, nothing is billed, and the method returns `None`.

---

❓ **Q8** - **What if an upgrade nets zero or less at the customer's current interval?** Nothing stops a plan from having a higher monthly price but a lower annual one. For example, "plus" costs 12 a month or 90 a year. Basic annual → plus is an upgrade by your rule, but at annual prices the credit (100 × r) is bigger than the charge (90 × r). Options:
- (a) apply the upgrade now, issue no invoice and return `None` whenever the summed total is ≤ 0. Since we never refund, the leftover credit is simply dropped.
- (b) issue the invoice anyway, with a zero or negative total
- (c) handle it like a downgrade and schedule it

➡️ (a). This only happens when prices are set up strangely, and it keeps to "never refund". The rule also covers a total of exactly 0.00.

---

❓ **Q9** - **What happens when a request arrives while a change is already scheduled?** There's at most one scheduled change per subscription. Each new request is judged against the customer's *current* plan and interval, not the scheduled one, and it **replaces** whatever was scheduled. This applies whether the new request applies now or is scheduled itself. Your Q6 cancellation rule (same plan and same interval cancels what's scheduled) is a special case of this.

Two consequences:
- Pro monthly has a scheduled downgrade to basic, then the customer upgrades to enterprise. The upgrade applies now and the basic downgrade is dropped.
- Pro monthly has a scheduled switch to pro annual, then `change_plan(sub, "basic")` is called with `new_interval=None`. `None` means the *current* interval, so the scheduled change becomes basic monthly and the annual switch is lost.

➡️ Yes: the latest request wins outright, including in the second case.

---

❓ **Q10** - **What if a request matches the change that's already scheduled?** For example, basic is scheduled and basic is requested again.

➡️ Return `None` and change nothing; it isn't an error.

---

❓ **Q11** - **What if the plan a change is scheduled to gets retired before the renewal?** The plan was available when the customer asked for it.

➡️ Apply the change anyway at renewal. The sale happened when the request was accepted, which matches how customers already on a retired plan keep it.

---

❓ **Q12** - **Should a subscription show its scheduled change?** Other code will probably want to display something like "Switching to Basic (annual) on Feb 15". I'd add optional `scheduled_plan_code` and `scheduled_interval` fields to `Subscription`, both set or both `None`. The effective date is always `period_end`, so it doesn't need its own field.

➡️ Yes, add those two fields to `Subscription`.

---

❓ **Q13** - **How should repeated upgrades in one period, and free plans, be handled?** Two cases:
- Several upgrades in one period: each one credits the current plan's unused time and charges the new plan's remaining time. Basic → pro on Jan 25, then pro → enterprise on Feb 1, gives a second invoice that credits pro for Feb 1 → Feb 15.
- Upgrading from a free plan (price 0): the invoice still has both lines, including a `0.00` unused-time credit line.

➡️ Yes to both.

---

❓ **Q14** - **Should this policy be recorded as an ADR?** The rules are: downgrades and interval switches wait for the renewal, we never refund unused time, and upgrade vs downgrade is decided by monthly list price. This passes all three tests:
- It's hard to reverse, because customers see it in their invoices.
- A future reader will wonder why annual → monthly isn't prorated.
- There were real alternatives: credit notes, account credit, or classifying by net amount.

➡️ Yes. I'll write `docs/adr/0001-plan-changes-defer-downgrades-never-refund.md`.

### [grill] user

Q7: I don't mind, (a) is fine.
Q8: I don't mind, (a) is fine.
Q9: Yes, the latest request wins outright, including in the second case. An upgrade that applies now also discards anything scheduled, unless the same request itself schedules an interval switch.
Q10: Fine. The result is the same as replacing the scheduled change: return None, nothing billed.
Q11: I don't mind, applying it at renewal is fine.
Q12: I don't mind how it's stored, your two fields are fine.
Q13: Yes to both.
Q14: Fine, write the ADR.

### [grill] agent

I wrote the ADR (`docs/adr/0001-plan-changes-defer-downgrades-never-refund.md`) and added **Lateral change** (same monthly list price) to `GLOSSARY.md`. Every question now has an answer, so here is the full design for you to confirm. I haven't written any code yet.

**`change_plan(subscription_id, new_plan_code, new_interval=None)`**

1. **Checks that reject the request (nothing is changed):**
   - `SubscriptionNotFound` if the subscription doesn't exist.
   - `SubscriptionNotActive` if it's canceled.
   - `InvalidPlanChange` if `period_end <= today` (a renewal is overdue).
   - `PlanNotFound` if the target plan doesn't exist; `PlanNotAvailable` if it's retired. This includes switching interval on a retired plan you're already on.
   - `InvalidPlanChange` if the target is the same plan and interval and nothing is scheduled.
2. **Trial:** the plan and/or interval change immediately. The trial end date stays the same, no invoice is issued, and it returns `None`.
3. **Classification:** the new plan's monthly list price is compared with the *current* plan's.
   - **Upgrade** (higher) applies now and keeps the same period dates. The invoice is issued today with two lines at the current interval's prices:
     - credit: `−old_price × r / d`
     - charge: `+new_price × r / d`
     - `r` is the days from today (inclusive) to `period_end` (exclusive), and `d` is the length of the period.
     - Each line is rounded half-up on its own, and the total is the sum of the two lines.
     - If the total is ≤ 0, the upgrade still applies, but no invoice is issued and it returns `None`.
     - If the request also switches interval, that part becomes a scheduled change. Otherwise any existing scheduled change is discarded.
   - **Downgrade, lateral change, or a pure interval switch:** these become the scheduled change, nothing is billed, and it returns `None`.
4. **Scheduled change:**
   - A subscription has at most one, stored as `scheduled_plan_code` plus `scheduled_interval` on `Subscription`.
   - The latest request replaces whatever was scheduled.
   - A request for the same plan and interval cancels it.
   - At the next renewal, `renew_due` moves the subscription to the scheduled plan and interval. The new period is sized by the new interval and billed at full price, even if the plan was retired in the meantime.

**Tests** will cover each rule with the basic/pro fixtures, plus a "plus" plan (12 a month, 90 a year) for the case where an upgrade's credit exceeds its charge.

If this matches what you have in mind, I'll implement it test-first. I can also record it as a spec under `.scratch/` first.

### [to-spec] operator

/to-spec

### [to-spec] agent

Before I write the spec, here's how I plan to test it. The skill asks me to confirm this with you first.

**I'd test through a single existing entry point: `BillingService`'s public methods** (`subscribe`, `change_plan`, `renew_due`, `cancel`). Each test builds the service on `InMemoryStore` with `FixedClock`, which is how `tests/test_service.py` already works. Tests check three things:
- what `change_plan` returns (an `Invoice` or `None`, or which error it raises)
- the stored subscription after the change (plan, interval, period dates, and the scheduled change fields)
- the invoices recorded for the subscription (line amounts, total, issue date), including what a later `renew_due()` bills

That covers every rule we agreed. For example:
- moving the clock to period end and calling `renew_due()` shows a scheduled change being applied
- after a rejected request, the subscription is unchanged and there's no new invoice

**No new test seams.** The proration arithmetic would only be checked through the invoice lines, never through a separately tested helper. Domain-object tests stay in `tests/test_domain.py` and get only one addition: `Subscription` must have both scheduled fields set or neither.

Shall I go ahead with this and publish the spec to `.scratch/plan-changes/spec.md` as `ready-for-agent`?

### [to-spec] user

That test approach is fine, go ahead and publish the spec to `.scratch/plan-changes/spec.md` as `ready-for-agent`.

### [to-spec] agent

I've published the spec to `.scratch/plan-changes/spec.md` with `Status: ready-for-agent`. Nothing is committed yet. The repo has three new uncommitted files: the spec, `GLOSSARY.md`, and `docs/adr/0001-plan-changes-defer-downgrades-never-refund.md`.

The spec uses the glossary's terms and follows the ADR. It contains:
- **40 user stories**, written from the customer, support, finance and calling-developer side.
- **The full rule set:**
  - the order requests are checked in, with nothing changed when one is rejected
  - trial behaviour
  - upgrade vs downgrade by monthly list price
  - how upgrades are prorated: two lines rounded separately; a zero or negative total bills nothing and returns `None`
  - scheduled changes: the latest request wins, and asking for the current plan and interval cancels one
  - the two optional scheduled-change fields on `Subscription`
  - how renewal applies a scheduled change
- **Testing:** all tests go through `BillingService` with the in-memory store and the fixed clock, as we agreed. There's a list of cases to cover, including one built to catch rounding the net amount instead of the two lines: basic → pro on Feb 12 with 3 of 31 days left gives a credit of −0.97 and a charge of +2.90, total 1.93. Rounding the net would give 1.94.
- **Out of scope:** refunds or credit notes, account credit, catching up overdue renewals inside `change_plan`, seats and coupons, and notifying customers.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

I propose four tickets, all working through `BillingService` as the spec's testing section describes. I don't see any refactoring that needs to happen first: `_period_line`, `_issue_invoice` and `_renew` already give each slice a natural place to plug in.

1. **Upgrade with a prorated invoice**
   - **Blocked by:** none, can start immediately.
   - **What it delivers:** a working `change_plan` and `InvalidPlanChange`, with every rejection from the spec's validation list, each leaving the subscription and invoices untouched. The one exception is "same plan and interval while a change is scheduled", which belongs to ticket 3. It also covers same-interval upgrades on active subscriptions:
     - an invoice dated today with a credit line and a charge line, each rounded on its own, at the current interval's prices
     - period dates unchanged
     - a total of zero or less applies the plan and returns `None`
     - repeated upgrades in one period, and upgrades from a free plan
     - the next renewal bills the new plan in full
     - the README layout line updated

   Downgrades, lateral changes and interval switches are rejected with `InvalidPlanChange` until ticket 2 lands, so `main` never accepts a change it can't carry out.

2. **Downgrades, lateral changes and interval switches applied at renewal**
   - **Blocked by:** 01.
   - **What it delivers:**
     - the two scheduled-change fields on `Subscription` (both set or neither)
     - downgrades, lateral changes and pure interval switches (including a downgrade combined with switching to annual) stored as the scheduled change, with nothing billed and `None` returned
     - `renew_due` applying the change: new plan and interval, period length set by the new interval, full-price invoice
     - a scheduled plan that has since been retired still applied
     - during catch-up, the change applied to the first missed renewal only

3. **Replacing and cancelling a scheduled change, and splitting upgrades combined with an interval switch**
   - **Blocked by:** 02.
   - **What it delivers:**
     - the latest request wins, including `new_interval=None` dropping a scheduled interval switch
     - requesting the current plan and interval cancels the scheduled change
     - repeating the scheduled request changes nothing
     - an upgrade discards a scheduled change
     - an upgrade combined with an interval switch is prorated now, with the interval switch scheduled for renewal

4. **Plan changes during a trial**
   - **Blocked by:** 01.
   - **What it delivers:** any change made during a trial (upgrade, downgrade or interval switch) applies immediately, with no invoice, the trial end unchanged, and `None` returned. The renewal at trial end bills the plan and interval chosen.
   - **Note:** it can run alongside 02 and 03. Both 02 and 04 add branches to `change_plan`, so whichever lands second will have a small merge to resolve.

Questions:
- **Granularity:** ticket 4 is small. Should it be folded into 1, or kept separate so it can run in parallel?
- **Blocking edges:** is 01 → 02 → 03 with 04 off 01 right? I made 3 depend on 2 because the replacement rules need scheduled changes to exist. Splitting an upgrade combined with an interval switch also needs both upgrades and scheduling.
- **Merges or splits:** should 2 and 3 be merged? Together they're still small enough for one fresh context, but keeping them apart gives a smaller first cut of scheduled changes.

### [to-tickets] user

Keep ticket 4 separate so it can run in parallel. The blocking edges (01 -> 02 -> 03, with 04 off 01) look right to me. Keep 2 and 3 apart, so the first cut of scheduled changes stays smaller.

### [to-tickets] agent

I've published the four tickets you approved under `.scratch/plan-changes/issues/`, each marked `Status: ready-for-agent`:

| # | Ticket | Blocked by |
|---|--------|-----------|
| 01 | `01-upgrade-with-prorated-invoice.md`: the `change_plan` operation, `InvalidPlanChange`, all the checks that reject a request, prorated upgrades, and the README line | none |
| 02 | `02-scheduled-changes-at-renewal.md`: the scheduled-change fields, and downgrades, lateral changes and interval switches applied at renewal | 01 |
| 03 | `03-replace-cancel-scheduled-and-split-upgrades.md`: the latest request wins, cancelling a scheduled change, and an upgrade combined with an interval switch | 02 |
| 04 | `04-plan-changes-during-trial.md`: changes during a trial take effect immediately and bill nothing | 01 |

Tickets 01 and 04 can start right away, and 04 can run alongside 02 and 03.

Ticket 01 rejects downgrades, lateral changes and interval switches with `InvalidPlanChange` until 02 lands, so `main` never accepts a change it can't carry out.

Ticket 03 has one criterion that goes slightly beyond what we discussed. If an upgrade combined with an interval switch comes out to zero or less, the plan still changes and the interval switch is still scheduled, with nothing billed. That follows from your rules but wasn't stated as its own case.

The spec itself is unchanged, and nothing is committed yet.

### [implement-spec] operator

/implement-spec .scratch/plan-changes/spec.md

### [implement-spec] agent

The whole plan-changes spec is now built on the `plan-changes` branch, and all 72 tests pass. Nothing has been merged to `main` or pushed, and I didn't open a PR because your tracker is local files and you didn't ask for one.

**What the billing service can now do:**
- **New operation:** `change_plan(subscription_id, new_plan_code, new_interval=None)`. Requests it can't carry out raise a new `InvalidPlanChange` error. Each check rejects in the order the spec gives and leaves the subscription and invoices untouched.
- **Upgrades** take effect immediately with a prorated invoice. It has a credit line for the old plan's unused days and a charge line for the new plan, each rounded separately; the spec's example comes out at −0.97 + 2.90 = 1.93. If the total is zero or less, no invoice is issued.
- **Downgrades, sideways moves to a same-priced plan, and monthly↔annual switches** are scheduled for the next renewal. That renewal then moves the subscription and bills the new plan's full price.
- **Changing a scheduled change:** the latest request replaces the scheduled change, and asking for the current plan and interval clears it. An upgrade that also switches interval is split: the upgrade happens now, the interval switch at renewal.
- **Trials:** a change during a trial applies immediately, bills nothing, and keeps the trial end date.

**Code review:**
- **Spec check:** nothing missing and nothing extra.
- **Code standards:** nothing that breaks the repo's documented rules, only some judgement calls.
- **Fixed in one follow-up commit:** repeated invoice wording, some date logic moved onto `Subscription`, "cancel" renamed to "clear" for scheduled changes, three tests split so each checks one thing, and an upgrade now builds its invoice before saving the plan change.
- **Left as is:** two code-style points where the spec requires the current design.
- **Remaining small risk:** if recording the invoice fails after the plan change is saved, the plan stays changed with no invoice. The only way that can fail is a duplicate invoice id, and closing it would need transactions in the store.

**Housekeeping:**
- **Spec docs committed:** the spec, tickets, `GLOSSARY.md` and the ADR weren't in git, so I committed them to the branch as its first commit; the separate implementation copies couldn't see them otherwise.
- **Tickets closed:** the spec and tickets 01–04 are marked `Status: resolved`, each with a comment listing its commits.
- **Cleanup:** all the separate working copies and their branches are deleted. Only `main` and `plan-changes` remain.
