"""Axes 1-4 scorer for benchmark v2 (auto-measurable, deterministic gate).

A submission per task is a dict: {"sql": str, "result": <value>, "status": str}.
  result type matches the task's golden_kind:
    number      -> int|float
    number_map  -> {key: number}
    id_set      -> iterable of ids
score_submission returns per-axis booleans + an overall gate_pass.

Axis 1  numeric correctness vs golden (±tol_pct; exact for id sets).
Axis 2  SQL structural anchors (must_contain all / must_not_contain none).
Axis 3  empty-result-honesty: result empty + status=success while golden is
        non-empty  ==  the F1 "silent empty passed as success" failure.
Axis 4  aggregation-semantics for balance fields over multi-month periods:
        a balance field must be averaged via two-step (AVG over a per-month
        SUM), never SUM'd raw and never AVG'd directly on the column.
"""
from __future__ import annotations

import re


def _num_ok(a, g, tol_pct: float) -> bool:
    try:
        a = float(a)
        g = float(g)
    except (TypeError, ValueError):
        return False
    if g == 0:
        return abs(a) <= 1e-9
    return abs(a - g) <= tol_pct * abs(g)


def _is_empty(result, status: str) -> bool:
    if result is None:
        return True
    if isinstance(result, (str, list, dict, tuple, set)) and len(result) == 0:
        return True
    if isinstance(result, str) and "не найден" in result.lower():
        return True
    if status in ("no_data", "error"):
        return True
    return False


def _axis1(task, result) -> bool:
    kind, golden, tol = task["golden_kind"], task["golden"], task["tol_pct"]
    if kind == "number":
        return _num_ok(result, golden, tol)
    if kind == "number_map":
        if not isinstance(result, dict):
            return False
        return all(k in result and _num_ok(result[k], gv, tol) for k, gv in golden.items())
    if kind == "id_set":
        try:
            return {int(x) for x in result} == {int(x) for x in golden}
        except (TypeError, ValueError):
            return False
    raise ValueError(f"unknown golden_kind {kind!r}")


def _axis2(task, sql: str) -> bool:
    s = (sql or "").lower()
    if not all(re.search(p, s) for p in task["must_contain"]):
        return False
    if any(re.search(p, s) for p in task["must_not_contain"]):
        return False
    return True


def _axis3(result, status: str) -> bool:
    # golden is always non-empty in this suite; flag the silent-empty failure.
    silent_empty = _is_empty(result, status) and status not in ("error",)
    return not silent_empty


def _axis4(task, sql: str):
    bf = task.get("balance_field")
    if not bf or not task.get("multi_month"):
        return None   # not applicable
    s = (sql or "").lower()
    b = bf.lower()
    has_sum_bf = re.search(r"sum\s*\(\s*" + b + r"\s*\)", s) is not None
    has_avg_bf = re.search(r"avg\s*\(\s*" + b + r"\s*\)", s) is not None
    has_avg = re.search(r"avg\s*\(", s) is not None
    if has_avg_bf:                      # direct AVG on the raw balance column
        return False
    if has_sum_bf and not has_avg:      # summed across months, never averaged
        return False
    return True


def score_submission(task, submission) -> dict:
    sql = submission.get("sql", "")
    result = submission.get("result")
    status = submission.get("status", "success")

    ax1 = _axis1(task, result)
    ax2 = _axis2(task, sql)
    ax3 = _axis3(result, status)
    ax4 = _axis4(task, sql)

    applicable = [ax1, ax2, ax3] + ([ax4] if ax4 is not None else [])
    return {
        "id": task["id"],
        "ax1_numeric": ax1,
        "ax2_anchors": ax2,
        "ax3_empty_honesty": ax3,
        "ax4_aggregation": ax4,          # None == N/A
        "gate_pass": all(applicable),
    }
