import csv
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.bank_import import import_file, init_db  # noqa: E402

ROWS = [
    {"payment_id": "P-1", "account": "ACC-1", "amount": "100", "phone": "+79990000001"},
    {"payment_id": "P-2", "account": "ACC-2", "amount": "250", "phone": "+79990000002"},
]


def write_csv(path: Path, rows) -> Path:
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["payment_id", "account", "amount", "phone"])
        w.writeheader()
        w.writerows(rows)
    return path


def make_conn():
    conn = sqlite3.connect(":memory:")
    init_db(conn)
    conn.execute("INSERT INTO accounts (number, balance) VALUES ('ACC-1', 0)")
    conn.execute("INSERT INTO accounts (number, balance) VALUES ('ACC-2', 0)")
    conn.commit()
    return conn


def balances(conn):
    return dict(conn.execute("SELECT number, balance FROM accounts").fetchall())


def test_repeated_file_does_not_double_charge(tmp_path):
    conn = make_conn()
    path = write_csv(tmp_path / "day1.csv", ROWS)

    import_file(conn, str(path))
    after_first = balances(conn)
    import_file(conn, str(path))

    assert balances(conn) == after_first
    assert after_first == {"ACC-1": 100, "ACC-2": 250}


def test_changed_amount_is_correction_not_second_payment(tmp_path):
    conn = make_conn()
    import_file(conn, str(write_csv(tmp_path / "day1.csv", ROWS)))

    corrected = [dict(ROWS[0], amount="130"), ROWS[1]]
    import_file(conn, str(write_csv(tmp_path / "day1-fix.csv", corrected)))

    assert balances(conn)["ACC-1"] == 130
    active = conn.execute(
        "SELECT amount FROM postings WHERE payment_id = 'P-1' AND state = 'active'"
    ).fetchall()
    assert active == [(130,)]


def test_broken_file_leaves_nothing_applied(tmp_path):
    conn = make_conn()
    bad = [ROWS[0], dict(ROWS[1], account="ACC-MISSING")]
    path = write_csv(tmp_path / "bad.csv", bad)

    try:
        import_file(conn, str(path))
    except ValueError:
        pass

    assert balances(conn) == {"ACC-1": 0, "ACC-2": 0}
