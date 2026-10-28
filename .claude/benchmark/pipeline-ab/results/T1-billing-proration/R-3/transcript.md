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

I've read the package (service, periods, plans, store, tests — 20 passing). Here's what shapes my questions: subscriptions have a half-open `[period_start, period_end)` period that's paid in advance, there's no customer credit balance anywhere, `LineItem` accepts negative amounts but nothing produces them today, and `renew_due` only runs when someone calls it.

The decisions that change the spec are below. Each has my recommendation; answering "yes" or giving the number is enough.

**1. What happens to the billing period on an upgrade?**
- (a) **Keep the anchor:** the new plan covers the rest of the current period, and the period dates don't change. The charge is new-plan-remaining minus old-plan-remaining.
- (b) **Restart today:** credit the unused part of the old period, start a new full period today on the new plan, and bill it in full.

My recommendation is (a) when the interval stays the same and (b) when it changes. A monthly→annual switch can't sensibly keep a one-month anchor.

**2. Downgrades (the new plan costs less for the remaining time).** Since there's no credit balance, the options are:
- (a) **Defer to period end:** nothing is billed now, the change is recorded as pending and takes effect at the next renewal, and the method returns `None`.
- (b) Apply immediately and issue an invoice with a negative total (a refund).
- (c) Apply immediately and carry the credit into the next renewal invoice.

I recommend (a). It's the only option that fits the model without adding a refund or credit-balance concept, and it explains why the return type allows `None`. If you choose (a): can a pending downgrade be replaced by a later change or cancelled? Does an upgrade requested while a downgrade is pending cancel the downgrade?

**3. How should "upgrade" vs "downgrade" be decided when the interval changes?** Annual→monthly on the same plan is cheaper per period but often more per day. I suggest comparing the price of the remaining days (new vs old, prorated by day). Alternatively, every annual→monthly change could be deferred to period end, since refunding most of a year is what (b) above avoids. I'd go with the latter.

**4. Proration unit:** calendar days. Credit = old price × unused days ÷ days in the current period. "Unused" counts from today (inclusive) to `period_end`. Each line is rounded to cents half-up, and the invoice has one credit line and one charge line. OK?

**5. Edge cases. My proposed answers:**
- **Trialing subscription:** swap the plan/interval immediately, bill nothing, keep the trial end date unchanged, return `None`.
- **Canceled subscription:** `SubscriptionNotActive`.
- **Unknown target plan:** `PlanNotFound`. **Retired target plan:** `PlanNotAvailable`. Moving *off* a retired plan is allowed.
- **Same plan and same interval:** `InvalidPlanChange`.
- **Overdue renewal** (`period_end <= today`, not yet renewed): `InvalidPlanChange` rather than silently renewing first. Or would you rather it catch up the renewal and then apply the change?
- **Change on the period's first day:** full credit of the old period, which is fine.
- **Upgrade where the net charge is exactly 0.00** (e.g. on the last day): apply the change and return `None` with no invoice?

**6. Non-goals check:** no credit balance or refunds, no tax, no scheduling a change for an arbitrary future date, no plan-price versioning, no undoing a change. Anything to add or remove?

### [spec] user

1. Keep the anchor (a) for every upgrade, including when an interval switch comes with it. The upgrade happens now, prorated at the prices of the interval the customer is currently on. The interval switch waits until the period end, and the renewal then starts a period of the new interval at its full price. Don't restart the period.

2. Yes to (a): defer to period end. Nothing is billed or credited, change_plan returns None, and the renewal moves them to the cheaper plan at its full price. Only one change can be scheduled at a time. Each request states the full target (plan + interval) and replaces whatever was scheduled before. An upgrade that applies now also discards anything scheduled, unless the same request itself schedules an interval switch. An upgrade requested while a downgrade is pending is prorated from the current plan, since the downgrade hasn't happened yet. Asking for the plan and interval they already have cancels a pending change and returns None. If nothing is pending, raise InvalidPlanChange.

