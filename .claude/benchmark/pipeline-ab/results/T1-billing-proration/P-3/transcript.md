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

I've read the whole billing package. Some facts that shape the questions:

- There's no credit balance and no refund anywhere. `cancel` says "No refund".
- A `LineItem` can have a negative amount (only whole cents are checked), so an invoice can include a credit line.
- `Subscription` only holds the current plan, interval and period. Nothing can store a change that is waiting to happen.
- `renew_due` is a batch job, so a subscription can sit with `period_end <= today` until the job runs.

Round 1 covers the decisions that don't depend on anything else:

---

❓ **Q1** - **When do downgrades take effect?** Since there's no credit balance, a downgrade that takes effect today leaves us owing the customer money. The options are:

- (a) **Scheduled downgrade**: the change takes effect at the end of the current period. Nothing is billed now and `change_plan` returns `None`. This needs a new pending-change field on `Subscription`, which `renew_due` applies.
- (b) Immediate, with a negative-total invoice. That's effectively a refund, which contradicts the "no refunds" stance in `cancel`.
- (c) Immediate, with a new customer credit balance used against later invoices. That's a whole new concept.

➡️ (a). The customer has already paid for the current period, so they keep it. It needs no money-out path, and it explains the `None` return in your interface.

---

❓ **Q2** - **How does an upgrade within the same interval work?** It takes effect today and the period dates stay the same. The invoice has two lines: a negative **credit** for the unused part of the current plan, and a **charge** for the new plan over the same remaining days. That way `[period_start, today)` is paid on the old plan and `[today, period_end)` on the new one, so no day is paid for twice.

➡️ Yes.

---

❓ **Q3** - **How is the proration calculated?** The unit is calendar days. The unused share is `(period_end − today) / (period_end − period_start)`, using the real length of the period (28–31 days, or 365/366). Each line is rounded to cents half-up on its own, so the invoice total is the sum of the rounded lines. The change takes effect on the day of the request, which means today counts as a day on the new plan.

➡️ Yes.

---

❓ **Q4** - **What happens to a change during a free trial?** For a `TRIALING` subscription, the plan and/or interval change right away. The trial end date stays the same, nothing is billed, and the call returns `None`. The first paid period is billed at the new terms when the trial ends. The "target plan must not be retired" check still applies.

➡️ Yes.

---

❓ **Q5** - **What if a renewal is overdue?** If `period_end <= today` and `renew_due` hasn't run yet, there are no unused days left to prorate. The options are:

- (a) Reject with `InvalidPlanChange`. The caller runs `renew_due` and then retries.
- (b) Have `change_plan` catch up the renewals itself first. That issues renewal invoices the caller never sees in the return value.

➡️ (a). It's predictable, and only one call returns invoices.

---

❓ **Q6** - **Which errors does `change_plan` raise?**

| Situation | Error |
|---|---|
| Unknown subscription | `SubscriptionNotFound` |
| Canceled subscription | `SubscriptionNotActive` |
| Unknown target plan | `PlanNotFound` |
| Target plan is retired | `PlanNotAvailable` |
| Same plan and same interval as now | `InvalidPlanChange` |
| Renewal overdue (Q5) | `InvalidPlanChange` |

➡️ Yes.

---

❓ **Q7** - **Can a customer on a retired plan switch interval?** Say a customer on a retired plan wants to stay on it and move from monthly to annual. Does that count as "selling" the retired plan? The options are:

- (a) Yes, so it raises `PlanNotAvailable`. They can only move to an active plan.
- (b) No, so it's allowed, because they're already a customer of that plan.

➡️ (a). A new interval is a new purchase of the plan. Grandfathering means the plan keeps renewing as it is, not that it can be changed.

---

Once these are settled, round 2 will cover:
- how to classify a change as an upgrade or a downgrade, including equal prices and interval switches;
- what a monthly↔annual switch does to the period;
- how a scheduled downgrade behaves when the customer makes another change or cancels before it applies.

### [grill] user

Q1: Yes, (a). Downgrades wait for the end of the period. Nothing is billed or refunded at the request, and change_plan returns None.

Q2: Yes.

Q3: Yes.

Q4: Yes.

