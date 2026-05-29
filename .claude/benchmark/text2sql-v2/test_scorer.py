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