3. Don't compare prorated values. Upgrade vs downgrade is decided by the plans' monthly list price, whatever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade. A same-plan interval switch is neither, and it always waits for the period end, in both directions (monthly→annual too). Nothing is billed at the request. The renewal starts the new interval and bills its full price. We never refund unused annual time.

4. Calendar days, with remaining days counted from the change date inclusive to period_end exclusive. Days in the period are real calendar days (28-31 for a month, 365/366 for a year). Each line is computed exactly as price × remaining days / period days, with no rounded daily rate in between. Each line is rounded half-up to cents on its own, and the total is the sum of the two rounded lines. Don't round the net difference instead. The invoice is issued on the change date and recorded like any other invoice. Example: Pro→Premium on Mar 11 in a Mar 1–Apr 1 period gives 21/31, lines -20.32 and +50.81, total 30.49.

5. Edge cases:
- Trial: yes, but any change applies immediately, whether up, down or an interval switch. Plan and interval both switch now, nothing is billed, and it returns None. The trial end date doesn't move. At trial end the customer is billed the full price of whatever plan and interval they're on by then.
- Canceled: SubscriptionNotActive. Correct.
- Unknown plan: PlanNotFound. Retired target: PlanNotAvailable. Moving off a retired plan is allowed. Correct.
- Same plan and interval: as in 2, cancel if something is pending, otherwise InvalidPlanChange.
- Overdue renewal: I don't mind, so use your recommendation.
- First day of the period: fine.
- Zero-net upgrade: I don't mind whether it records an invoice.
- Any rejected request changes nothing: no invoice, and the subscription is untouched.

6. Non-goals: those are fine as listed.

### [spec] agent

Your answers cover almost everything. Three gaps remain, all caused by the rule that compares monthly list prices:

1. **Two different plans with the same monthly list price.** By that rule the change is neither an upgrade nor a downgrade. I'd treat it like a downgrade: deferred to period end, nothing billed now. Rejecting it with `InvalidPlanChange` is the other option.

2. **An upgrade whose invoice would go negative.** The monthly price decides that it's an upgrade, but proration uses the current interval's prices. If the customer is on annual and the "more expensive" plan has a *lower* annual price, the upgrade invoice comes out negative. I'd reject it with `InvalidPlanChange`, since the non-goals say we never issue refunds. Alternatively we accept the negative invoice. A third option is to defer it like a downgrade, which I'd choose if you'd rather not expose an error that only bad pricing data can trigger.

3. **Target plan retired after a change was scheduled but before the renewal.** I'd honour the scheduled change, because the customer committed to it while the plan was still sellable. This matches "existing customers keep renewing on retired plans". The alternative is to drop the change at renewal.

For the overdue renewal I'll use my recommendation (`InvalidPlanChange`). The spec will allow either behaviour for a zero-net upgrade.

### [spec] user

1. Same monthly price, different plans: I don't mind, so go with your recommendation.

2. A negative upgrade invoice: my notes don't cover it and I don't mind. Pick whichever you think is sensible. I'd only ask that a rejected request leaves everything untouched, with no invoice and the subscription unchanged.

3. Target plan retired before the renewal: I don't mind. Your recommendation of honouring the scheduled change is fine.

### [spec] agent

I've written the spec to `SPEC.md`. It has the interface copied word for word, definitions, 31 acceptance criteria, five worked examples and the non-goals. I checked the example numbers by recalculating them, including your Pro→Premium case: 30.49, where rounding the net difference instead would give 30.48.

These are the calls I made where you had no preference. Each is listed at the end of the spec so you can override it:
- **Two plans with the same monthly price:** treated as a downgrade, so it waits for the period end and nothing is billed now.
- **Upgrade whose invoice would come out negative:** rejected with `InvalidPlanChange`, leaving everything untouched. A negative invoice would be a refund, which the non-goals rule out.
- **Renewal overdue:** rejected with `InvalidPlanChange` rather than renewing first.
- **Plan retired after a change was scheduled:** the change still happens at renewal.
- **Upgrade that nets exactly 0.00:** recording an invoice or not are both allowed. Either way, the method returns the invoice if one was recorded and `None` otherwise.