Q5: I don't mind. Go with (a).

Q6: Mostly yes, with one correction. If the customer asks for the plan and interval they already have and a change is scheduled, that cancels the scheduled change. It returns None, bills nothing, and the renewal continues on the current plan. Only when nothing is scheduled does it raise InvalidPlanChange. The other rows are fine. Customers on a retired plan can still move off it to an active plan like anyone else.

Q7: I don't mind. Go with your recommendation.

### [grill] agent

Round 1 is settled. I created `GLOSSARY.md` with the terms we've agreed: **Plan change**, **Upgrade** (takes effect today and is prorated), **Downgrade** (waits for the end of the period), **Scheduled change**, and **Proration** with its **credit** and **charge**. I've noted your Q6 correction: asking for the current plan and interval when a downgrade is scheduled cancels that downgrade.

Round 2:

---

❓ **Q8** - **How do we classify a change when the interval stays the same?** We compare the two plans' list prices for that interval:

- **Higher price**: it's an upgrade, prorated to the current `period_end` as in Q2.
- **Lower price**: it's a downgrade and is scheduled.
- **Equal price, different plan** (a "lateral" move): it takes effect today. The proration credit and charge cancel to exactly 0.00, so no invoice is issued and the call returns `None`.

➡️ Yes. A lateral move has no reason to wait, and "nothing is billed" fits the `None` return.

---

❓ **Q9** - **What does a monthly → annual switch do?** It's an upgrade and takes effect today. A **new annual period starts today**, `[today, today + 12 months)`. The invoice is a proration credit for the unused days of the current monthly period, plus a charge for the **full annual price** of the target plan. A target plan is allowed (e.g. monthly Basic → annual Pro). The renewal date moves to today's date.

➡️ Yes. Keeping the old `period_end` would leave an annual subscription with a period about one month long.

---

❓ **Q10** - **Is an annual → monthly switch always a downgrade?** It would be scheduled for the end of the annual period, whatever the plans' prices. From then on the subscription renews monthly on the target plan. Making it immediate would almost always mean a credit bigger than the charge, which is a refund under another name.

➡️ Yes.

---

❓ **Q11** - **How does a scheduled change behave over time?**

- (a) Any new plan change request **replaces** the scheduled change. A new downgrade overwrites it. An upgrade or lateral move clears it and applies now. Asking for the current terms clears it, per your Q6 answer.
- (b) Requesting the **same** change that's already scheduled is a harmless repeat: it returns `None`, and the scheduled change stays as it is.
- (c) If the target plan is **retired** between the request and the renewal, the scheduled change **still applies**, because it was sold when the customer requested it.
- (d) When `renew_due` catches up several missed periods, the scheduled change applies at the **first** renewal, and later periods continue on the new terms.

➡️ Yes to all four.

---

After this round, the one remaining question is what to do when a monthly → annual switch would net to zero or less. For example, a $100/month Pro customer moving to a $50/year Basic plan. Its answer depends on Q9.

### [grill] user

Q8: Partly. Upgrade or downgrade is decided by the plans' monthly list price, whichever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade. Switching interval on the same plan is neither. A higher monthly price applies now, prorated at the current interval's prices. A lower one is scheduled for the end of the period. For equal monthly prices I don't mind, so your lateral approach is fine.

Q9: No, this contradicts how I want it. Interval switches, monthly to annual included, wait for the end of the current period. Nothing is billed at the request, and the period doesn't move. At the renewal date a new period of the new interval starts and bills that interval's full price. If an upgrade comes together with an interval switch, split it. The upgrade happens now, prorated at the current interval's prices as in Q2 and Q3. The interval switch happens at the period end. Your zero-or-negative example doesn't arise, because nothing is prorated for the interval switch.

Q10: Same rule as Q9, so yes, it waits for the end of the period. But I wouldn't call it a downgrade, because an interval switch is neither an upgrade nor a downgrade. If the plan also moves to a more expensive one, that part is an upgrade now, prorated at the annual prices of the current period. The switch to monthly still happens at the period end. If the plan also moves to a cheaper one, everything waits for the period end.

