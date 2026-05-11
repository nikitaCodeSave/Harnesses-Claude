"""Unit tests for cross-fixture-check.py — pytest, no external fixtures."""
from __future__ import annotations
import importlib.util
import json
import sys
from pathlib import Path

import pytest


def _load_module():
    path = Path(__file__).parent / "cross-fixture-check.py"
    spec = importlib.util.spec_from_file_location("cross_fixture_check", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["cross_fixture_check"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def cfc():
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


def test_parse_iter_filename(cfc):
    assert cfc.parse_iter_filename(Path("iter-0009-T01-sample-py-app.json")) == (
        9, "T01", "sample-py-app")


def test_spread_pct_single_value_is_zero(cfc):
    assert cfc.spread_pct([1000]) == 0.0


def test_spread_pct_equal_values_is_zero(cfc):
    assert cfc.spread_pct([1000, 1000, 1000]) == 0.0


def test_spread_pct_high(cfc):
    # 1000 vs 2000 → max/min - 1 = 100%
    assert cfc.spread_pct([1000, 2000]) == pytest.approx(100.0)


def test_spread_pct_low(cfc):
    # 1000 vs 1050 → 5%
    assert cfc.spread_pct([1000, 1050]) == pytest.approx(5.0)


def test_collect_groups_by_task_fixture(cfc, tmp_path, make_report, monkeypatch):
    make_report(1, "T01", "sample-py-app", tokens=1000)
    make_report(2, "T01", "sample-py-app", tokens=1100)
    make_report(3, "T01", "fastapi-tpl", tokens=2000)
    make_report(4, "T02", "sample-py-app", tokens=3000)
    monkeypatch.chdir(tmp_path)
    by_task = cfc.collect("reports/iter-*.json")
    assert set(by_task.keys()) == {"T01", "T02"}
    assert set(by_task["T01"].keys()) == {"sample-py-app", "fastapi-tpl"}
    assert len(by_task["T01"]["sample-py-app"]) == 2
    assert len(by_task["T02"]["sample-py-app"]) == 1


def test_compute_skips_single_fixture_tasks(cfc, tmp_path, make_report, monkeypatch):
    make_report(1, "T01", "sample-py-app", tokens=1000)
    make_report(2, "T01", "sample-py-app", tokens=1100)
    monkeypatch.chdir(tmp_path)
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=None,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=1)
    assert rows == []


def test_compute_flags_high_spread(cfc, tmp_path, make_report, monkeypatch):
    # T01: fixture A tokens 1000, fixture B tokens 2000 → spread 100% > 30%
    make_report(1, "T01", "fxA", tokens=1000)
    make_report(2, "T01", "fxA", tokens=1000)
    make_report(3, "T01", "fxB", tokens=2000)
    make_report(4, "T01", "fxB", tokens=2000)
    monkeypatch.chdir(tmp_path)
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=None,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=2)
    tok = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok["spread_pct"] == pytest.approx(100.0)
    assert tok["spread_flag"] is True
    assert tok["sign_inversion"] is False  # no baseline


def test_compute_no_spread_flag_for_low_spread(cfc, tmp_path, make_report, monkeypatch):
    make_report(1, "T01", "fxA", tokens=1000)
    make_report(2, "T01", "fxB", tokens=1050)
    monkeypatch.chdir(tmp_path)
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=None,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=1)
    tok = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok["spread_pct"] == pytest.approx(5.0)
    assert tok["spread_flag"] is False


def test_compute_below_min_n_suppresses_spread_flag(cfc, tmp_path, make_report,
                                                    monkeypatch):
    # fxA n=1, fxB n=1 — even huge spread shouldn't flag when n < min_n=2
    make_report(1, "T01", "fxA", tokens=1000)
    make_report(2, "T01", "fxB", tokens=3000)
    monkeypatch.chdir(tmp_path)
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=None,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=2)
    tok = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok["below_min_n"] is True
    assert tok["spread_flag"] is False


def test_compute_detects_sign_inversion(cfc, tmp_path, make_report, monkeypatch):
    # baseline T01.tokens.mean = 2000
    # fxA tokens = 1000 (delta -50% vs baseline)
    # fxB tokens = 3000 (delta +50% vs baseline)
    # → opposite signs, both exceed noise=10% → SIGN_INVERSION
    make_report(1, "T01", "fxA", tokens=1000)
    make_report(2, "T01", "fxB", tokens=3000)
    monkeypatch.chdir(tmp_path)
    baseline = {"T01": {"tokens": {"mean": 2000}}}
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=baseline,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=1)
    tok = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok["sign_inversion"] is True
    assert tok["deltas_pct"]["fxA"] == pytest.approx(-50.0)
    assert tok["deltas_pct"]["fxB"] == pytest.approx(50.0)


def test_compute_no_sign_inversion_when_same_sign(cfc, tmp_path, make_report,
                                                  monkeypatch):
    # both fixtures regress vs baseline → no inversion
    make_report(1, "T01", "fxA", tokens=2400)  # +20%
    make_report(2, "T01", "fxB", tokens=2600)  # +30%
    monkeypatch.chdir(tmp_path)
    baseline = {"T01": {"tokens": {"mean": 2000}}}
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=baseline,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=1)
    tok = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok["sign_inversion"] is False


def test_compute_no_sign_inversion_when_deltas_below_noise(cfc, tmp_path,
                                                           make_report, monkeypatch):
    # one fixture +5%, other -5% — both within noise=10% → no flag
    make_report(1, "T01", "fxA", tokens=1900)   # -5%
    make_report(2, "T01", "fxB", tokens=2100)   # +5%
    monkeypatch.chdir(tmp_path)
    baseline = {"T01": {"tokens": {"mean": 2000}}}
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=baseline,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=1)
    tok = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok["sign_inversion"] is False


def test_compute_no_sign_inversion_without_baseline(cfc, tmp_path, make_report,
                                                    monkeypatch):
    make_report(1, "T01", "fxA", tokens=1000)
    make_report(2, "T01", "fxB", tokens=3000)
    monkeypatch.chdir(tmp_path)
    by_task = cfc.collect("reports/iter-*.json")
    rows = cfc.compute(by_task, baseline=None,
                       spread_threshold_pct=30.0, noise_threshold_pct=10.0, min_n=1)
    tok = [r for r in rows if r["metric"] == "tokens"][0]
    assert tok["sign_inversion"] is False


def test_any_flag_helper(cfc):
    assert cfc.any_flag({"spread_flag": True, "sign_inversion": False}) is True
    assert cfc.any_flag({"spread_flag": False, "sign_inversion": True}) is True
    assert cfc.any_flag({"spread_flag": False, "sign_inversion": False}) is False


def test_extract_metrics_matches_shared_schema(cfc):
    r = {"claude": {"num_turns": 11, "cost_usd": 0.42,
                    "tokens": {"input": 100, "output": 1900}},
         "verification": {"files_changed": 5, "pytest": {"status": "pass"}}}
    m = cfc.extract_metrics(r)
    assert m["tokens"] == 2000
    assert m["turns"] == 11
    assert m["files"] == 5
    assert m["cost_usd"] == pytest.approx(0.42)
    assert m["success"] == 1.0


def test_collect_empty_glob_returns_empty(cfc, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert cfc.collect("reports/iter-*.json") == {}
