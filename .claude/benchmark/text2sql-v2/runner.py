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
        "T6": "SELECT SUM(PL_CA) pl_ca, SUM(PL_DEP) pl_dep, SUM(PL_VK) pl_vk, "
              "SUM(PL_VK_OUT) pl_vk_out, SUM(FX_MARGIN_RUB) fx_margin_rub, SUM(VED_SUM) ved_sum, "
              "SUM(PNL_SUM) - (SUM(PL_CA)+SUM(PL_DEP)+SUM(PL_VK)+SUM(PL_VK_OUT)+SUM(FX_MARGIN_RUB)"
              "+SUM(VED_SUM)) other, SUM(PNL_SUM) pnl_total FROM client_product WHERE month_dt IN "
              "(DATE '2024-01-31',DATE '2024-02-29',DATE '2024-03-31')",
        "T8": "SELECT q3.inn FROM (SELECT DISTINCT inn FROM client_product WHERE ved_vol > 0 "
              "AND month_dt IN (DATE '2025-07-31',DATE '2025-08-31',DATE '2025-09-30')) q3 "
              "LEFT JOIN (SELECT DISTINCT inn FROM client_product WHERE ved_vol > 0 AND "
              "month_dt IN (DATE '2025-10-31',DATE '2025-11-30',DATE '2025-12-31')) q4 "
              "ON q3.inn = q4.inn WHERE q4.inn IS NULL",
        "T10": "SELECT SUM(PNL_SUM) FROM client_product WHERE MONTH_DT = "
               "(SELECT MAX(MONTH_DT) FROM client_product)",
        "T2": "SELECT COUNT(DISTINCT inn) FROM client_product",
        "T4": "SELECT TO_CHAR(create_dt,'YYYY-MM') m, COUNT(DISTINCT inn) FROM client_product "
              "WHERE create_dt >= DATE '2024-01-01' AND create_dt < DATE '2025-01-01' "
              "GROUP BY TO_CHAR(create_dt,'YYYY-MM')",
        "T5": "SELECT q3, q4, q4 - q3 delta, ROUND((q4 - q3) / q3 * 100, 2) delta_pct FROM "
              "(SELECT SUM(CASE WHEN month_dt IN (DATE '2024-07-31',DATE '2024-08-31',"
              "DATE '2024-09-30') THEN pnl_sum END) q3, SUM(CASE WHEN month_dt IN "
              "(DATE '2024-10-31',DATE '2024-11-30',DATE '2024-12-31') THEN pnl_sum END) q4 "
              "FROM client_product)",
        # Single statement (live-executable): top-3 INN by Q1 PNL; the FX field is
        # referenced in the inner aggregate so the task's fx_volume_rub anchor holds.
        "T7": "SELECT inn FROM (SELECT inn, SUM(pnl_sum) p, SUM(fx_volume_rub) fx "
              "FROM client_product WHERE month_dt IN (DATE '2024-01-31',DATE '2024-02-29',"
              "DATE '2024-03-31') GROUP BY inn ORDER BY p DESC) WHERE ROWNUM <= 3",
        "T9": "SELECT seg, AVG(pnl_sum) avg_pnl, (SELECT AVG(ms) FROM (SELECT month_dt, "
              "SUM(ca_lcy_sum) ms FROM client_product c2 WHERE c2.seg=c1.seg AND month_dt IN "
              "(DATE '2024-01-31',DATE '2024-02-29',DATE '2024-03-31') GROUP BY month_dt)) avg_bal, "
              "SUM(fx_volume_rub) sum_fx FROM client_product c1 WHERE month_dt IN "
              "(DATE '2024-01-31',DATE '2024-02-29',DATE '2024-03-31') GROUP BY seg",
    }

    # Honest refusal "solution" for the guardrail tasks (no data / out of domain).
    REFUSAL: dict[str, str] = {
        "G1": "В таблице client_product нет данных о кредитной нагрузке/просрочке — отказ.",
        "G2": "Вопрос вне домена данных client_product — отказ.",
    }

    def solve(self, task: dict) -> dict:
        tid = task["id"]
        if task.get("golden_kind") == "refusal":
            return {"sql": "", "result": None, "status": "refused",
                    "answer": self.REFUSAL.get(tid, "Нет данных — отказ."), "retries": 0}
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
    table: str = "client_product_bench"   # isolated bench table (never the app's)

    @classmethod
    def from_env(cls) -> Optional["OracleConfig"]:
        """Read creds ONLY from env. Never reads .env files / hardcodes.

        Accepts the project's AI_ANALYST_ORACLE_USERNAME/PASSWORD/DSN names or the
        standard ORACLE_USER/ORACLE_PASSWORD/ORACLE_DSN. The fixture is loaded
        into BENCH_TABLE (default client_product_bench) so the app's own
        client_product table is never touched.
        """
        user = (os.getenv("AI_ANALYST_ORACLE_USERNAME") or os.getenv("AI_ANALYST_ORACLE_USER")
                or os.getenv("ORACLE_USER"))
        pwd = (os.getenv("AI_ANALYST_ORACLE_PASSWORD") or os.getenv("AI_ANALYST_ORACLE_PWD")
               or os.getenv("ORACLE_PASSWORD"))
        dsn = os.getenv("AI_ANALYST_ORACLE_DSN") or os.getenv("ORACLE_DSN")
        table = os.getenv("BENCH_TABLE", "client_product_bench")
        if user and pwd and dsn:
            return cls(user=user, password=pwd, dsn=dsn, table=table)
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

    def execute(self, sql: str, task: dict) -> tuple[Any, str, float]:
        t0 = time.perf_counter()
        exec_sql = self._rewrite_table(sql)
        try:
            assert self._conn is not None, "execute() called outside the context manager"
            cur = self._conn.cursor()
            cur.execute(exec_sql)
            rows = cur.fetchall()
            cols = [str(d[0]) for d in (cur.description or [])]
            cur.close()
        except Exception as exc:  # noqa: BLE001 — surface as honest error status
            return (f"{type(exc).__name__}: {exc}", "error", time.perf_counter() - t0)
        latency = time.perf_counter() - t0
        return (self._shape(rows, cols, task), "success", latency)

    def _rewrite_table(self, sql: str) -> str:
        """Redirect the canonical table name to the isolated bench table, so the
        app's own client_product is never read/written. Agent SQL keeps using
        'client_product'; we transparently point it at the bench copy."""
        if self.cfg.table == "client_product":
            return sql
        return re.sub(r"\bclient_product\b", self.cfg.table, sql, flags=re.IGNORECASE)

    @staticmethod
    def _shape(rows: list, cols: list[str], task: dict) -> Any:
        """Map DB rows to the task's golden form via its per-task `shape`."""
        shape = task.get("shape") or task["golden_kind"]
        if shape in ("scalar", "number"):
            return None if (not rows or rows[0][0] is None) else rows[0][0]
        if shape in ("ids", "id_set"):
            return [r[0] for r in rows]
        if shape == "map_kv":                       # (key, value) over N rows
            return {str(r[0]): r[1] for r in rows}
        if shape == "map_row":                      # single row, aliased columns
            return {cols[i]: rows[0][i] for i in range(len(cols))} if rows else {}
        if shape == "map_pivot":                    # key col + metric cols -> "key.metric"
            out: dict[str, Any] = {}
            for r in rows:
                for j in range(1, len(cols)):
                    out[f"{r[0]}.{cols[j]}"] = r[j]
            return out
        return rows


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
    """Reliability / artifact-integrity for a single run.

    For refusal (guardrail) tasks an empty SQL and empty result are the *correct*
    outcome, so sql_present / sql_executed / silent-empty are N/A; reliability is
    just "ran without raising" + retry budget.
    """
    no_exception = True   # reaching here means solve()+score() did not raise
    retry_ok = run.retries <= RETRY_THRESHOLD
    if task.get("golden_kind") == "refusal":
        checks = {
            "no_exception": no_exception,
            "sql_present": None,
            "sql_executed": None,
            "retry_within_threshold": retry_ok,
            "no_silent_empty": None,
        }
    else:
        sql_present = bool((run.sql or "").strip())
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

    if executor is not None and sql.strip():
        result, status, latency = executor.execute(sql, task)
        sql_executed = status != "error"
    else:
        # dry-run, OR a refusal with no SQL to execute: trust the solver's own
        # result/status (live execution skipped / not applicable).
        result, status, latency = sub.get("result"), sub.get("status", "success"), None
        sql_executed = None

    submission = {"sql": sql, "result": result, "status": status,
                  "answer": sub.get("answer", "")}
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
        assert cfg is not None  # live implies a valid config (see oracle_available)
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