Q11: (a) Yes, with one exception. An upgrade that applies now clears the scheduled change, unless that same request schedules an interval switch per Q9. (b) Fine. A repeat just replaces the scheduled change with the same one. (c) and (d) I don't mind, so go with your recommendation.

### [grill] agent

I've updated `GLOSSARY.md`. Upgrade and downgrade are now decided by the **monthly list price**. I added **Lateral change** and **Interval switch** (neither an upgrade nor a downgrade, always waits for the period end, never prorated). **Scheduled change** now covers a downgrade, an interval switch, or both. Q11 (c) and (d) are settled as I recommended.

Combining your rules raises one new problem and two scenarios I want you to confirm.

---

❓ **Q12** - **Does this table match your rules?** It treats every request as a plan part plus an interval part:

| Plan part (by monthly list price) | Same interval | Interval switch requested |
|---|---|---|
| Higher (upgrade) | Applies now and returns a prorated invoice | Upgrade now with a prorated invoice. The interval switch on the *new* plan is scheduled. |
| Equal, different plan (lateral) | Applies now | Lateral move now. The interval switch is scheduled. |
| Lower (downgrade) | Scheduled; returns `None` | Plan and interval are both scheduled; returns `None` |
| Same plan | Clears a scheduled change and returns `None`; with nothing scheduled, raises `InvalidPlanChange` | Interval switch scheduled; returns `None` |

"Same plan" and "same interval" are always compared with the terms in effect now, not the scheduled ones. During a trial (Q4), everything still applies immediately with nothing billed. The two rules agree there anyway: switching interval during a trial just means the first paid period uses the new interval.

➡️ Yes.

---

❓ **Q13** - **What if a change that applies now nets to zero or less?** Because upgrades are decided by *monthly* price but prorated at the *current interval's* prices, the invoice can come out negative. For example, take an annual customer:

- Basic: $10/month, $120/year
- Pro: $12/month, $100/year (heavily discounted annual price)

Moving from annual Basic to Pro is an upgrade by monthly price, but the credit at $120/year is bigger than the charge at $100/year. A lateral change on the annual interval can also have unequal annual prices, giving a net positive or negative result. The options are:

- (a) Apply now. Issue an invoice only if the net is **positive**. If the net is zero or negative, bill nothing, refund nothing, and return `None`. The customer simply doesn't get the difference back, which matches "no refunds" in `cancel`.
- (b) Apply now and issue the negative-total invoice. That's a refund.
- (c) Schedule it for the period end instead.
- (d) Reject with `InvalidPlanChange`.

➡️ (a). This also settles laterals: they're billed when the new current-interval price is higher, and otherwise return `None`.

---

❓ **Q14** - **Should a scheduled interval switch be dropped by a later plain upgrade?** A monthly Basic customer schedules a switch to annual. A week later they upgrade to Pro with `new_interval=None`. By the rule from Q11(a), the request means "Pro, monthly" (the interval *in effect now*), so the upgrade applies now and **the scheduled annual switch is dropped**. To keep it, the caller must pass `new_interval=ANNUAL`.

➡️ Yes. That follows directly from "each request replaces the scheduled change", and `None` means the interval in effect now, as your interface says.

### [grill] user

Q12: Yes, the table matches my rules.

Q13: I haven't thought about negative totals, so I don't mind. Go with (a).

Q14: Yes. Each request states the full target and replaces whatever was scheduled, and None means the current interval.

### [grill] agent

Every question is now answered. I added the Q13 rule to `GLOSSARY.md`: a proration credit is never paid out. Here is the full design for `change_plan` in one place. Please confirm before I build anything.

**Validation, checked in this order**
1. **Subscription**: `SubscriptionNotFound` if it doesn't exist; `SubscriptionNotActive` if it's canceled.
2. **Target plan**: `PlanNotFound` if it doesn't exist; `PlanNotAvailable` if it's retired. Customers on a retired plan can still move to an active one.
3. **Overdue renewal**: if `period_end <= today`, raise `InvalidPlanChange` (renewal due; run `renew_due` first).
4. **Retired plan, new interval**: staying on your current retired plan but asking for a different interval raises `PlanNotAvailable`.
5. **No change**: the same plan and interval as the terms in effect now clears any scheduled change and returns `None`. With nothing scheduled, it raises `InvalidPlanChange`.

