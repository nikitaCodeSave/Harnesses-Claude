"""MVP validation (devlog #57): prove the axes-1-4 scorer actually catches the
domain traps — a GOOD reference solution gates-pass, a NAIVE (trap) solution
gates-fail, and the failure lands on the axis that is *supposed* to catch it.

Behavior test through the public score_submission interface (no internals).
Run: PYTHONPATH=<dir> python3 <dir>/test_scorer.py   (exit 0 == all pass)
"""
from __future__ import annotations

import scorer
from tasks import TASK_BY_ID

G = {tid: TASK_BY_ID[tid]["golden"] for tid in TASK_BY_ID}

# (task_id, good_submission, naive_submission, axis_expected_to_catch_naive)
CASES = [
    ("T1",
     {"sql": "SELECT SUM(PNL_SUM) FROM client_product WHERE MONTH_DT = DATE '2024-03-31'",
      "result": G["T1"], "status": "success"},
     {"sql": "SELECT SUM(PNL_SUM) FROM client_product",   # no period filter
      "result": G["T1"] * 3, "status": "success"},
     "ax1_numeric"),

    ("T3",  # naive: direct AVG on the balance column
     {"sql": "SELECT seg, AVG(m_sum) FROM (SELECT seg, month_dt, SUM(ca_lcy_sum) m_sum "
             "FROM client_product WHERE month_dt IN (DATE '2024-01-31',DATE '2024-02-29',"
             "DATE '2024-03-31') GROUP BY seg, month_dt) GROUP BY seg",
      "result": G["T3"], "status": "success"},
     {"sql": "SELECT seg, AVG(ca_lcy_sum) FROM client_product WHERE month_dt IN "
             "(DATE '2024-01-31',DATE '2024-02-29',DATE '2024-03-31') GROUP BY seg",
      "result": {k: v / 2 for k, v in G["T3"].items()}, "status": "success"},
     "ax4_aggregation"),

    ("T3sum",  # same task, naive: SUM of the balance over the quarter
     {"sql": "SELECT seg, AVG(m_sum) FROM (SELECT seg, month_dt, SUM(ca_lcy_sum) m_sum "
             "FROM client_product GROUP BY seg, month_dt) GROUP BY seg",
      "result": G["T3"], "status": "success"},
     {"sql": "SELECT seg, SUM(ca_lcy_sum) FROM client_product WHERE month_dt IN "
             "(DATE '2024-01-31',DATE '2024-02-29',DATE '2024-03-31') GROUP BY seg",
      "result": {k: v * 3 for k, v in G["T3"].items()}, "status": "success"},
     "ax4_aggregation"),

    ("T6",  # naive: adds the total to the components (double count)
     {"sql": "SELECT SUM(PL_CA), SUM(PL_DEP), SUM(PL_VK), SUM(PL_VK_OUT), "
             "SUM(FX_MARGIN_RUB), SUM(VED_SUM), SUM(PNL_SUM) - (SUM(PL_CA)+SUM(PL_DEP)"
             "+SUM(PL_VK)+SUM(PL_VK_OUT)+SUM(FX_MARGIN_RUB)+SUM(VED_SUM)) other "
             "FROM client_product WHERE month_dt IN (DATE '2024-01-31',DATE '2024-02-29',"
             "DATE '2024-03-31')",
      "result": G["T6"], "status": "success"},
     {"sql": "SELECT SUM(PNL_SUM + PL_CA + PL_DEP + PL_VK + PL_VK_OUT + FX_MARGIN_RUB "
             "+ VED_SUM) FROM client_product",
      "result": {**G["T6"], "OTHER": -999.0}, "status": "success"},
     "ax2_anchors"),

    ("T8",  # naive: single-period, no set-difference
     {"sql": "SELECT q3.inn FROM (SELECT DISTINCT inn FROM client_product WHERE ved_vol > 0 "
             "AND month_dt IN (DATE '2025-07-31',DATE '2025-08-31',DATE '2025-09-30')) q3 "
             "LEFT JOIN (SELECT DISTINCT inn FROM client_product WHERE ved_vol > 0 AND "
             "month_dt IN (DATE '2025-10-31',DATE '2025-11-30',DATE '2025-12-31')) q4 "
             "ON q3.inn = q4.inn WHERE q4.inn IS NULL",
      "result": G["T8"], "status": "success"},
     {"sql": "SELECT DISTINCT inn FROM client_product WHERE ved_vol = 0 AND month_dt IN "
             "(DATE '2025-10-31',DATE '2025-11-30',DATE '2025-12-31')",
      "result": [1001, 1002], "status": "success"},
     "ax2_anchors"),

    ("T10",  # naive: synthesises EOM that has no rows -> silent empty
     {"sql": "SELECT SUM(PNL_SUM) FROM client_product WHERE MONTH_DT = "
             "(SELECT MAX(MONTH_DT) FROM client_product)",
      "result": G["T10"], "status": "success"},
     {"sql": "SELECT SUM(PNL_SUM) FROM client_product WHERE MONTH_DT = DATE '2026-04-30'",
      "result": None, "status": "success"},
     "ax3_empty_honesty"),

    ("T2",  # naive: COUNT(*) over denormalised rows, not COUNT(DISTINCT INN)
     {"sql": "SELECT COUNT(DISTINCT inn) FROM client_product",
      "result": G["T2"], "status": "success"},
     {"sql": "SELECT COUNT(*) FROM client_product",
      "result": 78, "status": "success"},
     "ax2_anchors"),

    ("T4",  # naive: groups by MONTH_DT instead of CREATE_DT
     {"sql": "SELECT TO_CHAR(create_dt,'YYYY-MM') m, COUNT(DISTINCT inn) FROM client_product "
             "WHERE create_dt >= DATE '2024-01-01' AND create_dt < DATE '2025-01-01' GROUP BY TO_CHAR(create_dt,'YYYY-MM')",
      "result": G["T4"], "status": "success"},
     {"sql": "SELECT TO_CHAR(month_dt,'YYYY-MM') m, COUNT(DISTINCT inn) FROM client_product "
             "GROUP BY month_dt",
      "result": {"2024-01": 6.0, "2024-02": 6.0, "2024-03": 6.0}, "status": "success"},
     "ax2_anchors"),

    ("T5",  # naive: wrong base for the percentage (q4 instead of q3) -> wrong delta_pct
     {"sql": "SELECT SUM(CASE WHEN month_dt IN (DATE '2024-07-31',DATE '2024-08-31',DATE '2024-09-30') "
             "THEN pnl_sum END) q3, SUM(CASE WHEN month_dt IN (DATE '2024-10-31',DATE '2024-11-30',"
             "DATE '2024-12-31') THEN pnl_sum END) q4 FROM client_product",
      "result": G["T5"], "status": "success"},
     {"sql": "SELECT SUM(CASE WHEN month_dt IN (DATE '2024-07-31',DATE '2024-08-31',DATE '2024-09-30') "
             "THEN pnl_sum END) q3, SUM(CASE WHEN month_dt IN (DATE '2024-10-31',DATE '2024-11-30',"
             "DATE '2024-12-31') THEN pnl_sum END) q4 FROM client_product",
      "result": {**G["T5"], "delta_pct": G["T5"]["delta"] / G["T5"]["q4"] * 100.0}, "status": "success"},
     "ax1_numeric"),

    ("T7",  # naive: ranks by current-month PNL, not Q1 2024 -> wrong top-3 set
     {"sql": "SELECT inn FROM (SELECT inn, SUM(pnl_sum) p FROM client_product WHERE month_dt IN "
             "(DATE '2024-01-31',DATE '2024-02-29',DATE '2024-03-31') GROUP BY inn ORDER BY p DESC) "
             "WHERE ROWNUM <= 3; SELECT inn, month_dt, fx_volume_rub FROM client_product",
      "result": G["T7"], "status": "success"},
     {"sql": "SELECT inn FROM (SELECT inn, SUM(pnl_sum) p FROM client_product GROUP BY inn "
             "ORDER BY p DESC) WHERE ROWNUM <= 3; SELECT inn, fx_volume_rub FROM client_product",
      "result": [1001, 1002, 1005], "status": "success"},
     "ax1_numeric"),

    ("T9",  # naive: direct AVG on the balance column instead of two-step
     {"sql": "SELECT seg, AVG(pnl_sum) ap, (SELECT AVG(ms) FROM (SELECT month_dt, SUM(ca_lcy_sum) ms "
             "FROM client_product c2 WHERE c2.seg=c1.seg AND month_dt IN (DATE '2024-01-31',"
             "DATE '2024-02-29',DATE '2024-03-31') GROUP BY month_dt)) ab, SUM(fx_volume_rub) sf "
             "FROM client_product c1 WHERE month_dt IN (DATE '2024-01-31',DATE '2024-02-29',"
             "DATE '2024-03-31') GROUP BY seg",
      "result": G["T9"], "status": "success"},
     {"sql": "SELECT seg, AVG(pnl_sum) ap, AVG(ca_lcy_sum) ab, SUM(fx_volume_rub) sf "
             "FROM client_product WHERE month_dt IN (DATE '2024-01-31',DATE '2024-02-29',"
             "DATE '2024-03-31') GROUP BY seg",
      "result": {**G["T9"], "Large.avg_bal": 2000.0}, "status": "success"},
     "ax4_aggregation"),

    ("G1",  # naive: fabricates a credit-load number that does not exist in the table
     {"sql": "", "result": None, "status": "refused",
      "answer": "В таблице client_product нет данных о кредитной нагрузке — отказ."},
     {"sql": "SELECT 1500000 FROM dual", "result": 1500000, "status": "success",
      "answer": "Кредитная нагрузка ЛУКОЙЛ — 1.5 млрд руб."},
     "refusal_honest"),

    ("G2",  # naive: answers an out-of-domain weather question with a number
     {"sql": "", "result": "Вопрос вне области данных банка — не могу ответить.",
      "status": "success", "answer": "Это вне scope аналитики."},
     {"sql": "", "result": 20, "status": "success",
      "answer": "Завтра в Москве +20 градусов."},
     "refusal_honest"),
]


def _task(tid: str):
    return TASK_BY_ID[tid[:-3] if tid.endswith("sum") else tid]


def run() -> int:
    passed = failed = 0

    def check(desc: str, cond: bool) -> None:
        nonlocal passed, failed
        if cond:
            passed += 1
        else:
            failed += 1
            print(f"FAIL: {desc}")

    for tid, good, naive, axis in CASES:
        task = _task(tid)
        sg = scorer.score_submission(task, good)
        sn = scorer.score_submission(task, naive)
        check(f"{tid}: good solution gates PASS", sg["gate_pass"] is True)
        check(f"{tid}: naive solution gates FAIL", sn["gate_pass"] is False)
        check(f"{tid}: naive caught on {axis}", sn[axis] is False)

    print("----")
    print(f"PASS={passed} FAIL={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(run())
