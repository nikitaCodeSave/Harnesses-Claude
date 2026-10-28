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

I've read the whole package (Plan/Interval, Subscription with half-open periods and trials, Invoice/LineItem, `subscribe`/`renew_due`/`cancel`). A few facts shape the questions:

- Nothing records what a customer actually paid for the current period except the invoices, and there's no credit balance or refund mechanism.
- `LineItem` accepts negative amounts, so an invoice could technically total less than zero.
- Plan prices never change after creation. Only `active` can be flipped.

Here's the first round. Each question has a proposed default, so you can reply "yes to all except…".

**1. Upgrades (new plan costs more, same interval).** Should they take effect immediately, keep the current period dates, and issue an invoice now? That invoice would have a credit line for the unused part of the old plan and a charge line for the same remaining days on the new plan.
*Default: yes.*

**2. Downgrades (cheaper plan, same interval).** Since there's nowhere to put a refund or credit, which do you want?
- (a) Schedule it for the end of the current period. The customer keeps the better plan until renewal, the renewal bills the new plan, and `change_plan` returns `None`.
- (b) Apply it immediately and issue an invoice with a negative total, which then needs some notion of a credit or refund.
- (c) Apply it immediately and refund nothing. This contradicts "nobody pays twice".

*Default: (a).*

**3. Monthly → annual.** Should this happen immediately, starting a new annual period today? The invoice would credit the unused monthly days and charge the full annual price.
*Default: yes.*

**4. Annual → monthly.** Refunding up to 11 months immediately would hit the same problem as downgrades.
*Default: schedule it for the end of the annual period, return `None`.*

**5. Classifying changes.** When the plan and the interval both change, how do we decide which is the "upgrade" and which the "downgrade"? I'd use the interval rule first: anything moving to annual is immediate, and anything moving to monthly is deferred. Within the same interval, comparing list prices decides. If the prices are equal, I'd apply the change immediately, which gives an invoice that nets to zero.
*Question: should an equal-price change produce a zero-total invoice, or switch with no invoice and return `None`?*

**6. Proration math.**
- The fraction is remaining days divided by days in the current period. Today counts as unused, so a change on `period_start` credits the full period.
- The credit is valued at the current plan's list price for the current interval. Because prices never change, that equals what was paid, including after an earlier mid-cycle upgrade.
- The credit and the charge are each rounded to cents, half up.

*Default: all of the above. Please also confirm that "today counts as unused" matches what you want.*

**7. Trials.** During a trial, should a change swap the plan and/or interval without billing anything, keep the trial end date, and return `None`?
*Default: yes.*

**8. Rejections.**