I also decided two things you didn't raise:
- **Switching interval while staying on a retired plan** is rejected with `PlanNotAvailable`, because it sells the retired plan at a new price. Asking for the plan and interval the customer already has is still allowed, so a pending change on a retired plan can always be cancelled.
- **`new_interval=None` means the current interval**, not the interval of a pending change. So an upgrade with no interval given drops a pending interval switch.

Two criteria aren't in your wording but are needed to make it work:
- Scheduled changes are saved with the subscription, so a fresh `BillingService` on the same store still applies them.
- Subscription errors take precedence over plan errors, which take precedence over `InvalidPlanChange`.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I wrote 136 acceptance tests covering all 31 criteria in `tests/acceptance/`. All of them fail for now, as intended. I didn't implement anything: `src/` is unchanged and the 20 existing tests still pass.

**Command:**
```
python3 -m pytest tests/acceptance -q --tb=line
```
**Output (summary line, then the failure reasons counted):**
```
136 failed in 0.39s

114 × AttributeError: 'BillingService' object has no attribute 'change_plan'
 21 × AttributeError: module 'billing.errors' has no attribute 'InvalidPlanChange'
  1 × AttributeError: module 'billing' has no attribute 'InvalidPlanChange'
```
Every failure is due to the missing `change_plan` or `InvalidPlanChange`. None are import or collection errors: the tests look up `errors.InvalidPlanChange` only when they run, so each one fails separately. For criterion 31, `python3 -m pytest -q` gives `136 failed, 20 passed`, and those 20 are the existing tests.

**Files**, one per section of the spec:
- `conftest.py`: the spec's Basic, Pro and Premium plans, plus a few extra plans for edge cases. One has the same monthly price as Pro, one has a higher monthly but lower annual price (criterion 6), one gives an exact half-cent charge to test half-up rounding, and one gives a 0.00 total (criterion 20). There's also a `start(plan, interval, date)` helper.
- `test_change_plan_rejections.py` (1–8), `_same_target.py` (9–10), `_trial.py` (11–13), `_upgrades.py` (14–20), `_deferred.py` (21–24), `_renewal.py` (25–28), `_general.py` (29–31).

**How the tests are written:**
- **Only the public interface:** they use `change_plan`, `subscribe`, `renew_due`, `cancel`, the store's methods, `FixedClock` and the errors. The spec doesn't define a way to read a pending change, so the tests check it through what happens next: what the renewal bills and the period it sets, and whether a request for the current plan cancels the change (criterion 9) or raises `InvalidPlanChange` (criterion 10).
- **Expected values:** all five worked examples are tested with the spec's numbers (30.49, 100.82, 13.55, and the downgrade and cancellation flows). For other amounts I applied the spec's formula by hand with `Decimal`, and the expected figures are written as literals with the arithmetic in comments. Examples: a 366-day leap-year period gives −7.92 / +23.77, and 20.01 × 15/30 = 10.005 rounds to 10.01.
- **Line order:** the spec doesn't say which line comes first, so the tests compare the two amounts in sorted order rather than by position.

**Decisions you may want to check:**
- **Criterion 10 also applies in two other cases:** requesting the current plan during a trial, and on a retired plan with nothing pending, both raise `InvalidPlanChange` rather than `PlanNotAvailable`.
- **Criterion 20:** whichever invoice behaviour is chosen for a 0.00 total, the test still requires the plan to switch to the new one, following criterion 14.
- **No half-cent credit line:** I avoided a credit line that lands exactly on a half cent, because the spec doesn't say whether "half-up" for a negative amount rounds away from zero.

These tests haven't been run against a working implementation, so a mistake in a test could still show up as a false failure once the feature is built.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

`BillingService.change_plan` is built, and the acceptance tests and the existing suite all pass.

**Command:** `python3 -m pytest` (from the repo root; `pyproject.toml` already points it at `tests/`)

```
tests/acceptance/test_change_plan_deferred.py ...
tests/acceptance/test_change_plan_general.py ...
...
tests/test_service.py ..........                                         [100%]

============================= 156 passed in 0.06s ==============================
```

