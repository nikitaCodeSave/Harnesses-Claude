"""Live-Oracle runner for benchmark v2: orchestrates a full benchmark pass and
adds axes 5-6 on top of the deterministic axes-1-4 scorer.

Pipeline per task
------------------
  solver.solve(task)                       -> submission {"sql","result","status"}
  [optional] OracleExecutor.execute(sql)   -> (result, status, latency)   # live Oracle
  scorer.score_submission(task, submission) -> axes 1-4 + gate_pass
  axes 5-6 computed across N>=3 repeats of the above.

Axis 5  reliability / artifact-integrity (per task, per run):
  - the pipeline produced a submission without raising;
  - the SQL executed (live mode) or is non-empty (dry-run);
  - retry count <= RETRY_THRESHOLD (solver-reported);
  - no silent-empty: result is non-empty when golden is non-empty.
Axis 6  stability / flakiness (per task, across N runs):
  - share of runs whose normalised SQL equals the modal SQL  (sql_stability);
  - share of runs whose scorer gate_pass equals the modal verdict (result_stability).
  Stable == both shares == 1.0.

Degrade
-------
If `oracledb` is missing OR the Oracle env config is absent, the runner falls
back to DRY-RUN: it trusts the solver's own `result`/`status` (the reference
solver carries the correct golden), scores axes 1-4 on that, computes axis 6
(SQL stability is solver-only and still meaningful), and marks axis-5 live
sub-checks (sql_executed) as skipped rather than failing. It NEVER raises for a
missing stack — it prints what the operator must provide and exits cleanly.

Solver extension point
----------------------
`Solver` is the pluggable contract: `solve(task) -> submission`. The bundled
`ReferenceSolver` hardcodes the correct SQL + golden result per task so the
runner can be exercised end-to-end (and validated against a live Oracle when
present). To benchmark a *real* agent-under-test, implement `Solver.solve` as a
thin wrapper, e.g. shell out to `claude --print` with the task NL and parse the
emitted SQL, or call the target project's NL->SQL pipeline; return the same
submission dict. See `AgentSolver` (commented skeleton) at the bottom.
"""
from __future__ import annotations

import json
import os
import re
import statistics
import time
from collections import Counter
from dataclasses import dataclass, field
from typing import Any, Callable, Optional, Protocol

import scorer
from tasks import TASKS

RETRY_THRESHOLD = 3          # axis-5: max acceptable solver self-repair retries
DEFAULT_REPEATS = 3          # axis-6: N>=3 runs per task for flakiness


# --------------------------------------------------------------------------- #
# Submission helpers (mirror scorer's notion of "empty" for axis-5).          #
# --------------------------------------------------------------------------- #
def _result_is_empty(result: Any, status: str) -> bool:
    if result is None:
        return True
    if isinstance(result, (str, list, dict, tuple, set)) and len(result) == 0:
        return True
    if isinstance(result, str) and "не найден" in result.lower():
        return True
    if status in ("no_data", "error"):
        return True
    return False


def _golden_is_empty(task: dict) -> bool:
    g = task["golden"]
    if g is None:
        return True
    if isinstance(g, (list, dict, tuple, set)) and len(g) == 0:
        return True
    return False


def _normalise_sql(sql: str) -> str:
    """Whitespace/case-insensitive canonical form for SQL stability comparison."""
    return re.sub(r"\s+", " ", (sql or "").strip().lower())


# --------------------------------------------------------------------------- #
# Solver contract (extension point).                                          #
# --------------------------------------------------------------------------- #
class Solver(Protocol):
    def solve(self, task: dict) -> dict:
        """Return a submission {"sql": str, "result": <value>, "status": str}.

        May also carry an integer "retries" key (self-repair attempts) which the
        runner reads for axis-5; absent == 0.
        """
        ...