**During a trial:** the plan and interval change right away. The trial end stays the same, nothing is billed, and the call returns `None`.

**Otherwise, the request has two parts:**
- **Plan part**, decided by monthly list price:
  - **Upgrade** (higher price): applies now.
  - **Lateral change** (equal price, different plan): applies now.
  - **Downgrade** (lower price): scheduled.
- **Interval part**: an **interval switch** is always scheduled and never prorated.

**Every request replaces the scheduled change.** Whatever this request schedules (a downgrade, an interval switch, both, or nothing) becomes the new scheduled change. `None` means the interval in effect now.

**Changes that apply now (upgrade or lateral):**
- The period dates stay the same.
- **Proration** is by calendar day, using the current interval's prices. The new plan covers `[today, period_end)`, out of the period's real length in days.
- The invoice has a negative **proration credit** for the old plan and a **proration charge** for the new one, each rounded to cents half-up. It's dated today.
- The invoice is issued only if the total is greater than 0. Otherwise nothing is billed or refunded, and the call returns `None`.

**At renewal**, `renew_due` applies the scheduled change at the first renewal it processes. It applies even if the target plan has been retired since. The new period uses the scheduled plan and interval and is billed at full price, then the scheduled change is cleared.

**Implementation, unless you object:**
- **Code**: an optional scheduled-change field on `Subscription`, and `InvalidPlanChange` exported from `billing/__init__.py`.
- **Tests**: each row of the Q12 table, the Q13 negative case, a leap-year annual proration, a catch-up renewal that applies a scheduled change, and the error rows.

**One offer:** I'd like to write an ADR, `docs/adr/0001-plan-changes-without-refunds.md`. It would record two decisions: interval switches are never prorated and wait for the period end, and credits are never paid out. Both are surprising (I recommended the opposite for monthly→annual), both were real trade-offs, and both are costly to reverse once customers depend on them. Shall I write it?

Do we have a shared understanding?

### [grill] user

Yes, that matches my rules. Where I said I don't mind, such as overdue renewals, retired plans and zero or negative totals, your choices are fine.

You can write the ADR, since it's documentation from this interview. Don't start on the code or tests yet. I'll run /to-spec, /to-tickets and /implement-spec myself afterwards.

### [grill] agent

I wrote the ADR at `docs/adr/0001-plan-changes-without-refunds.md`. It records two decisions:

- **Never pay money out:** only upgrades and lateral changes apply mid-period. If the proration credit is at least the charge, nothing is billed and the leftover credit is lost.
- **Interval switches wait for the renewal:** they are never prorated. A request that combines an upgrade with an interval switch is split: the upgrade applies now and the switch is scheduled.

It also notes the two options we rejected (prorating interval switches immediately, and refunds or a credit balance) and two effects customers will notice:

- A customer moving from monthly to annual keeps paying monthly until their current month ends.
- An annual customer who upgrades to a plan with a discounted annual price gets the upgrade with nothing billed, and doesn't get the difference back.

`GLOSSARY.md` has all the terms from the interview: Plan, Interval, Period, Retired plan, Plan change, Upgrade, Downgrade, Lateral change, Interval switch, Scheduled change, Proration, Proration credit and Proration charge.

I haven't touched any code or tests or committed anything, so both files are uncommitted and ready for your `/to-spec`.

### [to-spec] operator

/to-spec

### [to-spec] agent

I've checked the existing tests. They all drive `BillingService` with a `FixedClock` and check the results through the `InMemoryStore`.

**Proposed test seam: one existing seam, nothing new.**
- **Input:** the public `BillingService` API, meaning `change_plan` plus the existing `subscribe`, `renew_due` and `cancel` calls to set up state and observe scheduled changes being applied.
- **Time:** controlled by `FixedClock`.
- **Checks:** the returned `Invoice | None`, `store.get_subscription(...)` (plan, interval, period, scheduled change) and `store.invoices_for(...)` (lines, totals, issue dates).
- **Scope:** proration maths, the Q12 classification table, the scheduled-change lifecycle and every error case go through this seam. No unit tests for an internal proration helper, and no new store methods just for tests.