# Minimal domain hint given to the agent-under-test (NOT the full 989-line prod
# prompt — a thin baseline; the benchmark measures how well the agent copes).
_SCHEMA_HINT = (
    "Oracle-таблица client_product — помесячный снимок по корпоративному клиенту "
    "(одна строка = клиент × месяц). Колонки: MONTH_DT (дата снимка; у закрытого "
    "месяца конец месяца, у текущего НЕ конец — используй MAX(MONTH_DT)); "
    "CREATE_DT/CLOSE_DT (открытие/закрытие клиента); INN, ORGANIZATION_NM, GROUP_NM, "
    "SEG (сегмент); CA_LCY_SUM, CA_LCY_RUB_SUM, DEP_SUM (остатки/депозиты — за "
    "период усредняются по месяцам, не суммируются); FX_VOLUME_RUB, FX_CNT, "
    "FX_MARGIN_RUB (FX); PNL_SUM (итоговый доход = сумма компонентов + прочее); "
    "PL_CA, PL_DEP, PL_VK, PL_VK_OUT, VED_SUM (компоненты дохода); VED_VOL (объём "
    "ВЭД-платежей); ACT_1M, ACT_3M (флаги активности 0/1)."
)


def _extract_sql(text: str) -> str:
    """Pull a single SELECT out of an LLM reply. Empty string == no SQL / refusal."""
    if not text or "NO_SQL" in text:
        return ""
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL | re.IGNORECASE)
    for pat in (r"```sql\s*(.+?)```", r"```\s*(select.+?)```", r"(select\b.+)"):
        m = re.search(pat, text, flags=re.DOTALL | re.IGNORECASE)
        if m:
            return m.group(1).strip().rstrip(";").strip()
    return ""


