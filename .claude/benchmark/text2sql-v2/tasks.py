"""Benchmark v2 task suite (MVP: T1/T3/T6/T8/T10) with golden answers and the
per-axis check specs. Golden is COMPUTED from fixture.ROWS so it can never drift
from the seed actually loaded into Oracle.

Each task:
  id, level, nl                — what the agent is asked.
  golden_kind, golden          — expected result (number | number_map | id_set).
  tol_pct                      — tolerance for numeric comparison (0 for sets).
  must_contain / must_not_contain — axis-2 SQL structural anchors (regex, i-flag).
  balance_field / multi_month  — axis-4 aggregation-semantics spec (or None).
"""
from __future__ import annotations

import fixture as F

_Q1, _Q3, _Q4 = set(F.Q1_2024), set(F.Q3_2025), set(F.Q4_2025)
_COMPONENTS = ["PL_CA", "PL_DEP", "PL_VK", "PL_VK_OUT", "FX_MARGIN_RUB", "VED_SUM"]


def _g_t1() -> float:
    return sum(r["PNL_SUM"] for r in F.ROWS if r["MONTH_DT"] == "2024-03-31")


def _g_t3() -> dict[str, float]:
    out: dict[str, float] = {}
    segs = {r["SEG"] for r in F.ROWS if r["MONTH_DT"] in _Q1}
    for seg in segs:
        monthly = []
        for m in F.Q1_2024:
            monthly.append(sum(r["CA_LCY_SUM"] for r in F.ROWS
                               if r["MONTH_DT"] == m and r["SEG"] == seg))
        out[seg] = sum(monthly) / len(monthly)   # two-step: SUM per month -> AVG
    return out


def _g_t6() -> dict[str, float]:
    out: dict[str, float] = {f: float(sum(r[f] for r in F.ROWS if r["MONTH_DT"] in _Q1))
                             for f in _COMPONENTS}
    pnl_total = float(sum(r["PNL_SUM"] for r in F.ROWS if r["MONTH_DT"] in _Q1))
    out["OTHER"] = pnl_total - sum(out.values())
    out["PNL_TOTAL"] = pnl_total
    return out


def _g_t8() -> list[int]:
    q3 = {}
    q4 = {}
    for r in F.ROWS:
        if r["MONTH_DT"] in _Q3:
            q3[r["INN"]] = q3.get(r["INN"], 0) + (r["VED_VOL"] or 0)
        elif r["MONTH_DT"] in _Q4:
            q4[r["INN"]] = q4.get(r["INN"], 0) + (r["VED_VOL"] or 0)
    return sorted(inn for inn, v in q3.items() if v > 0 and q4.get(inn, 0) <= 0)


def _g_t10() -> float:
    maxd = max(r["MONTH_DT"] for r in F.ROWS)
    return sum(r["PNL_SUM"] for r in F.ROWS if r["MONTH_DT"] == maxd)


TASKS = [
    dict(
        id="T1", level="easy",
        nl="Суммарный доход (PNL_SUM) по всем клиентам за март 2024 года.",
        golden_kind="number", golden=_g_t1(), tol_pct=0.01,
        must_contain=[r"sum\s*\(\s*pnl_sum", r"2024-03-31"],
        must_not_contain=[],
        balance_field=None, multi_month=False,
    ),
    dict(
        id="T3", level="medium",
        nl="Средние остатки на расчётных счетах (CA_LCY_SUM) по сегментам за 1 квартал 2024 года.",
        golden_kind="number_map", golden=_g_t3(), tol_pct=0.01,
        must_contain=[r"avg\s*\(", r"group\s+by"],
        must_not_contain=[r"avg\s*\(\s*ca_lcy_sum\s*\)"],   # forbid direct AVG on the raw column
        balance_field="CA_LCY_SUM", multi_month=True,
    ),
    dict(
        id="T6", level="hard",
        nl="Структура дохода по компонентам (PL_CA, PL_DEP, ВК свой+чужой банк, маржа FX, ВЭД, прочее) "
           "за 1 квартал 2024 года.",
        golden_kind="number_map", golden=_g_t6(), tol_pct=0.01,
        must_contain=[r"pl_ca", r"pl_dep", r"pl_vk", r"fx_margin_rub", r"ved_sum", r"pnl_sum"],
        must_not_contain=[r"pnl_sum\s*\+\s*pl_", r"pl_[a-z_]+\s*\+\s*pnl_sum"],  # total + component = double count
        balance_field=None, multi_month=False,
    ),
    dict(
        id="T8", level="hard",
        nl="Какие клиенты (ИНН) перестали проводить ВЭД-платежи в 4 квартале 2025 по сравнению с 3 кварталом?",
        golden_kind="id_set", golden=_g_t8(), tol_pct=0.0,
        must_contain=[r"ved_vol", r"(left\s+join|not\s+exists|minus|is\s+null)"],
        must_not_contain=[],
        balance_field=None, multi_month=False,
    ),
    dict(
        id="T10", level="medium",
        nl="Суммарный доход (PNL_SUM) за последний доступный (текущий) месяц.",
        golden_kind="number", golden=_g_t10(), tol_pct=0.01,
        must_contain=[r"max\s*\(\s*month_dt\s*\)"],
        must_not_contain=[r"2026-04-30"],   # naive synthesises EOM that has no rows
        balance_field=None, multi_month=False,
    ),
]

TASK_BY_ID = {t["id"]: t for t in TASKS}