One thing tests would see: the scheduled change needs to be visible on `Subscription`, as an optional field holding the target plan and interval. The alternative is to check it only indirectly, through what `renew_due` bills. I recommend the visible field, so a test can confirm "scheduled, nothing billed yet" without moving the clock.

Do this seam and the visible scheduled-change field match what you expect? Once you confirm, I'll write the spec to `.scratch/plan-changes/spec.md` with the `ready-for-agent` label.

### [to-spec] user

The seam is fine. For the scheduled change, how and where it's stored on the subscription is up to you, so go with your recommendation. Go ahead and write the spec.

### [to-spec] agent

I wrote the spec to `.scratch/plan-changes/spec.md` and labelled it `Status: ready-for-agent`. It isn't committed; neither are `GLOSSARY.md` or the ADR.

The spec has 37 user stories and covers all the rules we settled. It also includes a worked example to anchor the maths. A Basic subscription starts on 2026-01-15 and upgrades to Pro on 2026-01-20, with 26 of 31 days left. That gives a credit of −8.39 and a charge of 25.16, so the invoice is 16.77. I checked these numbers by hand.

My own choices in the spec:

- **Retired plans (please check this one):** in my summary, the retired-plan check ran before the "same terms" check. That order would stop a customer on a retired plan from cancelling their scheduled change by requesting their current plan and interval. The spec makes an exception: requesting your current plan at your current interval isn't treated as buying the retired plan, so it's allowed. Any other request that targets a retired plan raises `PlanNotAvailable`. Change it if you'd rather it be rejected.
- **Where the scheduled change lives:** it's an optional `scheduled_change` field on `Subscription`. Its value is a new `ScheduledChange` type holding the plan and interval the subscription will take on at the next renewal. Both `ScheduledChange` and `InvalidPlanChange` are exported from the package.
- **Cancel:** it doesn't change. A scheduled change on a canceled subscription just never applies.
- **Out of scope:** this includes the production database store, which will need to save the new field.

### [to-tickets] operator

/to-tickets

### [to-tickets] agent

Here's the breakdown I propose. The codebase is small and renewals already read their terms from the subscription, so no prefactor ticket is needed. The renewal change goes in ticket 2, where the scheduled change first appears.

1. **Upgrade and lateral change with proration (tracer bullet)**
   - **Blocked by:** none (can start immediately).
   - **What it delivers:**
     - `change_plan` and `InvalidPlanChange` exist end to end, with every validation rule: unknown subscription or plan, canceled subscription, overdue renewal, retired target plan, and same terms with nothing scheduled.
     - An upgrade or lateral change on an active subscription, at the same interval, applies now. The period dates stay the same. The proration credit and charge use the current interval's prices.
     - The invoice is recorded and returned when the total is above zero. Otherwise the call returns `None`.
     - Tests: the worked example, the first-day upgrade, the 366-day annual period, laterals, and the zero-or-negative total case.

2. **Scheduled downgrades applied at renewal**
   - **Blocked by:** 1.
   - **What it delivers:**
     - `ScheduledChange` on `Subscription`.
     - A downgrade schedules the change, bills nothing and returns `None`.
     - `renew_due` applies the scheduled change at the next renewal, billing the full price, including during a catch-up of several periods. The change still applies if the target plan has been retired since.
     - Replacement rules:
       - a new request replaces the scheduled change;
       - an upgrade or lateral change clears it;
       - a repeated request changes nothing;
       - requesting the current terms clears it, also for a customer on a retired plan.

3. **Interval switches, alone and combined with a plan change**
   - **Blocked by:** 2.
   - **What it delivers:**
     - Monthly↔annual switches are scheduled, never prorated. At renewal they start a period of the new length at the new interval's full price.
     - An upgrade or lateral change plus a switch is split: the plan part is billed now and the switch is scheduled on the new plan.
     - A downgrade plus a switch is scheduled as a whole.
     - An upgrade with `new_interval=None` drops a scheduled switch.
     - Staying on a retired plan with a switch raises `PlanNotAvailable`.

4. **Plan changes during a free trial**
   - **Blocked by:** 1.
   - **What it delivers:**
     - A trialing subscription swaps plan and/or interval immediately. The trial end stays the same, nothing is billed, and the call returns `None`.
     - The first paid period bills the new terms.
   - This can run in parallel with 2 and 3.

