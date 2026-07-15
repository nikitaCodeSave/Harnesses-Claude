"""Unit tests for aggregate-metrics.py — runs under pytest with no fixtures dir."""
from __future__ import annotations
import importlib.util
import json
import sys
from pathlib import Path

import pytest


def _load_module():
    """Import aggregate-metrics.py (hyphen in name → spec_from_file_location)."""
    path = Path(__file__).parent / "aggregate-metrics.py"
    spec = importlib.util.spec_from_file_location("aggregate_metrics", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["aggregate_metrics"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def am():
    return _load_module()


@pytest.fixture
def make_report(tmp_path):
    def _make(iter_n: int, task: str, fixture: str, *, tokens=2000, turns=10,
             files=3, cost=0.30, success=True, wall=40):
        d = tmp_path / "reports"
        d.mkdir(exist_ok=True)
        name = f"iter-{iter_n:04d}-{task}-{fixture}.json"
        p = d / name
        p.write_text(json.dumps({
            "task": task, "fixture": fixture, "harness_injected": True,
            "timing": {"start": "x", "end": "y", "wall_seconds": wall},
            "claude": {
                "exit_code": 0, "stop_reason": "end_turn", "num_turns": turns,
                "cost_usd": cost,
                "tokens": {"input": 0, "output": tokens, "cache_creation": 0, "cache_read": 0},
            },
            "verification": {
                "files_changed": files,
                "pytest": {"status": "pass" if success else "fail", "reason": "x"},
            },
            "result_excerpt": "", "stderr_tail": "",
        }))
        return p
    return _make


def test_parse_iter_filename(am):
    p = Path("iter-0007-T01-sample-py-app.json")
    assert am.parse_iter_filename(p) == (7, "T01", "sample-py-app")


def test_parse_iter_filename_rejects_unrelated(am):
    assert am.parse_iter_filename(Path("T01-foo-bar.json")) is None


def test_extract_metrics_canonicalizes_nested_schema(am):
    r = {
        "claude": {"num_turns": 11, "cost_usd": 0.42,
                   "tokens": {"input": 100, "output": 1900}},
        "verification": {"files_changed": 5, "pytest": {"status": "pass"}},
        "timing": {"wall_seconds": 33},
    }
    m = am.extract_metrics(r)
    assert m["tokens"] == 2000
    assert m["turns"] == 11
    assert m["files"] == 5
    assert m["cost_usd"] == pytest.approx(0.42)
    assert m["success"] == 1.0
    assert m["wall_sec"] == 33


def test_extract_metrics_failed_pytest(am):
    r = {"claude": {"num_turns": 1, "cost_usd": 0, "tokens": {}},
         "verification": {"files_changed": 0, "pytest": {"status": "fail"}}}
    assert am.extract_metrics(r)["success"] == 0.0


def test_collect_groups_by_iter_and_task(am, tmp_path, make_report, monkeypatch):
    make_report(1, "T01", "sample-py-app", tokens=2400)
    make_report(1, "T02", "sample-py-app", tokens=2500)
    make_report(2, "T01", "sample-py-app", tokens=2200)
    monkeypatch.chdir(tmp_path)
    by_iter = am.collect("reports/iter-*.json")
    assert set(by_iter.keys()) == {1, 2}
    assert set(by_iter[1].keys()) == {"T01", "T02"}
    assert by_iter[1]["T01"][0]["tokens"] == 2400


def test_aggregate_means_across_fixtures(am, tmp_path, make_report, monkeypatch):
    make_report(1, "T01", "fixA", tokens=2000)
    make_report(1, "T01", "fixB", tokens=3000)
    monkeypatch.chdir(tmp_path)
    by_iter = am.collect("reports/iter-*.json")
    agg = am.aggregate(by_iter)
    assert agg[1]["T01"]["n_fixtures"] == 2
    assert agg[1]["T01"]["tokens"] == 2500


def test_collect_empty_glob_returns_empty(am, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert am.collect("reports/iter-*.json") == {}


def test_delta_vs_baseline_handles_zero(am):
    assert "--" in am.delta_vs_baseline(100, 0)
    assert am.delta_vs_baseline(110, 100).strip().startswith("+10")
