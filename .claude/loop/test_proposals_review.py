"""Unit tests for proposals-review.py — runs under pytest with no external deps."""
from __future__ import annotations
import importlib.util
import sys
from pathlib import Path

import pytest


def _load_module():
    """Import proposals-review.py (hyphen in name → spec_from_file_location)."""
    path = Path(__file__).parent / "proposals-review.py"
    spec = importlib.util.spec_from_file_location("proposals_review", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["proposals_review"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def pr():
    return _load_module()


@pytest.fixture
def proposals_dir(tmp_path):
    d = tmp_path / "proposals"
    d.mkdir()
    return d


@pytest.fixture
def journal_path(tmp_path):
    return tmp_path / "journal.md"


def _write_diff(d: Path, name: str, body: str) -> Path:
    p = d / name
    p.write_text(body)
    return p


# ---------- parse_proposal_filename ----------

def test_parse_proposal_filename_valid(pr):
    assert pr.parse_proposal_filename("iter-0011-run.sh.diff") == (11, "run.sh")
    assert pr.parse_proposal_filename("iter-0042-PROMPT.md.diff") == (42, "PROMPT.md")


def test_parse_proposal_filename_invalid(pr):
    assert pr.parse_proposal_filename("REVIEW.md") is None
    assert pr.parse_proposal_filename("iter-99-foo.diff") is None  # 2 digits, not 4
    assert pr.parse_proposal_filename("iter-0001-foo.txt") is None  # not .diff


# ---------- diff_stats ----------

def test_diff_stats_basic(pr, tmp_path):
    p = tmp_path / "a.diff"
    p.write_text(
        "--- a/foo.txt\n"
        "+++ b/foo.txt\n"
        "@@ -1,3 +1,4 @@\n"
        " context\n"
        "-removed line\n"
        "+added line\n"
        "+another added\n"
    )
    assert pr.diff_stats(p) == (2, 1)


def test_diff_stats_skips_file_headers(pr, tmp_path):
    p = tmp_path / "b.diff"
    # Without skipping +++/---, naive count would say (3, 2) instead of (2, 1)
    p.write_text(
        "--- a/x\n"
        "+++ b/x\n"
        "@@\n"
        "+one\n"
        "+two\n"
        "-removed\n"
    )
    assert pr.diff_stats(p) == (2, 1)


def test_diff_stats_empty(pr, tmp_path):
    p = tmp_path / "empty.diff"
    p.write_text("")
    assert pr.diff_stats(p) == (0, 0)


def test_diff_stats_missing_file(pr, tmp_path):
    p = tmp_path / "nope.diff"
    assert pr.diff_stats(p) == (0, 0)


# ---------- collect_proposals ----------

def test_collect_proposals_empty_dir(pr, proposals_dir):
    assert pr.collect_proposals(proposals_dir) == []


def test_collect_proposals_nonexistent_dir(pr, tmp_path):
    assert pr.collect_proposals(tmp_path / "no") == []


def test_collect_proposals_sorted_desc(pr, proposals_dir):
    _write_diff(proposals_dir, "iter-0005-run.sh.diff", "+a\n")
    _write_diff(proposals_dir, "iter-0011-PROMPT.md.diff", "+b\n+c\n-d\n")
    _write_diff(proposals_dir, "iter-0007-corpus.yml.diff", "+e\n")
    out = pr.collect_proposals(proposals_dir)
    assert [x["iter"] for x in out] == [11, 7, 5]
    p11 = out[0]
    assert p11["basename"] == "PROMPT.md"
    assert p11["added"] == 2
    assert p11["removed"] == 1


def test_collect_proposals_skips_review_md(pr, proposals_dir):
    _write_diff(proposals_dir, "iter-0001-foo.diff", "+x\n")
    _write_diff(proposals_dir, "REVIEW.md", "# review\n")
    out = pr.collect_proposals(proposals_dir)
    assert len(out) == 1
    assert out[0]["basename"] == "foo"


# ---------- collect_journal_proposals ----------

def test_collect_journal_proposals_parses(pr, journal_path):
    journal_path.write_text(
        "# header\n"
        "2026-05-11 03:30:00Z iter-0011 PROPOSAL H-018 .claude/loop/run.sh\n"
        "2026-05-11 04:00:00Z iter-0012 ACCEPTED H-019 some thing\n"
        "2026-05-11 05:00:00Z iter-0013 PROPOSAL H-020 .claude/CLAUDE.md\n"
    )
    j = pr.collect_journal_proposals(journal_path)
    assert set(j.keys()) == {11, 13}
    assert j[11]["hyp"] == "H-018"
    assert j[11]["target"] == ".claude/loop/run.sh"
    assert j[13]["target"] == ".claude/CLAUDE.md"


def test_collect_journal_proposals_missing_file(pr, tmp_path):
    assert pr.collect_journal_proposals(tmp_path / "no.md") == {}


# ---------- render_review ----------

def test_render_review_empty(pr, proposals_dir):
    out = pr.render_review([], {})
    assert "Pending: 0" not in out  # we use markdown bold
    assert "**Pending**: 0" in out
    assert "_No proposals awaiting review._" in out


def test_render_review_with_journal(pr, proposals_dir):
    _write_diff(proposals_dir, "iter-0011-run.sh.diff", "+x\n+y\n-z\n")
    proposals = pr.collect_proposals(proposals_dir)
    journal = {11: {"timestamp": "2026-05-11 03:30:00Z",
                    "hyp": "H-018",
                    "target": ".claude/loop/run.sh"}}
    out = pr.render_review(proposals, journal)
    assert "iter-0011 — H-018" in out
    assert "`.claude/loop/run.sh`" in out
    assert "+2/-1" in out
    assert "2026-05-11 03:30:00Z" in out


def test_render_review_orphan_diff(pr, proposals_dir):
    _write_diff(proposals_dir, "iter-0099-foo.diff", "+a\n")
    proposals = pr.collect_proposals(proposals_dir)
    out = pr.render_review(proposals, {})
    assert "H-???" in out
    assert "orphan diff" in out


# ---------- main / CLI ----------

def test_main_writes_review_md(pr, proposals_dir, journal_path, capsys):
    _write_diff(proposals_dir, "iter-0011-x.diff", "+a\n")
    journal_path.write_text("")
    rc = pr.main.__wrapped__() if hasattr(pr.main, "__wrapped__") else None
    # Direct invocation through argv:
    sys.argv = [
        "proposals-review.py",
        "--proposals-dir", str(proposals_dir),
        "--journal", str(journal_path),
    ]
    rc = pr.main()
    assert rc == 0
    review = proposals_dir / "REVIEW.md"
    assert review.exists()
    content = review.read_text()
    assert "iter-0011" in content
    assert "**Pending**: 1" in content
    captured = capsys.readouterr()
    assert "REVIEW.md regenerated" in captured.out


def test_main_stdout_mode(pr, proposals_dir, journal_path, capsys):
    sys.argv = [
        "proposals-review.py",
        "--proposals-dir", str(proposals_dir),
        "--journal", str(journal_path),
        "--stdout",
    ]
    rc = pr.main()
    assert rc == 0
    out = capsys.readouterr().out
    assert "**Pending**: 0" in out
    # In stdout mode, REVIEW.md must NOT be written:
    assert not (proposals_dir / "REVIEW.md").exists()


def test_main_check_zero_pending_exits_zero(pr, proposals_dir, journal_path):
    sys.argv = [
        "proposals-review.py",
        "--proposals-dir", str(proposals_dir),
        "--journal", str(journal_path),
        "--check", "--stdout",
    ]
    rc = pr.main()
    assert rc == 0


def test_main_check_pending_exits_one(pr, proposals_dir, journal_path):
    _write_diff(proposals_dir, "iter-0011-x.diff", "+a\n")
    sys.argv = [
        "proposals-review.py",
        "--proposals-dir", str(proposals_dir),
        "--journal", str(journal_path),
        "--check", "--stdout",
    ]
    rc = pr.main()
    assert rc == 1