class ReferenceSolver:
    """Hardcoded CORRECT SQL + golden result per task.

    Lets the runner be driven end-to-end (and verified against a live Oracle).
    The result equals `task["golden"]` by construction, so in dry-run the scorer
    sees a gate-passing submission; in live mode the Oracle-produced result
    replaces it and is checked against the same golden.
    """

    # SQL mirrors the GOOD solutions proven in test_scorer.py.
    SQL: dict[str, str] = {
        "T1": "SELECT SUM(PNL_SUM) FROM client_product "
              "WHERE MONTH_DT = DATE '2024-03-31'",
        "T3": "SELECT seg, AVG(m_sum) FROM (SELECT seg, month_dt, SUM(ca_lcy_sum) m_sum "
              "FROM client_product WHERE month_dt IN (DATE '2024-01-31',DATE '2024-02-29',"
              "DATE '2024-03-31') GROUP BY seg, month_dt) GROUP BY seg",
        "T6": "SELECT SUM(PL_CA), SUM(PL_DEP), SUM(PL_VK), SUM(PL_VK_OUT), "
              "SUM(FX_MARGIN_RUB), SUM(VED_SUM), SUM(PNL_SUM) - (SUM(PL_CA)+SUM(PL_DEP)"
              "+SUM(PL_VK)+SUM(PL_VK_OUT)+SUM(FX_MARGIN_RUB)+SUM(VED_SUM)) other, "
              "SUM(PNL_SUM) pnl_total FROM client_product WHERE month_dt IN "
              "(DATE '2024-01-31',DATE '2024-02-29',DATE '2024-03-31')",
        "T8": "SELECT q3.inn FROM (SELECT DISTINCT inn FROM client_product WHERE ved_vol > 0 "
              "AND month_dt IN (DATE '2025-07-31',DATE '2025-08-31',DATE '2025-09-30')) q3 "
              "LEFT JOIN (SELECT DISTINCT inn FROM client_product WHERE ved_vol > 0 AND "
              "month_dt IN (DATE '2025-10-31',DATE '2025-11-30',DATE '2025-12-31')) q4 "
              "ON q3.inn = q4.inn WHERE q4.inn IS NULL",
        "T10": "SELECT SUM(PNL_SUM) FROM client_product WHERE MONTH_DT = "
               "(SELECT MAX(MONTH_DT) FROM client_product)",
    }

    def solve(self, task: dict) -> dict:
        tid = task["id"]
        return {
            "sql": self.SQL[tid],
            "result": task["golden"],     # correct by construction
            "status": "success",
            "retries": 0,
        }


# --------------------------------------------------------------------------- #
# Oracle executor (optional, env-only config, lazy import).                   #
# --------------------------------------------------------------------------- #
@dataclass
class OracleConfig:
    user: str
    password: str
    dsn: str

    @classmethod
    def from_env(cls) -> Optional["OracleConfig"]:
        """Read creds ONLY from env. Never reads .env files / hardcodes.

        Accepts the project's AI_ANALYST_ORACLE_* names or the standard
        ORACLE_USER/ORACLE_PASSWORD/ORACLE_DSN.
        """
        user = os.getenv("AI_ANALYST_ORACLE_USER") or os.getenv("ORACLE_USER")
        pwd = os.getenv("AI_ANALYST_ORACLE_PWD") or os.getenv("ORACLE_PASSWORD")
        dsn = os.getenv("AI_ANALYST_ORACLE_DSN") or os.getenv("ORACLE_DSN")
        if user and pwd and dsn:
            return cls(user=user, password=pwd, dsn=dsn)
        return None


class OracleExecutor:
    """Executes solver SQL against a live Oracle via python-oracledb (thin mode).

    `execute(sql)` returns (result, status, latency_s). `result` is shaped to
    match the task's golden_kind so the scorer can compare directly:
      number     -> scalar (single row, single col)
      number_map -> {col_name: value} from the single row, or {} if no rows
      id_set     -> list of ids from the first column
    """

    def __init__(self, cfg: OracleConfig):
        self.cfg = cfg
        self._conn = None

    def __enter__(self) -> "OracleExecutor":
        import oracledb  # lazy: not a hard dependency
        self._conn = oracledb.connect(
            user=self.cfg.user, password=self.cfg.password, dsn=self.cfg.dsn
        )
        return self

    def __exit__(self, *exc) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def execute(self, sql: str, golden_kind: str) -> tuple[Any, str, float]:
        t0 = time.perf_counter()
        try:
            cur = self._conn.cursor()
            cur.execute(sql)
            rows = cur.fetchall()
            cols = [d[0].lower() for d in (cur.description or [])]
            cur.close()
        except Exception as exc:  # noqa: BLE001 — surface as honest error status
            return (f"{type(exc).__name__}: {exc}", "error", time.perf_counter() - t0)
        latency = time.perf_counter() - t0
        return (self._shape(rows, cols, golden_kind), "success", latency)

    @staticmethod
    def _shape(rows: list, cols: list[str], golden_kind: str) -> Any:
        if golden_kind == "number":
            if not rows or rows[0][0] is None:
                return None
            return rows[0][0]
        if golden_kind == "number_map":
            # Two layouts: (a) single row, one col per component (wide);
            # (b) many rows of (key, value) pairs (long, e.g. T3 by segment).
            if not rows:
                return {}
            if len(cols) == 2 and len(rows) >= 1 and not _looks_wide(rows, cols):
                return {str(r[0]): r[1] for r in rows}
            return {cols[i]: rows[0][i] for i in range(len(cols))}
        if golden_kind == "id_set":
            return [r[0] for r in rows]
        return rows


