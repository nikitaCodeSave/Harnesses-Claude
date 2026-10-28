from datetime import date
from decimal import Decimal

import pytest

from billing.money import to_money
from billing.periods import add_months, period_end
from billing.plans import Interval


def test_to_money_rounds_half_up_to_cents():
    assert to_money(Decimal("2.345")) == Decimal("2.35")


def test_to_money_rejects_floats():
    with pytest.raises(TypeError):
        to_money(1.5)


def test_add_months_clamps_to_end_of_shorter_month():
    assert add_months(date(2026, 1, 31), 1) == date(2026, 2, 28)


def test_add_months_crosses_year_boundary():
    assert add_months(date(2026, 11, 30), 3) == date(2027, 2, 28)


def test_annual_period_from_leap_day_ends_on_feb_28():
    assert period_end(date(2028, 2, 29), Interval.ANNUAL) == date(2029, 2, 28)
