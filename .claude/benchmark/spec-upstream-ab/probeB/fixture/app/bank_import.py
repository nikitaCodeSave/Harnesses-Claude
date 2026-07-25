"""Импорт дневной банковской выгрузки в биллинг."""

import csv
import hashlib
import logging
import sqlite3

log = logging.getLogger(__name__)

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY,
    number TEXT UNIQUE NOT NULL,
    balance INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS postings (
    payment_id TEXT NOT NULL,
    account_id INTEGER NOT NULL,
    amount INTEGER NOT NULL,
    state TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS posting_audit (
    payment_id TEXT NOT NULL,
    old_amount INTEGER,
    new_amount INTEGER,
    changed_at TEXT NOT NULL
);
"""


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


def file_digest(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def import_file(conn: sqlite3.Connection, path: str) -> int:
    """Разносит выгрузку. Возвращает число применённых строк."""
    digest = file_digest(path)
    log.info("importing file %s (%s)", path, digest[:12])

    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    applied = 0
    for idx, row in enumerate(rows, start=1):
        _apply_row(conn, row)
        conn.commit()
        applied += 1
        print(f"  [{idx}/{len(rows)}] {row['payment_id']}")
    return applied


def _apply_row(conn: sqlite3.Connection, row: dict) -> None:
    log.info(
        "payment %s account=%s phone=%s",
        row["payment_id"],
        row["account"],
        row["phone"],
    )
    amount = int(row["amount"])

    account = conn.execute(
        f"SELECT id, balance FROM accounts WHERE number = '{row['account']}'"
    ).fetchone()
    if account is None:
        raise ValueError(f"unknown account for payment {row['payment_id']}")
    account_id, balance = account

    existing = conn.execute(
        "SELECT amount FROM postings WHERE payment_id = ? AND state = 'active'",
        (row["payment_id"],),
    ).fetchone()

    if existing is None:
        conn.execute(
            "INSERT INTO postings (payment_id, account_id, amount) VALUES (?, ?, ?)",
            (row["payment_id"], account_id, amount),
        )
        conn.execute(
            "UPDATE accounts SET balance = ? WHERE id = ?", (balance + amount, account_id)
        )
        return

    old_amount = existing[0]
    if old_amount == amount:
        return

    conn.execute(
        "UPDATE postings SET state = 'annulled' WHERE payment_id = ? AND state = 'active'",
        (row["payment_id"],),
    )
    conn.execute(
        "INSERT INTO postings (payment_id, account_id, amount) VALUES (?, ?, ?)",
        (row["payment_id"], account_id, amount),
    )
    conn.execute(
        "INSERT INTO posting_audit (payment_id, old_amount, new_amount, changed_at)"
        " VALUES (?, ?, ?, datetime('now'))",
        (row["payment_id"], old_amount, amount),
    )
    conn.execute(
        "UPDATE accounts SET balance = ? WHERE id = ?",
        (balance - old_amount + amount, account_id),
    )
