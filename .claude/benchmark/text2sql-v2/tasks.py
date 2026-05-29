"""Benchmark v2 task suite (T1-T10 + guardrails G1/G2) with golden answers and
the per-axis check specs. Golden is COMPUTED from fixture.ROWS so it can never
drift from the seed actually loaded into Oracle.

Each task:
  id, level, nl                — what the agent is asked.
  golden_kind, golden          — expected result
                                 (number | number_map | id_set | refusal).
  tol_pct                      — tolerance for numeric comparison (0 for sets).
  must_contain / must_not_contain — axis-2 SQL structural anchors (regex, i-flag).
  balance_field / multi_month  — axis-4 aggregation-semantics spec (or None).
"""
from __future__ import annotations

import fixture as F

_Q1, _Q3, _Q4 = set(F.Q1_2024), set(F.Q3_2025), set(F.Q4_2025)
_Q3_24, _Q4_24 = set(F.Q3_2024), set(F.Q4_2024)
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


def _g_t2() -> float:
    # Distinct clients, not COUNT(*) over the denormalised snapshot rows.
    return float(len({r["INN"] for r in F.ROWS}))


def _g_t4() -> dict[str, float]:
    # New clients per 2024 month, keyed by CREATE_DT month — not MONTH_DT.
    out: dict[str, float] = {}
    for inn, (_n, _s, _g) in F.CLIENTS.items():
        cdt = F._CREATE_DT[inn]
        if cdt and cdt.startswith("2024-"):
            key = cdt[:7]                      # "2024-MM"
            out[key] = out.get(key, 0.0) + 1.0
    return out


def _g_t5() -> dict[str, float]:
    # Flow field PNL_SUM -> SUM over each quarter; compare Q3 vs Q4 2024.
    q3 = float(sum(r["PNL_SUM"] for r in F.ROWS if r["MONTH_DT"] in _Q3_24))
    q4 = float(sum(r["PNL_SUM"] for r in F.ROWS if r["MONTH_DT"] in _Q4_24))
    delta = q4 - q3
    return {"q3": q3, "q4": q4, "delta": delta, "delta_pct": delta / q3 * 100.0}


def _g_t7() -> list[int]:
    # Top-3 clients by total PNL over Q1 2024 (the FX breakdown in the question
    # must stay scoped to exactly these INNs — the merge anchor).
    pnl: dict[int, float] = {}
    for r in F.ROWS:
        if r["MONTH_DT"] in _Q1:
            pnl[r["INN"]] = pnl.get(r["INN"], 0.0) + r["PNL_SUM"]
    top = sorted(pnl, key=lambda i: (-pnl[i], i))[:3]
    return sorted(top)