Questions:
- Does the granularity feel right? Ticket 1 is the largest because it carries all the validation. I could split the validation into its own ticket, but then neither half could be checked without the other.
- Are the blocking edges correct? In particular, ticket 4 depends only on 1.
- Should any tickets be merged or split?

### [to-tickets] user

The granularity and the blocking edges look right to me. Keep ticket 1 as one piece and don't merge or split anything. I don't see anything in the tickets that contradicts what I told you.

### [to-tickets] agent

I've written the four tickets, as approved, to `.scratch/plan-changes/issues/`, all marked `ready-for-agent`:

| # | Ticket | Blocked by |
|---|---|---|
| 01 | Upgrade and lateral change with proration (all validation, the worked example) | none |
| 02 | Scheduled downgrades applied at renewal (`ScheduledChange`, `renew_due`, replacement rules) | 01 |
| 03 | Interval switches, alone and combined with a plan change | 02 |
| 04 | Plan changes during a free trial | 01 |

Tickets 01 and 04 can start straight away. Once 01 is done, 02 and 04 can run in parallel, and 03 follows 02.

While 01 is the only ticket done, two kinds of request have no defined result yet: downgrades (handled in 02) and interval switches (handled in 03). Treat those as unfinished, not as bugs.

Nothing is committed. The uncommitted files are `GLOSSARY.md`, `docs/adr/0001-plan-changes-without-refunds.md`, the spec, and these four tickets. They're ready for `/implement-spec`.

### [implement-spec] operator

/implement-spec .scratch/plan-changes/spec.md

### [implement-spec] agent

The whole spec is implemented on the `plan-changes` branch, and all 72 tests pass (20 existing, 52 new). Nothing is merged into `main` yet. There's no git remote, so I didn't open a PR.

**What customers and callers get:** `BillingService.change_plan(subscription_id, new_plan_code, new_interval=None)`, plus a new `InvalidPlanChange` error and a `ScheduledChange` value that is visible on the subscription.
- **Upgrades and lateral changes** apply the same day. The period dates don't move. The customer is credited for the unused days of the old plan and charged for the new one over the same days, each line rounded half-up to the cent. An invoice is issued only when that comes to more than zero; otherwise nothing is billed and nothing is refunded.
- **Downgrades and interval switches** are scheduled for the next renewal, which then bills the new terms at full price. That holds even if the target plan has been retired since the request, and in a catch-up of several missed periods the change applies only at the first one.
- **A request that upgrades and switches interval** is split: the upgrade happens now and the switch is scheduled. A new request replaces whatever was scheduled, and asking for the current plan and interval cancels it.
- **During a free trial** any change applies straight away with nothing billed, and the trial still ends on the same day.

**Choices the spec left open** — worth checking that you agree:
- **Line wording:** a credit line reads like "Credit for unused time on Basic (monthly) 2026-01-20 to 2026-02-15", and one test asserts these exact strings.
- **Upgrade plus interval switch that nets to zero or less:** the plan still changes now, the call returns `None`, and the interval switch is still scheduled.
- **Repeating an upgrade-plus-switch after the upgrade has applied:** it's treated as an interval switch on the new plan. It just re-schedules the same switch and bills nothing, so a double-click is harmless.

**Code review:** the spec review found nothing wrong in the code. One implementer fixed the standards findings:
- a shared overdue check and a shared line-description format;
- clearer names and glossary wording;
- an up-to-date README layout;
- consistent test imports;
- a test that a line landing exactly on half a cent rounds up.

I left two findings alone because both would reshape the domain model rather than tidy code:
- "terms" (a plan plus an interval) isn't a glossary word;
- the plan code and interval keep being passed around as a pair.

**Things I added along the way:**
- The spec, tickets, glossary and ADR were untracked, so they're committed on the branch so the worktrees could read them.
- I added a `.gitignore` after the first ticket branch committed Python cache files.
- In the tracker, the spec and all four tickets are now `resolved`, with their checkboxes ticked and a comment pointing to the commits.
- All the agent worktrees and their branches have been removed.
