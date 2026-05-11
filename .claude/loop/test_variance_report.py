"""Unit tests for variance-report.py — runs under pytest with no fixtures dir."""
from __future__ import annotations
import importlib.util
import json
import sys
from pathlib import Path

import pytest


def _load_module():
    path = Path(__file__).parent / "variance-report.py"
    spec = importlib.util.spec_from_file_location("variance_report", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["variance_report"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def vr():
    return _load_module()


@pytest.fixture
def make_report(tmp_path):
    def _make(iter_n: int, task: str, fixture: str, *, tokens=2000, turns=10,
              files=3, cost=0.30, success=True):
        d = tmp_path / "reports"
        d.mkdir(exist_ok=True)
        name = f"iter-{iter_n:04d}-{task}-{fixture}.json"
        p = d / name
        p.write_text(json.dumps({
            "task": task, "fixture": fixture,
            "claude": {"num_turns": turns, "cost_usd": cost,
                       "tokens": {"input": 0, "output": tokens}},
            "verification": {"files_changed": files,
                             "pytest": {"status": "pass" if success else "fail"}},
        }))
        return p
    return _make


def test_parse_iter_filename(vr):
    assert vr.parse_iter_filename(Path("iter-0007-T01-sample-py-app.json")) == (
        7, "T01", "sample-py-app")


def test_cv_of_two_equal_values_is_zero(vr):
    m, s, cv = vr.cv_of([100, 100])
    assert m == 100
    assert s == 0
    assert cv == 0


def test_cv_of_single_value_is_zero(vr):
    m, s, cv = vr.cv_of([42])
    assert m == 42
    assert s == 0
    assert cv == 0


def test_cv_of_empty_is_zero(vr):
    assert vr.cv_of([]) == (0.0, 0.0, 0.0)


def test_cv_of_high_variance_yields_high_cv(vr):
    _m, _s, cv = vr.cv_of([1000, 3000, 5000])
    assert cv > 30.0


def test_cv_of_low_variance_yields_low_cv(vr):
    _m, _s, cv = vr.cv_of([1000, 1010, 990])
    assert cv < 5.0


def test_collect_groups_by_task_fixture(vr, tmp_path, make_report, monkeypatch):
    make_report(1, "T01", "sample-py-app", tokens=2000)
    make_report(2, "T01", "sample-py-app", tokens=2400)
    make_report(2, "T02", "sample-py-app", tokens=3000)
    monkeypatch.chdir(tmp_path)
    by_key = vr.collect("reports/iter-*.json")
    assert set(by_key.keys()) == {("T01", "sample-py-app"), ("T02", "sample-py-app")}
    assert len(by_key[("T01", "sample-py-app")]) == 2
    assert {m["tokens"] for m in by_key[("T01", "sample-py-app")]} == {2000, 2400}


def test_compute_flags_high_cv_above_threshold(vr, tmp_path, make_report, monkeypatch):
    # tokens range 1000..5000 (mean 3000, large stdev) → CV well above 30%
    for i, tok in enumerate([1000, 3000, 5000], start=1):
        make_report(i, "T01", "fx", tokens=tok)
    monkeypatch.chdir(tmp_path)
    by_key = vr.collect("reports/iter-*.json")
    rows = vr.compute(by_key, threshold_pct=30.0, min_n=3)
    tok_row = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok_row["n"] == 3
    assert tok_row["cv_pct"] > 30.0
    assert tok_row["flag"] is True


def test_compute_does_not_flag_below_min_n(vr, tmp_path, make_report, monkeypatch):
    # only 2 reports → n < min_n=3 → no flag regardless of variance
    make_report(1, "T01", "fx", tokens=1000)
    make_report(2, "T01", "fx", tokens=5000)
    monkeypatch.chdir(tmp_path)
    by_key = vr.collect("reports/iter-*.json")
    rows = vr.compute(by_key, threshold_pct=30.0, min_n=3)
    tok_row = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok_row["n"] == 2
    assert tok_row["below_min_n"] is True
    assert tok_row["flag"] is False


def test_compute_no_flag_for_low_variance(vr, tmp_path, make_report, monkeypatch):
    for i, tok in enumerate([2000, 2010, 1990], start=1):
        make_report(i, "T01", "fx", tokens=tok)
    monkeypatch.chdir(tmp_path)
    by_key = vr.collect("reports/iter-*.json")
    rows = vr.compute(by_key, threshold_pct=30.0, min_n=3)
    tok_row = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok_row["flag"] is False


def test_collect_empty_glob_returns_empty(vr, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert vr.collect("reports/iter-*.json") == {}


def test_extract_metrics_matches_shared_schema(vr):
    r = {"claude": {"num_turns": 11, "cost_usd": 0.42,
                    "tokens": {"input": 100, "output": 1900}},
         "verification": {"files_changed": 5, "pytest": {"status": "pass"}}}
    m = vr.extract_metrics(r)
    assert m["tokens"] == 2000
    assert m["turns"] == 11
    assert m["files"] == 5
    assert m["cost_usd"] == pytest.approx(0.42)
    assert m["success"] == 1.0