def _looks_wide(rows: list, cols: list[str]) -> bool:
    # Heuristic: a 2-col single-row numeric result is "wide" (e.g. SUM,SUM),
    # whereas multi-row 2-col is the long (key,value) layout.
    return len(rows) == 1 and all(isinstance(v, (int, float)) for v in rows[0])


# --------------------------------------------------------------------------- #
# Axis 5 / 6 computation.                                                     #
# --------------------------------------------------------------------------- #
@dataclass
class RunRecord:
    sql: str
    result: Any
    status: str
    retries: int
    sql_executed: Optional[bool]   # None == skipped (dry-run)
    latency_s: Optional[float]
    score: dict                    # scorer.score_submission output


def _axis5(task: dict, run: RunRecord) -> dict:
    """Reliability / artifact-integrity for a single run."""
    no_exception = True   # reaching here means solve()+score() did not raise
    sql_present = bool((run.sql or "").strip())
    retry_ok = run.retries <= RETRY_THRESHOLD
    # silent-empty: golden non-empty but result empty under a success status.
    silent_empty = (
        not _golden_is_empty(task)
        and _result_is_empty(run.result, run.status)
        and run.status != "error"
    )
    checks = {
        "no_exception": no_exception,
        "sql_present": sql_present,
        "sql_executed": run.sql_executed,        # None if dry-run (skipped)
        "retry_within_threshold": retry_ok,
        "no_silent_empty": not silent_empty,
    }
    applicable = [v for v in checks.values() if v is not None]
    return {"checks": checks, "pass": all(applicable)}


def _axis6(records: list[RunRecord]) -> dict:
    """Stability / flakiness across N runs of one task."""
    n = len(records)
    sqls = [_normalise_sql(r.sql) for r in records]
    verdicts = [r.score["gate_pass"] for r in records]

    modal_sql, modal_sql_n = Counter(sqls).most_common(1)[0]
    modal_verdict, modal_verdict_n = Counter(verdicts).most_common(1)[0]

    sql_stability = modal_sql_n / n
    result_stability = modal_verdict_n / n
    return {
        "runs": n,
        "sql_stability": sql_stability,
        "result_stability": result_stability,
        "stable": sql_stability == 1.0 and result_stability == 1.0,
        "distinct_sql": len(set(sqls)),
    }


# --------------------------------------------------------------------------- #
# Single run + multi-run orchestration.                                       #
# --------------------------------------------------------------------------- #
def _one_run(task: dict, solver: Solver, executor: Optional[OracleExecutor]) -> RunRecord:
    sub = solver.solve(task)
    sql = sub.get("sql", "")
    retries = int(sub.get("retries", 0) or 0)

    if executor is not None:
        result, status, latency = executor.execute(sql, task["golden_kind"])
        sql_executed = status != "error"
    else:
        # dry-run: trust the solver's own result/status; live execution skipped.
        result, status, latency = sub.get("result"), sub.get("status", "success"), None
        sql_executed = None

    submission = {"sql": sql, "result": result, "status": status}
    score = scorer.score_submission(task, submission)
    rec = RunRecord(
        sql=sql, result=result, status=status, retries=retries,
        sql_executed=sql_executed, latency_s=latency, score=score,
    )
    return rec


