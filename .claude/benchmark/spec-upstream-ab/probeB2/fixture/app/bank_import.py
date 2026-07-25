"""Импорт дневной банковской выгрузки в биллинг."""

import csv
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
    id INTEGER PRIMARY KEY,
    payment_id TEXT NOT NULL,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    amount INTEGER NOT NULL,
    state TEXT NOT NULL DEFAULT 'active'
);
CREATE INDEX IF NOT EXISTS postings_payment ON postings (payment_id);
"""


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


def import_file(conn: sqlite3.Connection, path: str) -> int:
    """Разносит выгрузку. Возвращает число применённых строк.

    Файл применяется целиком: при любой ошибке транзакция откатывается.
    """
    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    applied = 0
    try:
        conn.execute("BEGIN")
        for idx, row in enumerate(rows, start=1):
            if _apply_row(conn, row):
                applied += 1
            print(f"  [{idx}/{len(rows)}] {row['payment_id']}")
        conn.commit()
    except Exception:
        conn.rollback()
        log.error("import failed, file not applied: %s", path)
        raise
    return applied


def _apply_row(conn: sqlite3.Connection, row: dict) -> bool:
    """Применяет одну строку. True — состояние изменилось."""
    payment_id = row["payment_id"]
    amount = int(row["amount"])
    log.info("payment %s amount=%s", payment_id, amount)

    account = conn.execute(
        "SELECT id FROM accounts WHERE number = ?", (row["account"],)
    ).fetchone()
    if account is None:
        raise ValueError(f"unknown account for payment {payment_id}")
    account_id = account[0]

    existing = conn.execute(
        "SELECT id, amount FROM postings WHERE payment_id = ? AND state = 'active'",
        (payment_id,),
    ).fetchone()

    if existing is None:
        conn.execute(
            "INSERT INTO postings (payment_id, account_id, amount) VALUES (?, ?, ?)",
            (payment_id, account_id, amount),
        )
        conn.execute(
            "UPDATE accounts SET balance = balance + ? WHERE id = ?", (amount, account_id)
        )
        return True

    posting_id, old_amount = existing
    if old_amount == amount:
        return False

    conn.execute("UPDATE postings SET state = 'annulled' WHERE id = ?", (posting_id,))
    conn.execute(
        "INSERT INTO postings (payment_id, account_id, amount) VALUES (?, ?, ?)",
        (payment_id, account_id, amount),
    )
    conn.execute(
        "UPDATE accounts SET balance = balance + ? WHERE id = ?",
        (amount - old_amount, account_id),
    )
    return True
