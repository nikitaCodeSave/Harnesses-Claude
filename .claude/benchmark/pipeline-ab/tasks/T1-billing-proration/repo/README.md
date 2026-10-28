# billing

Subscription billing core: plans with monthly and annual list prices, subscriptions with
billing periods and optional free trials, invoices with line items. Pure Python 3.12, no
runtime dependencies.

## Layout

```
src/billing/
  money.py          Decimal helpers (to_money: quantize to cents, half up)
  clock.py          Clock protocol + FixedClock
  plans.py          Plan, Interval
  periods.py        month arithmetic, period_end()
  subscriptions.py  Subscription, SubscriptionStatus
  invoices.py       Invoice, LineItem
  store.py          InMemoryStore (plans, subscriptions, invoices)
  service.py        BillingService: subscribe / renew_due / cancel
```

## Conventions

- Money is always `Decimal` in whole cents; build amounts with `to_money()`. Floats raise.
- No code calls the system clock. `BillingService` gets a `Clock`; tests use `FixedClock`.
- Domain objects are frozen dataclasses. Change one with `dataclasses.replace` and save it
  through the store.
- Billing periods are half-open `[period_start, period_end)`; the renewal is billed on
  `period_end`. Month arithmetic clamps to the end of shorter months.
- Retired plans (`active=False`) cannot be sold; existing customers keep renewing on them.
- Domain failures raise subclasses of `billing.errors.BillingError`.

## Tests

```
python3 -m pytest -q
```
