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

I've read the whole package: `subscribe` / `renew_due` / `cancel`, frozen dataclasses, half-open periods, no credit-balance concept, and invoice lines can already be negative. Here's the first round. Each question has my recommendation, so "agree" is a complete answer.

**1. When does each kind of change take effect?**
- (a) Everything takes effect immediately and is prorated today.
- (b) Upgrades take effect immediately. Downgrades are scheduled for the end of the current period, so `change_plan` returns `None` and the next renewal bills the new plan.
- *Recommendation: (b).* It's the common SaaS pattern, it's the most natural reading of "return `None` when nothing is billed at the moment", and it avoids issuing refunds. You decide whether that's actually what you want.

**2. If anything can produce a credit (an immediate downgrade, or a switch from annual to monthly), what happens to the money?**
- (a) Issue an invoice with a negative total, i.e. a credit note (refunding it is someone else's job).
- (b) Carry the credit forward against future invoices. That needs a credit balance, which doesn't exist today.
- (c) Forfeit it.
- *Recommendation:* if you pick 1(b), mostly avoid the question by deferring anything that would create a credit. Otherwise (a).

**3. How do we define "upgrade" vs "downgrade", especially across intervals?** Example: pro monthly ($30) to basic annual ($100).
- *Recommendation:* compare the cost per day of the new plan+interval against the current one. Higher means upgrade (immediate), lower or equal means downgrade (deferred).

**4. What happens to the billing period on an immediate change?**
- (a) Same interval: keep the current `period_end` and charge only the difference for the days left.
- (b) Interval switch, e.g. monthly to annual: start a fresh period today, charge the full new-interval price, and subtract the unused days of the old period as a credit line on the same invoice.
- *Recommendation:* both of the above.

**5. Proration arithmetic.**
- *Recommendation:* by calendar day. Today counts as a day on the new plan. Unused fraction = `(period_end − today) / (period_end − period_start)`. Each line is rounded to cents half-up. The invoice has two lines (a credit for the unused old plan and a charge for the new plan) rather than a single net line. OK?

**6. Edge cases. My proposed answers:**
- Subscription is canceled: `SubscriptionNotActive`.
- Unknown plan: `PlanNotFound`.
- Retired target plan: `PlanNotAvailable`. Leaving a retired plan is allowed.
- Same plan and same interval: `InvalidPlanChange`.
- Subscription is in its trial: switch plan/interval right away, bill nothing, keep the trial end date, return `None`.
- A renewal is overdue (`period_end <= today`, `renew_due` not yet run): `InvalidPlanChange`, rather than silently renewing first. Or would you rather the change run the overdue renewal itself?

**7. Pending (scheduled) changes, if you choose 1(b):**
- *Recommendation:* at most one pending change per subscription. A new `change_plan` call replaces it. Requesting the current plan+interval clears it instead of raising an error. An upgrade clears any pending downgrade. Canceling drops it. Do we also need a way to inspect the pending change (a field on `Subscription`)?

### [spec] user

Answers by number:

**1.** Agree with (b), with one addition. A switch between monthly and annual also waits for the end of the period, in both directions. We never refund unused annual time. Nothing is billed at the request, and `change_plan` returns `None`. The renewal on the period end starts a period of the new interval at that interval's full price.

**2.** No credit should ever arise. Downgrades and interval switches are deferred, so nothing is refunded, credited or forfeited. No credit balance is needed.

**3.** Don't use cost per day. Compare the plans' monthly list prices, whichever interval the customer is on or moving to. A more expensive plan is an upgrade and a cheaper one is a downgrade. Your Pro monthly to Basic annual example is a downgrade, so it is deferred. Changing only the interval on the same plan is neither.

**4.** Not as you proposed.
- (a) An upgrade never moves the billing period. The start and end stay the same, and the next renewal bills the new plan at full price.
- (b) An interval switch never starts a new period today. It happens at the period end.
- An upgrade combined with an interval switch is split. The upgrade applies now, prorated at the prices of the current interval. The interval switch is scheduled for the period end.

**5.** Mostly agree.
- Remaining days count from the change date, inclusive, up to `period_end`, exclusive. Days in the period are real calendar days.
- Each of the two lines is price × remaining days ÷ period days, computed exactly with no rounded daily rate. Each is rounded half-up to cents on its own, and the total is the sum of the two rounded lines.
- Both lines use the prices of the interval the customer is currently on.
- Example: Pro to Premium on Mar 11 in a Mar 1–Apr 1 period gives −20.32 and +50.81, total 30.49.

**6.**
- Canceled raises `SubscriptionNotActive`, unknown plan raises `PlanNotFound`, and a retired target raises `PlanNotAvailable`. Leaving a retired plan is allowed.
- Same plan and same interval depends on state. If a change is scheduled, the request cancels it, returns `None` and bills nothing. If nothing is scheduled, raise `InvalidPlanChange`.
- Trial: any change applies immediately in full, covering plan and interval, whether up, down or interval. It returns `None` with no invoice, and the trial end date doesn't move. At trial end the customer is billed the full price of the plan and interval they are on by then.
- Overdue renewal: I don't mind, so use your recommendation.
- Any rejected request changes nothing, with no invoice and the subscription untouched.

**7.** Agree with one pending change at a time. Each request states the full target (plan and interval) and replaces whatever was scheduled. An upgrade applied now also discards anything scheduled, unless the same request schedules an interval switch itself. A scheduled change hasn't happened yet, so an upgrade requested while a downgrade is pending is prorated from the current plan. Example: on Pro with Basic scheduled, then Premium requested on Mar 11, the invoice is 30.49. How the pending change is stored on `Subscription` is up to you.

### [spec] agent

That settles almost everything. Your examples check out, assuming Premium is $75/month: 30 × 21/31 = 20.32 and 75 × 21/31 = 50.81. A few gaps remain, mostly created by the new rules:

**8. Monthly and annual prices that rank differently.** Upgrades are classified by monthly price but prorated at the current interval's prices. Suppose plan X is $40/month but $350/year and plan Y is $35/month but $380/year. An annual customer "upgrading" from Y to X would then get a negative proration, which is a credit. Options:
- (a) Reject with `InvalidPlanChange`.
- (b) Treat it as an upgrade anyway and allow the credit.
- (c) Classify by the current interval's price instead.
- *Recommendation: (a).* It keeps "no credit ever arises" true.

**9. Equal monthly prices on different plans.** Two plans can have the same monthly list price. Is a switch between them deferred like a downgrade, or rejected?
- *Recommendation:* defer it to the period end, like a downgrade.

**10. Upgrade whose rounded total is $0.00.** Example: $10.00 to $10.01 on the last day of a period. Both lines round to 0.32.
- *Recommendation:* still apply the upgrade now and issue the two-line invoice with a 0.00 total, so the change has a record.
- The alternative is to apply it and return `None`.

**11. Retirement and scheduled changes.**
- (a) Suppose a downgrade to Basic is scheduled, then Basic is retired before the period end. *Recommendation:* the scheduled change still applies, since it was sold while Basic was active.
- (b) Suppose the customer is on a retired plan and asks only to switch interval, keeping the same plan. That plan is the "target", but they aren't buying a new plan. *Recommendation:* allow it.

**12. Catch-up renewals.** If `renew_due` bills several overdue periods at once, the scheduled change applies at the first renewal, and every later period in the catch-up is on the new plan and interval. I'm assuming this; tell me if you disagree.

### [check] operator

Read SPEC.md. Turn every acceptance criterion into tests under tests/acceptance/, exercising only the public interface the spec names. Take expected values from the spec, not from the code. Do not implement the feature: these tests should fail for now. Report the command you ran and its output.

### [check] agent

I stopped before writing any tests because there's no SPEC.md in this workspace (`/tmp/pab-work-busy/T1-billing-proration-R-3/ws`).

**What I ran:**
```
$ cat SPEC.md
cat: SPEC.md: No such file or directory
```
The repo has one commit ("base"), and SPEC.md isn't in it. The tracked files are `README.md`, `pyproject.toml`, `src/billing/*` and the existing tests in `tests/`. None of them contain acceptance criteria. The README only covers the current features (plans, subscriptions, invoices, subscribe/renew/cancel) and says nothing about proration.

**What I didn't do:** A search turned up SPEC.md files in nearby directories, including `/tmp/pab-work/T1-billing-proration-R-3/ws/SPEC.md` (under `pab-work`, not `pab-work-busy`). I didn't use any of them. They're outside this workspace, and I can't tell whether they match what you want here. Writing tests from one of them would mean taking expected values from a source you didn't point me to, which defeats the point of spec-driven tests.

Nothing has been written or changed. To go ahead, either:
1. add SPEC.md to this workspace, or
2. confirm that `/tmp/pab-work/T1-billing-proration-R-3/ws/SPEC.md` (or another path) is the spec you mean.

Then I'll write the tests in `tests/acceptance/`, run `python3 -m pytest -q tests/acceptance`, and report the command and its output.

### [check] user

Yes, that's the spec from our interview. I read /tmp/pab-work/T1-billing-proration-R-3/ws/SPEC.md and it matches what I told you. It's fine to use it as the source for the tests. I can't copy files into the workspace myself, so read it from that path and write the tests in tests/acceptance/ only, with no feature code.

### [check] agent

I wrote 112 acceptance tests under `tests/acceptance/`, covering all 31 criteria in SPEC.md, and all 112 fail for now, as they should. I didn't change any feature code. As you said, the spec came from `/tmp/pab-work/T1-billing-proration-R-3/ws/SPEC.md`.

**Command and output:**
```
$ python3 -m pytest -q tests/acceptance
...
112 failed in 0.33s
```
Every failure is caused by the missing feature, not by a mistake in a test:
```
     93  AttributeError: 'BillingService' object has no attribute 'change_plan'
     18  AttributeError: module 'billing.errors' has no attribute 'InvalidPlanChange'
      1  AttributeError: module 'billing' has no attribute 'InvalidPlanChange'
```
The existing tests still pass and don't clash with the new ones: `python3 -m pytest -q` gives `112 failed, 20 passed`.

**Files** (test names start with the criterion number they cover):
- `test_plan_change_rejections.py` — criteria 1–8: errors raised and which error wins when several apply; a rejected request leaves the stored subscription and invoices identical, and a pending change still applies at renewal.
- `test_plan_change_same_target.py` — 9–10
- `test_plan_change_trialing.py` — 11–13
- `test_plan_change_upgrades.py` — 14–20
- `test_plan_change_deferred.py` — 21–24
- `test_plan_change_renewal.py` — 25–28
- `test_plan_change_general.py` — 29–31
- `conftest.py` and `plan_change_support.py` — setup with the spec's Basic, Pro and Premium plans. The helpers live in a separately named module so they don't clash with `tests/conftest.py`.

**How the tests are built:**
- **Only the named interface.** Tests call `change_plan`, `InvalidPlanChange`, the existing `subscribe`/`renew_due`/`cancel`, and the store's public methods. The spec doesn't say how a pending change is stored, so tests check for one by its effects: what the next renewal bills, and whether asking for the current plan cancels it or raises an error.
- **Expected values from the spec.** The five worked examples are used exactly (for example 30.49, 100.82, 13.55). For the extra cases (a 366-day period, a line that lands on exactly half a cent, plans with equal monthly prices, and negative and zero totals) I worked out the amounts by hand with the spec's formula.
- **Criterion 20** lets a zero-total upgrade either record an invoice or return `None`, so that test accepts both. It only checks that the return value matches what was recorded.

**Where I had to interpret the spec:**
- **Criterion 4 with criterion 10:** on a retired plan, asking for the current plan and interval with nothing pending is expected to raise `InvalidPlanChange`, not `PlanNotAvailable`. My reading is that criterion 4 exempts this request and criterion 10 then applies.
- **Rounding:** the half-cent rounding test puts the half cent on the charge line only. That's because the spec doesn't say how "half-up" rounds a negative credit.
- **Criterion 31:** it also requires the existing suite to keep passing. That is checked by running the full suite, not by a separate test.

The pytest run also created an untracked `tests/__pycache__/` directory; I left it in place.

### [build] operator

Build what SPEC.md describes. tests/acceptance/ is the agreed check and is read-only for you. Done means tests/acceptance/ and the existing test suite pass; report the command and its output.

### [build] agent

I added `BillingService.change_plan(subscription_id, plan_code, new_interval=None)`, and all tests pass: the 112 acceptance tests and the 20 existing ones.

**SPEC.md isn't in the repo.** It isn't tracked in git and isn't on disk. The acceptance tests are numbered against its criteria (1–31) and cover the behaviour in detail, so I built to them. Where they don't decide something, I made the call myself (listed below). If you have SPEC.md, it's worth checking those calls against it.

**Command and output:**
```
$ python3 -m pytest -q
........................................................................ [ 54%]
............................................................             [100%]
132 passed in 0.05s
```

**How a plan change works now:**
- **Pending changes are saved on the subscription** as `pending_plan_code` and `pending_interval`, so a second `BillingService` over the same store sees them. At renewal, the pending plan and interval are billed at full price and then cleared. Each missed renewal is billed on the new terms, a pending change to a plan retired since then still goes through, and canceled subscriptions are never renewed.
- **Upgrade** (target has a higher monthly list price): the plan changes immediately and the period stays the same. You get one invoice dated today with two lines: a credit for the unused days on the old plan and a charge for those days on the new plan. Both use the current interval's prices and are rounded half-up separately. If the upgrade also asks for a different interval, that switch waits for the renewal.
- **Downgrade, or an interval switch alone:** saved for the next renewal; nothing is billed or refunded now, and the method returns `None`.
- **During a trial:** applied right away with no invoice; the trial end date and status stay as they were.
- **Same plan and interval as now:** cancels the pending change, or raises `InvalidPlanChange` if nothing is pending.
- **Rejections, checked in this order:** unknown subscription, canceled subscription, unknown plan, retired target (unless it's the current plan and interval), an unbilled renewal or trial end, then an upgrade whose total would be negative. A rejected request changes nothing.
- **`InvalidPlanChange`** is new in `billing/errors.py` and exported from `billing`. I also added `change_plan` to the README's layout table.

**Calls I made where the tests don't decide:**
- An upgrade that nets to 0.00 still records and returns its invoice. The test accepts either that or returning `None`.
- If a renewal is overdue, a request to go back to the current plan is rejected, even when it would cancel a pending change.
- Canceling a subscription leaves its pending change in place. It has no effect because canceled subscriptions never renew.

Nothing is committed. The working tree has changes in `src/billing/` and `README.md`; the untracked `tests/acceptance/` is unchanged.

### [review1] operator

Review the changes since commit 1fd34714dcc48db28af608d2f0676f74de148967 (committed and uncommitted) against SPEC.md. Report only gaps that affect correctness, each with file:line; skip style. If there is nothing to fix, say so. End with one line: FINDINGS: <number>.

### [review1] agent

I couldn't do the review because this repo has no SPEC.md to check against.

- **It doesn't exist here.** There's no SPEC.md in the workspace (`/tmp/pab-work-busy/T1-billing-proration-R-3/ws`), and the only commit, `1fd3471 base`, never included one. It isn't among the uncommitted or untracked files either.
- **The changes add a `change_plan` operation.** They touch `service.py`, `subscriptions.py`, `errors.py`, `__init__.py` and README, and add a `tests/acceptance/` suite for plan changes. Without the spec I can't tell which behaviour is required and which is a real gap.
- **Copies exist in other directories.** The closest is `/tmp/pab-work/T1-billing-proration-R-3/ws/SPEC.md`, which has the same task name under a different root. I didn't use it: it belongs to a separate workspace and may not be the spec meant for these changes.

To go ahead, either point me at the right SPEC.md (that path, if it's the right one) or paste the spec, and I'll run the review.

FINDINGS: 0 (review not performed — SPEC.md missing)
