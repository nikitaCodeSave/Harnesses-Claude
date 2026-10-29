from datetime import date
from decimal import Decimal

import pytest

from lending import CopyStatus, Material
from lending.errors import CopyNotAvailable, DuplicateCopy, DuplicateMember, TitleNotFound
from lending.reports import overdue_report


def test_member_ids_are_unique(service):
    with pytest.raises(DuplicateMember):
        service.register_member("ann", "Another Ann")


def test_copy_needs_a_known_title(service):
    with pytest.raises(TitleNotFound):
        service.add_copy("X1", "no-such-isbn")


def test_copy_ids_are_unique(service):
    with pytest.raises(DuplicateCopy):
        service.add_copy("B1", "978-1")


def test_withdrawn_copy_leaves_circulation(service):
    service.withdraw_copy("B2")
    assert service.get_copy("B2").status is CopyStatus.WITHDRAWN
    assert [c.copy_id for c in service.available_copies("978-1")] == ["B1"]
    with pytest.raises(CopyNotAvailable):
        service.checkout("ann", "B2")


def test_copy_on_loan_cannot_be_withdrawn(service):
    service.checkout("ann", "B1")
    with pytest.raises(CopyNotAvailable):
        service.withdraw_copy("B1")


def test_replacement_cost_is_kept_as_decimal(service):
    title = service.add_title("978-5", "Atlas", Material.BOOK, Decimal("45.50"))
    assert title.replacement_cost == Decimal("45.50")


def test_overdue_report_lists_longest_overdue_first(service, clock):
    service.checkout("ann", "B1")  # due 23 March
    service.checkout("kid", "D1")  # due 9 March
    lines = overdue_report(service, as_of=date(2026, 3, 25))
    assert [(l.copy_id, l.days_overdue) for l in lines] == [("D1", 16), ("B1", 2)]


def test_overdue_report_skips_returned_loans(service, clock):
    service.checkout("kid", "D1")
    clock.set(date(2026, 3, 12))
    service.return_copy("D1")
    assert overdue_report(service, as_of=date(2026, 3, 20)) == []
