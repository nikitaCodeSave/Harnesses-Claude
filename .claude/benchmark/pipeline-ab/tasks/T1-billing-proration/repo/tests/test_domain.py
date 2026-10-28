from datetime import date
from decimal import Decimal

import pytest

from billing.errors import InvalidPlan, InvoiceError
from billing.invoices import Invoice, LineItem
from billing.plans import Interval, Plan


def test_plan_rejects_sub_cent_price():
    with pytest.raises(InvalidPlan):
        Plan("odd", "Odd", Decimal("9.999"), Decimal("99.00"))


def test_plan_rejects_negative_price():
    with pytest.raises(InvalidPlan):
        Plan("neg", "Negative", Decimal("-1.00"), Decimal("10.00"))


def test_plan_price_for_interval():
    plan = Plan("pro", "Pro", Decimal("30"), Decimal("300"))
    assert plan.price_for(Interval.ANNUAL) == Decimal("300.00")


def test_invoice_total_sums_lines():
    invoice = Invoice(
        id="inv_1",
        subscription_id="sub_1",
        customer_id="cus_1",
        issued_on=date(2026, 1, 1),
        lines=(LineItem("a", Decimal("10.00")), LineItem("b", Decimal("-2.50"))),
    )
    assert invoice.total == Decimal("7.50")


def test_invoice_needs_at_least_one_line():
    with pytest.raises(InvoiceError):
        Invoice(id="inv_1", subscription_id="s", customer_id="c", issued_on=date(2026, 1, 1), lines=())
