"""Ground-truth fixture for the text2sql v2 benchmark (devlog #57).

Single source of truth: ROWS defines the seed data; the SAME rows emit the
Oracle seed SQL AND feed the golden-answer computations in tasks.py. So golden
values stay arithmetically consistent with the loaded data by construction —
no hand-typed expected numbers to drift.

The fixture is deliberately shaped to make each domain trap *distinguishable*:
two-step AVG ≠ direct AVG ≠ SUM for balances; PNL_SUM > Σcomponents (an "other
income" remainder); a current UNCLOSED month whose MONTH_DT is not EOM; and a
VED two-period stop. See ../text2sql-v2-design.md.
"""
from __future__ import annotations

# 35-column schema of client_product (matches dev/setup-oracle.sql).
COLUMNS = [
    "MONTH_DT", "CREATE_DT", "CLOSE_DT",
    "CUSTOMER_ID", "INN", "ORGANIZATION_NM", "GROUP_NM", "SEG",
    "DESK", "HUB", "MANAGER_NAME",
    "CA_LCY_SUM", "CA_LCY_RUB_SUM", "DEP_SUM",
    "FX_VOLUME_RUB", "FX_CNT", "FX_MARGIN_RUB",
    "FX_EUR_MARGIN_RUB", "FX_EUR_VOLUME_RUB", "FX_EUR_CNT",
    "FX_CNY_MARGIN_RUB", "FX_CNY_VOLUME_RUB", "FX_CNY_CNT",
    "PNL_SUM", "PL_CA", "PL_DEP", "PL_VK", "PL_VK_OUT", "VED_SUM",
    "VED_VOL", "SALARY_PROJECT",
    "ACT_1M", "ACT_3M", "PREV_ACT_1M", "PREV_ACT_3M",
]

# Periods used by the tasks. Closed months use EOM dates; the current month is
# deliberately NOT end-of-month (lagging snapshot, as on prod).
Q1_2024 = ["2024-01-31", "2024-02-29", "2024-03-31"]
Q3_2025 = ["2025-07-31", "2025-08-31", "2025-09-30"]
Q4_2025 = ["2025-10-31", "2025-11-30", "2025-12-31"]
CURRENT_MONTH = "2026-04-22"   # MAX(MONTH_DT); EOM would be 2026-04-30

# Clients: (INN, name, SEG, GROUP_NM)
CLIENTS = {
    1001: ("ООО ШАЙДЕР ГРУП", "International", None),
    1002: ("ПАО ЛУКОЙЛ", "Large", "ЛУКОЙЛ ГРУППА"),
    1003: ("ООО ЛУКОЙЛ-ЗАПАД", "Large", "ЛУКОЙЛ ГРУППА"),
    1004: ("ООО СУХОЙ ПОРТ", "Middle", None),
    1005: ("АО ГАЗПРОМ-ТРЕЙД", "International", None),
    1006: ("ООО РОМАШКА", "SME", None),
}

# Per-client Q1-2024 monthly CA_LCY_SUM (balances vary so two-step AVG over the
# quarter differs from a direct AVG over rows and from a SUM).
_CA_Q1 = {
    1001: [100, 200, 300],
    1002: [1000, 1000, 1000],
    1003: [2000, 2000, 2000],
    1004: [30, 60, 90],
    1005: [400, 400, 400],
    1006: [10, 20, 30],
}

