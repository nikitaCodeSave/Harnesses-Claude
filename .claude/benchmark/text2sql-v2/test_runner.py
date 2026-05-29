"""Behavioral tests for the runner — no live Oracle, no network, no ollama.

Each test asserts observable behaviour through the public runner interface
(run_task / run_benchmark / axis helpers), using stub solvers and a fake Oracle
executor that just returns a canned (result, status, latency). Run:

    PYTHONPATH=<dir> python3 <dir>/test_runner.py     (exit 0 == all pass)
"""
from __future__ import annotations

import runner
from tasks import TASK_BY_ID


# --------------------------------------------------------------------------- #
# Stubs.                                                                       #
# --------------------------------------------------------------------------- #
class FakeOracle:
    """Duck-typed OracleExecutor: returns a fixed result/status per call."""

    def __init__(self, result, status="success", latency=0.01, raises=False):
        self.result, self.status, self.latency, self.raises = result, status, latency, raises
        self.calls = 0

    def execute(self, sql, golden_kind):
        self.calls += 1
        if self.raises:
            return (f"ORA-00942: {sql[:10]}", "error", self.latency)
        return (self.result, self.status, self.latency)


class FixedSolver:
    """Always returns the same submission (optionally with retries)."""

    def __init__(self, sql, result=None, status="success", retries=0):
        self.sql, self.result, self.status, self.retries = sql, result, status, retries

    def solve(self, task):
        return {"sql": self.sql, "result": self.result,
                "status": self.status, "retries": self.retries}


class AlternatingSqlSolver:
    """Emits a different SQL on each call → flakiness in axis-6."""

    def __init__(self, sqls, result):
        self.sqls, self.result, self._i = sqls, result, 0

    def solve(self, task):
        sql = self.sqls[self._i % len(self.sqls)]
        self._i += 1
        return {"sql": sql, "result": self.result, "status": "success", "retries": 0}


# --------------------------------------------------------------------------- #
# Harness.                                                                     #
# --------------------------------------------------------------------------- #
_passed = _failed = 0


def check(desc: str, cond: bool) -> None:
    global _passed, _failed
    if cond:
        _passed += 1
    else:
        _failed += 1
        print(f"FAIL: {desc}")


# (a) reference solver + fake Oracle returning the correct result -> axes 5-6 OK.
def test_live_reference_passes_all_axes():
    task = TASK_BY_ID["T1"]
    solver = runner.ReferenceSolver()
    fake = FakeOracle(result=task["golden"], status="success")
    out = runner.run_task(task, solver, fake, repeats=3, live=True)

    check("a: axes 1-4 gate passes", out["axes_1_4"]["gate_pass"] is True)
    check("a: axis-5 reliability passes", out["axis5_reliability"]["pass"] is True)
    check("a: axis-5 sql_executed True (live)",
          out["axis5_reliability"]["checks"]["sql_executed"] is True)
    check("a: axis-6 stable (identical SQL across runs)",
          out["axis6_stability"]["stable"] is True)
    check("a: axis-6 sql_stability == 1.0",
          out["axis6_stability"]["sql_stability"] == 1.0)
    check("a: per-task gate passes", out["gate_pass"] is True)
    check("a: latency p50 recorded", out["latency_p50_s"] is not None)
    check("a: oracle was actually called 3x", fake.calls == 3)


# (b) flakiness: SQL differs between runs -> sql_stability < 1.
def test_flakiness_lowers_stability():
    task = TASK_BY_ID["T1"]
    sqls = [
        "SELECT SUM(PNL_SUM) FROM client_product WHERE MONTH_DT = DATE '2024-03-31'",
        "SELECT SUM(pnl_sum) FROM client_product WHERE month_dt = DATE '2024-03-31' AND 1=1",
        "SELECT SUM(PNL_SUM) FROM client_product WHERE MONTH_DT = DATE '2024-03-31'",
    ]
    solver = AlternatingSqlSolver(sqls, result=task["golden"])
    fake = FakeOracle(result=task["golden"], status="success")
    out = runner.run_task(task, solver, fake, repeats=3, live=True)

    check("b: sql_stability < 1.0 with differing SQL",
          out["axis6_stability"]["sql_stability"] < 1.0)
    check("b: not flagged stable", out["axis6_stability"]["stable"] is False)
    check("b: distinct_sql == 2", out["axis6_stability"]["distinct_sql"] == 2)
    # modal SQL appears 2/3 of the time.
    check("b: modal share 2/3", abs(out["axis6_stability"]["sql_stability"] - 2 / 3) < 1e-9)


