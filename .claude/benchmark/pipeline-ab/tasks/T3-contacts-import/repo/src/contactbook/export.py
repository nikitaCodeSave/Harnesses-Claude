"""CSV export of contacts."""

from __future__ import annotations

import csv
import io
from collections.abc import Iterable

from .models import Contact

EXPORT_COLUMNS = ("name", "email", "phone", "tags")
TAG_SEPARATOR = ";"


def export_csv(contacts: Iterable[Contact]) -> str:
    """Render contacts as CSV text with a header row.

    One row per contact; tags are sorted and joined with TAG_SEPARATOR in a
    single cell, and a contact without a phone gets an empty phone cell.
    """
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(EXPORT_COLUMNS)
    for contact in contacts:
        writer.writerow(
            [
                contact.name,
                contact.email,
                contact.phone or "",
                TAG_SEPARATOR.join(sorted(contact.tags)),
            ]
        )
    return buffer.getvalue()