def run_task(task: dict, solver: Solver, executor: Optional[OracleExecutor],
             repeats: int = DEFAULT_REPEATS, live: bool = False) -> dict:
    records = [_one_run(task, solver, executor) for _ in range(repeats)]
    primary = records[0]

    ax5 = _axis5(task, primary)
    ax6 = _axis6(records)

    latencies = [r.latency_s for r in records if r.latency_s is not None]
    p50 = statistics.median(latencies) if latencies else None

    return {
        "id": task["id"],
        "level": task["level"],
        "axes_1_4": primary.score,                  # from scorer
        "axis5_reliability": ax5 if live else _skip_axis5_live(ax5),
        "axis6_stability": ax6,
        "latency_p50_s": p50,
        "retries": primary.retries,
        "sql": primary.sql,
        "status": primary.status,
        # per-task gate combines scorer's axes-1-4 gate with axis-5 reliability.
        "gate_pass": bool(primary.score["gate_pass"] and ax5["pass"]),
    }


def _skip_axis5_live(ax5: dict) -> dict:
    """In dry-run, sql_executed is already None (skipped); pass over applicable."""
    return ax5


def run_benchmark(solver: Optional[Solver] = None, repeats: int = DEFAULT_REPEATS) -> dict:
    solver = solver or ReferenceSolver()
    cfg = OracleConfig.from_env()
    oracle_available = cfg is not None and _oracledb_importable()
    live = oracle_available

    report: dict[str, Any] = {
        "mode": "live" if live else "dry-run",
        "repeats": repeats,
        "tasks": [],
    }

    if not live:
        report["degrade_reason"] = _degrade_reason(cfg)

    if live:
        with OracleExecutor(cfg) as ex:
            for task in TASKS:
                report["tasks"].append(run_task(task, solver, ex, repeats, live=True))
    else:
        for task in TASKS:
            report["tasks"].append(run_task(task, solver, None, repeats, live=False))

    report["summary"] = {
        "n_tasks": len(report["tasks"]),
        "gate_pass": sum(1 for t in report["tasks"] if t["gate_pass"]),
        "stable": sum(1 for t in report["tasks"] if t["axis6_stability"]["stable"]),
    }
    return report


def _oracledb_importable() -> bool:
    try:
        import oracledb  # noqa: F401
        return True
    except ImportError:
        return False


def _degrade_reason(cfg: Optional[OracleConfig]) -> str:
    if cfg is None:
        return ("No Oracle env config. Set AI_ANALYST_ORACLE_USER / "
                "AI_ANALYST_ORACLE_PWD / AI_ANALYST_ORACLE_DSN (or ORACLE_USER / "
                "ORACLE_PASSWORD / ORACLE_DSN) to enable live execution.")
    return "python-oracledb not installed (pip install oracledb) — live execution skipped."


# --------------------------------------------------------------------------- #
# Real agent-under-test skeleton (extension point — not wired by default).    #
# --------------------------------------------------------------------------- #
@dataclass
class AgentSolver:
    """Skeleton for benchmarking a real NL->SQL agent.

    Provide a callable that maps the task NL to a generated SQL string. Example
    using the Claude Code CLI (illustrative — uncomment/adapt to wire it):

        def claude_sql(nl: str) -> str:
            import subprocess
            out = subprocess.run(
                ["claude", "--print",
                 f"Output ONLY an Oracle SQL query for: {nl}"],
                capture_output=True, text=True, timeout=120,
            ).stdout
            return _extract_sql(out)

        solver = AgentSolver(gen_sql=claude_sql)

    The runner then executes that SQL on the live Oracle, so `result`/`status`
    come from the database, not the agent — exactly what we want to grade.
    """
    gen_sql: Callable[[str], str]
    max_retries: int = 0
    _retry: int = field(default=0, init=False)

    def solve(self, task: dict) -> dict:
        sql = self.gen_sql(task["nl"])
        # result/status are filled by the live OracleExecutor; in dry-run the
        # agent has no ground truth, so it honestly reports unknown.
        return {"sql": sql, "result": None, "status": "success", "retries": self._retry}


if __name__ == "__main__":
    rep = run_benchmark()
    print(json.dumps(rep, indent=2, ensure_ascii=False, default=str))
    if rep["mode"] == "dry-run":
        print(f"\n[dry-run] {rep['degrade_reason']}")
        print("[dry-run] axes 1-4 scored on reference-solver result; "
              "axis-5 live sub-check (sql_executed) skipped; axis-6 computed.")
    # exit 0 always: a missing live stack is a degrade, not a failure.