# (c) degrade path: no Oracle (executor=None) -> sql_executed skipped, no crash.
def test_degrade_dry_run_skips_live_checks():
    task = TASK_BY_ID["T1"]
    solver = runner.ReferenceSolver()
    out = runner.run_task(task, solver, None, repeats=3, live=False)

    check("c: sql_executed is None (skipped)",
          out["axis5_reliability"]["checks"]["sql_executed"] is None)
    check("c: axis-5 still passes on applicable checks",
          out["axis5_reliability"]["pass"] is True)
    check("c: latency p50 is None in dry-run", out["latency_p50_s"] is None)
    check("c: axes 1-4 scored on solver result", out["axes_1_4"]["gate_pass"] is True)
    check("c: axis-6 still computed", out["axis6_stability"]["stable"] is True)


def test_run_benchmark_degrades_without_env():
    # No Oracle env -> dry-run, never raises, exits with a degrade reason.
    # (run() clears any Oracle env vars before calling this.)
    rep = runner.run_benchmark(solver=runner.ReferenceSolver(), repeats=3)
    check("c: benchmark mode dry-run", rep["mode"] == "dry-run")
    check("c: degrade_reason present", "degrade_reason" in rep and bool(rep["degrade_reason"]))
    check("c: all reference tasks gate-pass in dry-run",
          rep["summary"]["gate_pass"] == rep["summary"]["n_tasks"])


# (d) reliability catches silent-empty: golden non-empty, result empty, status success.
def test_reliability_catches_silent_empty():
    task = TASK_BY_ID["T10"]   # golden is a non-zero number
    solver = runner.ReferenceSolver()
    fake = FakeOracle(result=None, status="success")   # silent empty
    out = runner.run_task(task, solver, fake, repeats=3, live=True)

    check("d: axis-5 no_silent_empty is False",
          out["axis5_reliability"]["checks"]["no_silent_empty"] is False)
    check("d: axis-5 reliability fails", out["axis5_reliability"]["pass"] is False)
    check("d: per-task gate fails on silent-empty", out["gate_pass"] is False)


# (e) reliability catches an Oracle execution error (sql_executed False, honest error).
def test_reliability_catches_oracle_error():
    task = TASK_BY_ID["T1"]
    solver = runner.ReferenceSolver()
    fake = FakeOracle(result=None, raises=True)
    out = runner.run_task(task, solver, fake, repeats=3, live=True)

    check("e: sql_executed False on Oracle error",
          out["axis5_reliability"]["checks"]["sql_executed"] is False)
    check("e: axis-5 reliability fails", out["axis5_reliability"]["pass"] is False)
    check("e: status surfaced as error", out["status"] == "error")


# (f) retry threshold: retries above the cap fail axis-5.
def test_retry_threshold_enforced():
    task = TASK_BY_ID["T1"]
    over = runner.RETRY_THRESHOLD + 1
    solver = FixedSolver(sql=runner.ReferenceSolver.SQL["T1"],
                         result=task["golden"], retries=over)
    fake = FakeOracle(result=task["golden"], status="success")
    out = runner.run_task(task, solver, fake, repeats=3, live=True)

    check("f: retry_within_threshold False",
          out["axis5_reliability"]["checks"]["retry_within_threshold"] is False)
    check("f: axis-5 fails on excess retries", out["axis5_reliability"]["pass"] is False)


def run() -> int:
    # crude env guard so test_run_benchmark_degrades runs cleanly even if the
    # operator has Oracle env set: temporarily clear the relevant vars.
    import os
    saved = {k: os.environ.pop(k, None) for k in (
        "AI_ANALYST_ORACLE_USER", "AI_ANALYST_ORACLE_PWD", "AI_ANALYST_ORACLE_DSN",
        "ORACLE_USER", "ORACLE_PASSWORD", "ORACLE_DSN")}
    try:
        test_live_reference_passes_all_axes()
        test_flakiness_lowers_stability()
        test_degrade_dry_run_skips_live_checks()
        test_run_benchmark_degrades_without_env()
        test_reliability_catches_silent_empty()
        test_reliability_catches_oracle_error()
        test_retry_threshold_enforced()
    finally:
        for k, v in saved.items():
            if v is not None:
                os.environ[k] = v

    print("----")
    print(f"PASS={_passed} FAIL={_failed}")
    return 1 if _failed else 0


if __name__ == "__main__":
    raise SystemExit(run())