def _g_t9() -> dict[str, float]:
    # Per-segment mixed aggregation over Q1 2024:
    #   avg PNL        -> AVG of the flow field over rows
    #   avg balances   -> two-step AVG of CA_LCY_SUM (SUM per month -> AVG)
    #   sum FX         -> SUM of the flow field FX_VOLUME_RUB
    out: dict[str, float] = {}
    segs = {r["SEG"] for r in F.ROWS if r["MONTH_DT"] in _Q1}
    for seg in segs:
        q1 = [r for r in F.ROWS if r["MONTH_DT"] in _Q1 and r["SEG"] == seg]
        avg_pnl = sum(r["PNL_SUM"] for r in q1) / len(q1)
        monthly = [sum(r["CA_LCY_SUM"] for r in q1 if r["MONTH_DT"] == m)
                   for m in F.Q1_2024]
        avg_bal = sum(monthly) / len(monthly)
        sum_fx = float(sum(r["FX_VOLUME_RUB"] for r in q1))
        out[f"{seg}.avg_pnl"] = avg_pnl
        out[f"{seg}.avg_bal"] = avg_bal
        out[f"{seg}.sum_fx"] = sum_fx
    return out


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
        id="T2", level="easy",
        nl="Сколько всего клиентов в базе?",
        golden_kind="number", golden=_g_t2(), tol_pct=0.0,
        must_contain=[r"count\s*\(\s*distinct\s+inn\s*\)"],
        must_not_contain=[r"count\s*\(\s*\*\s*\)"],   # COUNT(*) counts snapshot rows
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
        id="T4", level="medium",
        nl="Сколько новых клиентов открылось в каждом месяце 2024 года?",
        golden_kind="number_map", golden=_g_t4(), tol_pct=0.0,
        must_contain=[r"create_dt", r"group\s+by"],
        must_not_contain=[r"min\s*\(\s*month_dt", r"group\s+by\s+month_dt"],  # MONTH_DT trap
        balance_field=None, multi_month=False,
    ),
    dict(
        id="T5", level="medium",
        nl="Сравни суммарный доход (PNL_SUM) в 3 и 4 квартале 2024 года: разница и процент.",
        golden_kind="number_map", golden=_g_t5(), tol_pct=0.01,
        must_contain=[r"sum\s*\(", r"pnl_sum", r"2024-07-31", r"2024-10-31"],
        must_not_contain=[],
        balance_field=None, multi_month=False,
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
        id="T7", level="hard",
        nl="Топ-3 клиента (ИНН) по доходу PNL за 1 квартал 2024 года и их FX-оборот (FX_VOLUME_RUB) "
           "по месяцам квартала.",
        golden_kind="id_set", golden=_g_t7(), tol_pct=0.0,
        must_contain=[r"pnl_sum", r"fx_volume_rub", r"(fetch\s+first|rownum|row_number|rank|dense_rank)"],
        must_not_contain=[],
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
    dict(
        id="T9", level="hard",
        nl="Сравни сегменты по среднему доходу (PNL_SUM), средним остаткам (CA_LCY_SUM) и суммарному "
           "FX-обороту (FX_VOLUME_RUB) за 1 квартал 2024 года.",
        golden_kind="number_map", golden=_g_t9(), tol_pct=0.01,
        # CA_LCY_SUM is the balance field whose two-step AVG axis-4 verifies; the
        # other two are flow fields (AVG/SUM as written by the agent).
        must_contain=[r"pnl_sum", r"ca_lcy_sum", r"fx_volume_rub", r"group\s+by"],
        must_not_contain=[r"avg\s*\(\s*ca_lcy_sum\s*\)"],   # direct AVG on the balance
        balance_field="CA_LCY_SUM", multi_month=True,
    ),
    dict(
        id="G1", level="guardrail",
        nl="Какова кредитная нагрузка и просрочка ПАО ЛУКОЙЛ на сегодня?",
        golden_kind="refusal", golden=None, tol_pct=0.0,
        must_contain=[], must_not_contain=[],
        balance_field=None, multi_month=False,
    ),
    dict(
        id="G2", level="guardrail",
        nl="Какая погода будет завтра в Москве?",
        golden_kind="refusal", golden=None, tol_pct=0.0,
        must_contain=[], must_not_contain=[],
        balance_field=None, multi_month=False,
    ),
]

# Per-task live result-shaping (how OracleExecutor maps DB rows -> golden form).
#   scalar    : single value (rows[0][0])
#   ids       : first column over all rows
#   map_kv    : 2 cols (key, value) over N rows               -> {key: value}
#   map_row   : 1 row, columns aliased to golden keys         -> {col: value}
#   map_pivot : key col + metric cols over N rows             -> {"{key}.{metric}": value}
#   refusal   : N/A (no SQL executed)
# map_row / map_pivot require the SQL to alias columns to the golden key names
# (case-insensitive); the AgentSolver prompt passes these as the output contract.
_SHAPES = {
    "T1": "scalar", "T2": "scalar", "T10": "scalar",
    "T3": "map_kv", "T4": "map_kv",
    "T5": "map_row", "T6": "map_row",
    "T9": "map_pivot",
    "T7": "ids", "T8": "ids",
    "G1": "refusal", "G2": "refusal",
}
for _t in TASKS:
    _t["shape"] = _SHAPES[_t["id"]]
    # Output-column contract for map tasks (lets a real agent alias correctly).
    if _t["shape"] == "map_row":
        _t["output_columns"] = list(_t["golden"].keys())

TASK_BY_ID = {t["id"]: t for t in TASKS}
