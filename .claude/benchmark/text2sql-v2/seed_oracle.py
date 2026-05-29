"""Load the fixture into an ISOLATED bench table — never the app's client_product.

Clones the canonical schema (`CREATE TABLE <bench> AS SELECT * FROM client_product
WHERE 1=0`), then bulk-inserts fixture.ROWS. Config from env only
(AI_ANALYST_ORACLE_USERNAME/PASSWORD/DSN or ORACLE_*; BENCH_TABLE, default
client_product_bench). Idempotent: drops+recreates the bench table each run.
"""
from __future__ import annotations

import datetime
import os

import fixture as F


def _conv(col: str, val):
    if val is None:
        return None
    if col in ("MONTH_DT", "CREATE_DT", "CLOSE_DT"):
        return datetime.date.fromisoformat(val)
    return val


def main() -> None:
    import oracledb  # lazy: not a hard dependency of the package

    user = os.getenv("AI_ANALYST_ORACLE_USERNAME") or os.getenv("ORACLE_USER")
    pwd = os.getenv("AI_ANALYST_ORACLE_PASSWORD") or os.getenv("ORACLE_PASSWORD")
    dsn = os.getenv("AI_ANALYST_ORACLE_DSN") or os.getenv("ORACLE_DSN")
    table = os.getenv("BENCH_TABLE", "client_product_bench")
    if not (user and pwd and dsn):
        raise SystemExit("Set AI_ANALYST_ORACLE_USERNAME/PASSWORD/DSN (or ORACLE_*) env.")

    conn = oracledb.connect(user=user, password=pwd, dsn=dsn)
    cur = conn.cursor()
    cur.execute(
        f"BEGIN EXECUTE IMMEDIATE 'DROP TABLE {table}'; "
        f"EXCEPTION WHEN OTHERS THEN NULL; END;"
    )
    cur.execute(f"CREATE TABLE {table} AS SELECT * FROM client_product WHERE 1=0")

    cols = ", ".join(F.COLUMNS)
    binds = ", ".join(f":{i + 1}" for i in range(len(F.COLUMNS)))
    data = [[_conv(c, r[c]) for c in F.COLUMNS] for r in F.ROWS]
    cur.executemany(f"INSERT INTO {table} ({cols}) VALUES ({binds})", data)
    conn.commit()

    cur.execute(f"SELECT COUNT(*), TO_CHAR(MAX(MONTH_DT),'YYYY-MM-DD') FROM {table}")
    n, maxd = cur.fetchone()
    print(f"loaded {n} rows into {table}; MAX(MONTH_DT)={maxd}")
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