@dataclass
class OllamaSolver:
    """Real agent-under-test: an ollama model generates the SQL (OpenAI-compatible
    /chat/completions via stdlib urllib — no SDK dependency). result/status are
    filled by the live OracleExecutor. Config from env (AI_ANALYST_API_URL /
    _API_KEY / _SQL_MODEL). A guardrail task is handled honestly: if the model
    emits NO_SQL we record a refusal."""
    model: str = ""
    base_url: str = ""
    api_key: str = ""
    temperature: float = 0.1
    timeout_s: int = 180

    def __post_init__(self) -> None:
        self.base_url = self.base_url or os.getenv("AI_ANALYST_API_URL", "http://localhost:11434/v1")
        self.api_key = self.api_key or os.getenv("AI_ANALYST_API_KEY", "ollama")
        self.model = self.model or os.getenv(
            "AI_ANALYST_SQL_MODEL", "alibayram/Qwen3-30B-A3B-Instruct-2507")

    def _prompt(self, task: dict) -> str:
        out = ""
        if task.get("output_columns"):
            out = ("\nВерни ровно столбцы с такими псевдонимами (alias): "
                   + ", ".join(task["output_columns"]) + ".")
        return (_SCHEMA_HINT + "\n\nВопрос: " + task["nl"]
                + "\n\nВерни ОДИН Oracle SQL-запрос (только SELECT) в блоке ```sql ... ```. "
                + "Если данных для ответа в таблице нет — верни строго NO_SQL." + out)

    def _call(self, prompt: str) -> str:
        import urllib.request
        body = json.dumps({
            "model": self.model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": self.temperature,
            "stream": False,
        }).encode("utf-8")
        req = urllib.request.Request(
            self.base_url.rstrip("/") + "/chat/completions", data=body, method="POST",
            headers={"Content-Type": "application/json",
                     "Authorization": f"Bearer {self.api_key}"})
        with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"]

    def solve(self, task: dict) -> dict:
        text = self._call(self._prompt(task))
        sql = _extract_sql(text)
        if not sql:
            return {"sql": "", "result": None, "status": "refused",
                    "answer": text[:500], "retries": 0}
        return {"sql": sql, "result": None, "status": "success", "answer": "", "retries": 0}


if __name__ == "__main__":
    rep = run_benchmark()
    print(json.dumps(rep, indent=2, ensure_ascii=False, default=str))
    if rep["mode"] == "dry-run":
        print(f"\n[dry-run] {rep['degrade_reason']}")
        print("[dry-run] axes 1-4 scored on reference-solver result; "
              "axis-5 live sub-check (sql_executed) skipped; axis-6 computed.")
    # exit 0 always: a missing live stack is a degrade, not a failure.