# Per-client income components, constant across Q1 months. PNL_SUM is the total;
# for 1002 it exceeds the sum of listed components (an "other income" remainder).
# fields: PL_CA, PL_DEP, PL_VK, PL_VK_OUT, FX_MARGIN_RUB, VED_SUM, PNL_SUM
_PNL_Q1 = {
    1001: dict(PL_CA=10, PL_DEP=5,  PL_VK=2,  PL_VK_OUT=1, FX_MARGIN_RUB=3,  VED_SUM=4,  PNL_SUM=25),
    1002: dict(PL_CA=100, PL_DEP=50, PL_VK=20, PL_VK_OUT=10, FX_MARGIN_RUB=30, VED_SUM=40, PNL_SUM=300),
    1003: dict(PL_CA=20, PL_DEP=10, PL_VK=5,  PL_VK_OUT=5, FX_MARGIN_RUB=10, VED_SUM=0,  PNL_SUM=50),
    1004: dict(PL_CA=0,  PL_DEP=0,  PL_VK=0,  PL_VK_OUT=0, FX_MARGIN_RUB=0,  VED_SUM=0,  PNL_SUM=0),
    1005: dict(PL_CA=40, PL_DEP=0,  PL_VK=0,  PL_VK_OUT=0, FX_MARGIN_RUB=20, VED_SUM=0,  PNL_SUM=60),
    1006: dict(PL_CA=5,  PL_DEP=0,  PL_VK=1,  PL_VK_OUT=0, FX_MARGIN_RUB=0,  VED_SUM=0,  PNL_SUM=6),
}

# VED_VOL by client per quarter (T8 two-period stop). Q4 absence of a client
# also counts as "stopped" (the IS NULL case).
_VED_Q3 = {1001: 0, 1002: 500, 1005: 300, 1006: 200}
_VED_Q4 = {1001: 0, 1002: 0,   1005: 300}            # 1006 absent in Q4 entirely
_CURRENT_PNL = {1001: 100, 1002: 200, 1005: 300}     # rows at CURRENT_MONTH


def _row(inn: int, month: str, **over) -> dict[str, object]:
    name, seg, grp = CLIENTS[inn]
    r: dict[str, object] = {c: 0 for c in COLUMNS}   # numeric columns default to 0
    r.update({
        "MONTH_DT": month, "CREATE_DT": "2020-01-15", "CLOSE_DT": None,
        "CUSTOMER_ID": inn, "INN": inn, "ORGANIZATION_NM": name,
        "GROUP_NM": grp, "SEG": seg, "DESK": "DESK_A", "HUB": "Москва",
        "MANAGER_NAME": "Иванов", "SALARY_PROJECT": None,
        "ACT_1M": 1, "ACT_3M": 1, "PREV_ACT_1M": 1, "PREV_ACT_3M": 1,
    })
    r.update(over)
    return r


def build_rows() -> list[dict]:
    rows: list[dict] = []
    # Q1 2024: all clients, all 3 months — balances + income components.
    for inn in CLIENTS:
        for i, month in enumerate(Q1_2024):
            rows.append(_row(inn, month, CA_LCY_SUM=_CA_Q1[inn][i], **_PNL_Q1[inn]))
    # Q3 2025: VED activity for a subset.
    for inn, ved in _VED_Q3.items():
        for month in Q3_2025:
            rows.append(_row(inn, month, VED_VOL=ved))
    # Q4 2025: VED activity (1006 deliberately absent).
    for inn, ved in _VED_Q4.items():
        for month in Q4_2025:
            rows.append(_row(inn, month, VED_VOL=ved))
    # Current unclosed month.
    for inn, pnl in _CURRENT_PNL.items():
        rows.append(_row(inn, CURRENT_MONTH, PNL_SUM=pnl))
    return rows


ROWS = build_rows()


def _sql_val(col: str, v) -> str:
    if v is None:
        return "NULL"
    if col in ("MONTH_DT", "CREATE_DT", "CLOSE_DT"):
        return f"DATE '{v}'"
    if isinstance(v, str):
        return "'" + v.replace("'", "''") + "'"
    return str(v)


def make_seed_sql() -> str:
    cols = ", ".join(COLUMNS)
    lines = [
        "-- AUTO-GENERATED by fixture.py — do not edit by hand.",
        "ALTER SESSION SET CURRENT_SCHEMA = DEV_USER;",
        "DELETE FROM client_product;",
    ]
    for r in ROWS:
        vals = ", ".join(_sql_val(c, r[c]) for c in COLUMNS)
        lines.append(f"INSERT INTO client_product ({cols}) VALUES ({vals});")
    lines.append("COMMIT;")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    import pathlib
    out = pathlib.Path(__file__).with_name("seed.sql")
    out.write_text(make_seed_sql(), encoding="utf-8")
    print(f"wrote {out} ({len(ROWS)} rows)")