| Situation | Proposed error |
|---|---|
| Canceled subscription | `SubscriptionNotActive` |
| Unknown plan | `PlanNotFound` |
| Retired target plan | `PlanNotAvailable` (even if it's the customer's current plan and only the interval changes) |
| Same plan and same interval | `InvalidPlanChange` |
| Renewal overdue (`period_end <= today` but `renew_due` hasn't run yet) | `InvalidPlanChange` rather than silently renewing first |

*Default: as in the table. Do you agree, particularly with the last two rows?*

**9. Pending scheduled changes (only relevant if you pick 2(a) or 4).**
- A new change request replaces any pending one.
- Requesting the current plan and interval while a change is pending cancels the pending change, returns `None`, and does not raise.
- Canceling the subscription discards the pending change.
- Pending changes should be visible on `Subscription`, for example as a pending plan and interval.

*Default: all of the above.*

### [spec] user

1. Yes, but note: upgrade vs downgrade is decided by the plans' monthly list price, whatever interval the customer is on or moving to. Upgrade is immediate, the period dates don't move, and the invoice has exactly two lines: a credit for the unused part of the current plan and a charge for the same remaining days on the new plan, both at the current interval's prices.

2. (a), schedule for period end, return None, nothing billed. The renewal moves them to the cheaper plan at its full price. This applies to any move to a cheaper plan, including one combined with a switch to annual.

3. No. Interval switches in both directions wait for the end of the period. Nothing is billed at request; the renewal starts a period of the new interval at its full price. We never refund unused annual time.

4. Yes, scheduled for period end, return None (same as 3).

5. Don't use the interval rule. Classify by monthly list price only. If plan and interval both change and it's an upgrade, split it: the upgrade happens now, prorated at the current interval's prices, and the interval switch is scheduled for the period end. If it's a downgrade, the whole thing is scheduled. Switching only the interval on the same plan is neither, so it is scheduled. Equal monthly price between different plans: I don't mind, your call.

6. Proration is by real calendar days of the current period (28-31 for a month, 365/366 for a year). Remaining days count from the change date inclusive up to period end exclusive. So the change day counts as the new plan's day, not as unused. That differs from your default: a change on period_start has the full period remaining, which is the same as your result there, but the day is billed on the new plan. Each line is computed exactly as price x remaining days / period days, with no rounded daily rate, and rounded half-up to cents on its own. The total is the sum of the two rounded lines. Example: Pro -> Premium on Mar 11 in a Mar 1-Apr 1 period gives 21/31 left, lines -20.32 and +50.81, total 30.49.

7. Yes, with one addition: any change during a trial (up, down or interval) applies immediately in full, returns None, no invoice. The trial end date doesn't move, and at trial end they are billed the full price of the plan and interval they are on by then.

8. Canceled gives SubscriptionNotActive, unknown plan gives PlanNotFound, and a retired target gives PlanNotAvailable, all agreed. Customers on a retired plan can move off it like anyone else. Same plan and same interval: if something is scheduled, it cancels the scheduled change, returns None, and bills nothing. If nothing is scheduled, raise InvalidPlanChange. For a request on or after period_end before renewal has run, I don't mind. Also, rejected requests change nothing: no invoice, subscription untouched.

9. Mostly yes. Only one scheduled change at a time. Each request states the full target (plan + interval) and replaces whatever was scheduled. An upgrade applied now also discards anything scheduled, unless the same request itself schedules an interval switch. A scheduled change hasn't happened yet, so an upgrade while a downgrade is pending is prorated from the current plan. Example: on Pro, Basic scheduled on Mar 5, then Premium on Mar 11 gives 30.49. The cancel-on-same-target behaviour matches what I said in 8. How the pending change is stored on Subscription is up to you.

### [spec] agent

Thanks, that's nearly everything. Your example implies Premium has a monthly price of 75.00 (75 × 21/31 = 50.806, which rounds to 50.81). The fixtures only define Basic at 10/100 and Pro at 30/300, so the spec will add Premium at 75.00 monthly. Before I write it, I have four remaining questions and two decisions you left to me.

**A. Upgrades that would net to zero or less.** Upgrades are classified by monthly price but prorated at the current interval's prices, so they can disagree. Example: Pro is 30/300 and a "Team" plan is 35/280. An annual Pro customer moving to Team counts as an upgrade, but the invoice credits more than it charges, giving a negative total. That's effectively a refund. Options:
- (a) Reject with `InvalidPlanChange`.
- (b) Issue the two-line invoice anyway.
- (c) Treat it as scheduled, like a downgrade.

I'd pick (c): it keeps "we never refund" true and the customer still gets the plan.

**B. Scheduled target retired before renewal.** If the plan a customer is scheduled to move to gets retired before the renewal, should the renewal still move them onto it, or drop the change? I'd still move them: the plan was sold to them when they asked, which matches how existing customers keep renewing on retired plans.

**C. Requests from a customer whose current plan is retired.**
- Same plan, same interval, with a change scheduled: should this cancel the scheduled change? I'd allow it, because it isn't selling the retired plan to anyone new.
- Same plan, different interval: should this raise `PlanNotAvailable`, since the target is retired? I'd raise it.

**D. Upgrades during an overdue period.** Requests on or after `period_end` before `renew_due` has run will raise `InvalidPlanChange`; this is one of my two decisions below. Should trials be rejected the same way? A trial change doesn't prorate, so it could be honoured. I'd still reject trials too, so the rule is simple: renew first.

**My decisions on the two points you left to me:**
- **Equal monthly price between different plans:** scheduled for the period end, like a downgrade. Nothing is billed and there's no zero-total invoice.
- **Request on or after `period_end` before renewal has run:** raises `InvalidPlanChange` and changes nothing.

### [spec] user

Premium is 75.00 a month, so your arithmetic is right.

A. I'd pick (b), not (c). A move to a plan with a higher monthly price is an upgrade and happens right away, with the usual two-line invoice. Each line is rounded on its own and the total is their sum, whatever that comes to. I haven't thought about a negative total beyond that, so don't add any special handling.

B. I don't mind. Go with your recommendation.

C. Both of your proposals are fine. Cancelling a scheduled change on the same plan and interval is allowed. A different interval on a retired plan raises PlanNotAvailable.

D. Fine, reject trials too in the overdue case.

Your two decisions are also fine.

### [spec] agent

I've written `SPEC.md` with the interface copied word for word, 33 numbered acceptance criteria, non-goals, and a short record of decisions. Nothing is implemented or committed yet.

I checked every worked example by recomputing it with Decimal and half-up rounding. They include your 30.49 case, a change on `period_start`, a change on the last day, a 28-day February, an annual period, a 366-day leap-year period and the negative Pro → Team upgrade (−10.08).

The examples need three plans that don't exist in the test fixtures yet: Premium (75.00 / 750.00), Team (35.00 / 280.00) and Studio (30.00 / 280.00). You only gave me Premium's monthly price, so the other prices are mine.

A few things in the spec go slightly beyond what you said; please check them:

- **Line order:** the upgrade invoice lists the credit line first, then the charge.
- **What the target interval means:** if you don't pass `new_interval`, the target is the customer's current interval, not a switch that's already scheduled. So with Pro monthly and Pro annual scheduled, a request for Basic schedules Basic **monthly** and drops the switch to annual. This follows from your "each request states the full target".
- **Several missed renewals:** if `renew_due` has to bill several overdue periods, the scheduled change applies from the first of them.
- **Retired plan, nothing scheduled:** asking for your current retired plan and interval raises `InvalidPlanChange`, not `PlanNotAvailable`.
- **Exports:** `InvalidPlanChange` is exported from `billing` like the other errors.
- **Viewing scheduled changes:** a scheduled change must be readable from the saved `Subscription`. How it's stored is still up to the implementation.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote 125 acceptance tests under `tests/acceptance/`, covering all 33 criteria. As intended, 119 fail because the feature doesn't exist yet. The other 6 pass, and that's expected too: they check behaviour that must not change. I didn't touch any source code.

**Command and output**

```
$ python3 -m pytest tests/acceptance -q -p no:cacheprovider
...
FAILED tests/acceptance/test_upgrades.py::test_c04_worked_examples[pro-premium-mid-month]
... (119 FAILED lines in total)
119 failed, 6 passed in 0.36s
```

Every failure is a missing name, not a wrong value:
- 98 × `AttributeError: 'BillingService' object has no attribute 'change_plan'`
- 21 × `AttributeError: ... has no attribute 'InvalidPlanChange'`

The 6 that pass check criteria 32 and 33, which the current code already meets: no system clock calls, frozen dataclasses, `Subscription` can still be built from its original fields, unchanged subscribe/renew/cancel and trial behaviour, and a never-changed subscription shows nothing scheduled. The full suite (`python3 -m pytest -q`) gives `119 failed, 26 passed`, so the 20 existing tests still pass.

**Files** (each test name starts with its criterion number, e.g. `test_c04_…`)

| File | Criteria |
|---|---|
| `test_upgrades.py` | 1–7, including all 7 rows of the worked-example table |
| `test_scheduled_changes.py` | 8–16 |
| `test_existing_schedule.py` | 17–20 |
| `test_trials.py` | 21–23 |
| `test_rejections.py` | 24–30 |
| `test_package_hygiene.py` | 31–33 |
| `spec_support.py`, `conftest.py` | shared helpers: a test setup with the spec's plans, a renewal check, and the criterion 15 checks |

**Choices worth checking**
- **Expected values:** the money amounts come from the spec's table. I recalculated them on their own to confirm the spec is consistent with itself, and it is.
- **Extra values I derived:** a few tests needed amounts the spec doesn't list. I worked these out from the spec's formula:
  - zero credit when upgrading from a free plan: 0.00 / 6.77
  - a line that lands exactly on half a cent, to check half-up rounding: 0.125 → 0.13
  - a zero-total upgrade between plans with the same annual price: −151.23 / +151.23
- **Criterion 15 (storage is up to the implementation):** "scheduled" is checked by looking for the target plan code and interval among any fields `Subscription` gains beyond its original ones. "Nothing scheduled" means those extra fields equal what a `Subscription` built from only its original fields gets by default.
- **`InvalidPlanChange` lookup:** tests look it up when they run rather than importing it at the top of each file. A missing class then fails each test that needs it, instead of stopping pytest from loading the whole folder.
- **"No code reads the system clock" (criterion 32):** this one test scans the text of `src/billing` for calls like `date.today()` and `datetime.now()`. It's the only test that reads source code rather than using the public interface. A second test runs a change in 2031 to show the service follows the clock it's given.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

`BillingService.change_plan` is built as SPEC.md describes, and all tests pass: both the acceptance suite and the existing tests.

**Command and output:**
```
$ python3 -m pytest -q
........................................................................ [ 49%]
........................................................................ [ 99%]
.                                                                        [100%]
145 passed in 0.05s
```
That is 125 in `tests/acceptance/` and the 20 existing tests. I didn't change any tests.

**What changed** (all in `src/billing/`):
- **`errors.py` / `__init__.py`:** added `InvalidPlanChange(BillingError)` and exported it from `billing`.
- **`subscriptions.py`:** a pending change is stored as two new optional fields, `scheduled_plan_code` and `scheduled_interval`. Both are `None` by default, so a subscription that never had a change looks exactly as before. The constructor rejects a record with only one of the two set.
- **`money.py`:** added `prorate(amount, numerator, denominator)`. It multiplies before dividing and rounds to cents (half up) only once, so there is never a rounded per-day rate. That is what makes the 30.49 example come out right.
- **`service.py`:**
  - `change_plan` checks requests in this order: subscription exists, not canceled, target plan exists, period not overdue, not a request for the current plan, target not retired. Then a trial change applies immediately; a downgrade or interval switch is scheduled; an upgrade applies now with a credit line then a charge line, and any interval switch in the same request is scheduled.
  - Renewal now applies the scheduled change and clears it before billing. The rest of the renewal logic is unchanged, so missed renewals that are caught up all use the changed plan from the first one.

**Choices you may want to check:**
- **Check order:** the spec doesn't say which error wins when a request breaks two rules, and no test covers it. For example, an overdue request for an unknown plan raises `PlanNotFound`, and an overdue request for a retired plan raises `InvalidPlanChange`. Cancelling a pending change is also rejected once the period is overdue (criterion 29).
- **Zero credit:** when the current plan costs 0.00, the credit line is stored as `0.00` instead of `-0.00`. They compare equal, but `-0.00` would show up on the invoice.
- **Line descriptions:** each line says "Unused \<plan\>" or "\<plan\>", the billing interval, the dates and the remaining/period days, e.g. "21/31 days". The spec leaves the wording open.

Nothing is committed yet.

### [review1] operator

Review the changes since commit 8f1b061d1c9d8f7290d9c0d5bd20b8a46bd8ffd4 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found nothing to fix. I reviewed the diff since `8f1b061` (all uncommitted changes in `__init__.py`, `errors.py`, `money.py`, `service.py` and `subscriptions.py`) against every criterion in SPEC.md. All 145 tests pass, the existing tests and `tests/acceptance/` included.

Points I checked by hand:
- **Proration (criteria 2–6):** `prorate` (`money.py:23`) multiplies the full price by remaining days and divides last, so no daily rate is rounded. Each line is rounded on its own, half up. The credit is `ZERO - prorate(...)`, which gives the same result as rounding the negative amount half up, and it comes out as 0.00 for a free plan. The days count runs from today to `period_end`, so the day of the change is billed on the new plan.
- **Classifying the change (criteria 5, 8, 9):** it compares `monthly_price` only. Equal prices, and same-plan interval switches, take the scheduled path. Pro → Team is billed as an upgrade even though its annual price is lower.
- **Replacing a scheduled change (criteria 17–20):** every path writes the whole target or clears it. An upgrade on the same interval discards the schedule, and an upgrade with an interval switch schedules (target plan, target interval). When `new_interval` is `None`, the current interval is used, never the scheduled one.
- **Renewal (criteria 12–14):** `_renew` (`service.py:150`) applies and clears the schedule before pricing, so a catch-up applies it from the first missed period. It looks up the plan with `get_plan` and doesn't check `active`, so a scheduled change to a since-retired plan still goes through.
- **Trials (criteria 21–23):** the plan and interval change at once, status and `period_end` stay the same, nothing is billed, and a request for the current plan and interval raises `InvalidPlanChange`.
- **Rejections (criteria 24–30):** a retired target is rejected after the current-plan/current-interval check, so a customer on a retired plan can still cancel a scheduled change (criterion 28) but not switch interval. The overdue check uses `today >= period_end`. Every error is raised before anything is saved, so a rejected request changes nothing.
- **Package hygiene (criteria 31–33):** `InvalidPlanChange` is exported, the new fields default to `None` so existing behaviour is unchanged, and the code makes no clock calls and doesn't mutate any objects.

FINDINGS: 0