That's 136 acceptance tests plus the 20 existing ones, which pass unchanged. Before my changes, all 136 acceptance tests failed and the 20 existing ones passed. I didn't touch anything in `tests/`.

**How it works**
- **Where the pending change is kept:** I added an optional field, `pending_change`, to `Subscription` (`src/billing/subscriptions.py`). It holds the target plan and interval, so it's saved in the store with the subscription. A new `BillingService` over the same store sees it, and a rejected request leaves the stored subscription, pending change included, exactly as it was. Existing subscriptions are unaffected because the field defaults to `None`.
- **`change_plan`** (`src/billing/service.py`) checks requests in the order the spec sets:
  1. Unknown or canceled subscription.
  2. Unknown target plan.
  3. Retired target plan. A request for the current plan and interval is the only one allowed past this.
  4. Overdue renewal.
  5. Target equals current: cancels the pending change, or raises `InvalidPlanChange` if there isn't one.

  After the checks:
  - During a trial, the change applies immediately and nothing is billed.
  - If the target's monthly list price is lower or equal (or only the interval changes), the change is deferred to the next renewal.
  - Otherwise it's an upgrade, billed now. The credit and charge lines are each calculated exactly at the current interval's prices and then rounded half-up on their own. A negative total is rejected. If the upgrade also asks for an interval switch, that switch becomes the pending change.
- **Renewal:** the renewal step now applies and clears any pending change. Because of that, when several missed periods are caught up at once, the change applies to the first and later periods continue on the new plan.
- **Errors and exports:** I added `InvalidPlanChange(BillingError)` and exported it from the `billing` package. I also exported the new `PlanChange` type.

**One choice where the spec allowed either option:** when an upgrade's total rounds to exactly 0.00, the method records the invoice and returns it, rather than returning `None`.

I also updated the README's layout list and conventions to describe plan changes. Nothing is committed yet.

### [review1] operator

Review the changes since commit 0a16a9bc5ee48679637b9591fdbfb1a96e5e93df (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I found no correctness gaps against SPEC.md. Nothing needs fixing.

I compared every acceptance criterion (1–31) and the worked examples with the diff. I also ran the full suite, including `tests/acceptance/`: 156 tests passed.

- **Rejection order (1–8):** errors come in the order the spec requires. Unknown or canceled subscription is checked first, then unknown or retired plan, then the overdue renewal and negative-total checks. The retired-plan rule lets you move off a retired plan, rejects an interval switch that stays on one, and still allows a request for the current plan and interval. Every rejection happens before anything is saved, so a failed request leaves the subscription and invoices untouched.
- **Same plan and interval (9–10):** a pending change is cancelled and the call returns `None`. If nothing is pending, it raises `InvalidPlanChange`.
- **Trials (11–13):** the plan and interval switch immediately and nothing is billed. The trial end date and status stay the same, and the renewal bills whatever the subscription is on by then.
- **Upgrades (14–20):**
  - Plans are compared on monthly list price, and the proration uses the prices of the interval the customer is on now.
  - The credit and charge lines are each rounded half-up on their own, and the total is the sum of the two rounded lines.
  - The billing period never restarts, and any pending change is cleared, unless the upgrade also switches interval, in which case the switch becomes the pending change (`src/billing/service.py:132-135`).
- **Downgrades and interval switches (21–24):** these are stored as the single pending change, which replaces any earlier one. Equal monthly prices count as a downgrade, as the spec decides.
- **Renewal (25–28):**
  - `_renew` applies the pending change to the first renewal and then clears it, so when several missed periods are caught up, the later ones renew on the new plan and interval.
  - A pending change still applies if its target plan was retired after it was scheduled.
  - Canceled subscriptions are skipped, so their pending change never takes effect.
- **General (29–31):** `pending_change` is stored on the `Subscription` in the store, so a new `BillingService` over the same store sees and applies it. `InvalidPlanChange` is exported from the `billing` package, and the existing tests pass unmodified.

FINDINGS: 0
