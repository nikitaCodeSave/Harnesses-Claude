#!/usr/bin/env python3
"""pipeline-ab multi-session scoring.

  score_long.py calibrate <task>        — oracle sizes from the reference chain f1 -> fn
  score_long.py run <task> <arm>-<rep>  — score one run's final state
  score_long.py summary                 — per arm: min / median / max

Primary metric: test_cross — later features respecting decisions voiced "for later" in earlier ones;
where the task has test_reversal (L2), transfer = test_cross and test_reversal together.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

import score
from score import bracket, pytest

HERE = pathlib.Path(__file__).resolve().parent
TASKS = HERE / "tasks-long"
RESULTS = pathlib.Path(os.environ.get("PAB_RESULTS", HERE / "results-long"))
ORACLES = [f"test_f{k}" for k in range(1, 9)] + ["test_cross", "test_reversal", "test_regression"]


def run_oracles(src_root, task, tmp):
    oracle = tmp / "oracle"
    if not oracle.exists():
        shutil.copytree(TASKS / task / "oracle", oracle)
    env = dict(os.environ, PYTHONPATH=str(src_root), PYTHONDONTWRITEBYTECODE="1")
    return {o: pytest([str(oracle / f"{o}.py")], tmp, env, tmp / f"{o}.xml") for o in ORACLES
            if (oracle / f"{o}.py").exists()}


def calibrate(task):
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        ref = tmp / "ref"
        shutil.copytree(TASKS / task / "repo", ref)
        for f in sorted((TASKS / task / "reference").glob("f*.patch")):
            subprocess.run(["patch", "-s", "-p1", "-i", str(f)], cwd=ref, check=True)
        res = run_oracles(ref / "src", task, tmp)
    counts = {o: r["tests"] for o, r in res.items()}
    ok = all(r["passed"] == r["tests"] > 0 for r in res.values())
    (TASKS / task / "oracle_counts.json").write_text(json.dumps(counts))
    print(task, {o: f"{r['passed']}/{r['tests']}" for o, r in res.items()}, "OK" if ok else "FAIL")
    return ok


def artefacts(ws):
    adr = list(ws.glob("**/adr/*.md")) + list(ws.glob("**/ADR/*.md"))
    return {"glossary": any(ws.glob("**/GLOSSARY.md")), "adr_files": len([a for a in adr if ".git" not in a.parts]),
            "scratch": (ws / ".scratch").exists(), "spec_md": (ws / "SPEC.md").exists(),
            "spec_files": len(list(ws.glob("specs/*.md")))}


def per_feature(rdir, meta):
    out = {}
    for f in sorted((rdir / "calls").glob("*.json")):
        c = json.loads(f.read_text())
        fid = c["label"].split(":")[0]
        d = out.setdefault(fid, {"dev_cost_usd": 0.0, "user_turns": 0, "dev_calls": 0})
        if c["role"] != "user":
            d["dev_cost_usd"] = round(d["dev_cost_usd"] + (c.get("total_cost_usd") or 0), 3)
            d["dev_calls"] += 1
    for st in meta.get("stages", []):
        out.setdefault(st["label"].split(":")[0], {"dev_cost_usd": 0.0, "user_turns": 0, "dev_calls": 0})[
            "user_turns"] += st.get("user_turns", 0)
    return out


def foreign_refs(meta):
    slug = re.sub(r"[^A-Za-z0-9]", "-", meta["workspace"])
    pdir = pathlib.Path("~/.claude/projects").expanduser() / slug
    own = meta["workspace"].split("/")[-2]
    hits = set()
    for f in pdir.glob("*.jsonl") if pdir.exists() else []:
        t = f.read_text(errors="replace")
        if "Your private notes are the ground truth" in t:
            continue
        hits |= {x for x in re.findall(r"/tmp/pab-work[\w-]*/([\w.-]+)/ws", t) if x != own}
        hits |= {n for n in ("pipeline-ab", "Harnesses-Claude", "NOTES.md", "test_cross.py", "test_reversal.py")
                 if n in t}
    return sorted(hits)


def score_run(task, name):
    rdir = RESULTS / task / name
    meta = json.loads((rdir / "meta.json").read_text())
    ws = pathlib.Path(meta["workspace"])
    counts = json.loads((TASKS / task / "oracle_counts.json").read_text())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        wsc = tmp / "ws"
        shutil.copytree(ws, wsc, ignore=shutil.ignore_patterns(".git", "__pycache__", ".pytest_cache"))
        subprocess.run(["chmod", "-R", "u+w", str(wsc)])
        res = run_oracles(wsc / "src", task, tmp)
    out = {"task": task, "run": name, "arm": meta["arm"],
           "oracles": {o: {"passed": r["passed"], "total": counts.get(o, r["tests"]),
                           "interface_broken": r["collect_error"]} for o, r in res.items()},
           "per_feature": per_feature(rdir, meta), "features": meta.get("features"),
           "artefacts": artefacts(ws), "wall_s": meta.get("wall_s"),
           "dev_cost_usd": round(sum(v["dev_cost_usd"] for v in per_feature(rdir, meta).values()), 3),
           "user_turns": sum(v["user_turns"] for v in per_feature(rdir, meta).values()),
           "errors": meta.get("errors", []), "overrun": meta.get("overrun", []), "leaks": foreign_refs(meta)}
    (rdir / "score.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
    o = out["oracles"]
    print(f"{task} {name}: " + " ".join(f"{k[5:]} {v['passed']}/{v['total']}" for k, v in o.items())
          + f" cost ${out['dev_cost_usd']} turns {out['user_turns']} art {out['artefacts']} leaks {out['leaks']}")
    return out


def pooled(score, names):
    """Share of passed tests over several oracles together, in %."""
    o = [score["oracles"][n] for n in names if n in score["oracles"]]
    total = sum(d["total"] for d in o)
    return round(100 * sum(d["passed"] for d in o) / total, 1) if total else 0.0


def summary():
    for tdir in sorted(p for p in RESULTS.iterdir() if p.is_dir()):
        counts = json.loads((TASKS / tdir.name / "oracle_counts.json").read_text())
        feats = sorted(o for o in counts if re.fullmatch(r"test_f\d+", o))
        cols = [("transfer %", ["test_cross", "test_reversal"])] if "test_reversal" in counts else []
        cols += [("cross %", ["test_cross"])] + ([("reversal %", ["test_reversal"])] if "test_reversal" in counts else [])
        cols += [("acceptance %", feats)] + [(f"F{f[6:]} %", [f]) for f in feats] + [("regression %", ["test_regression"])]
        rows = ["| arm | n | " + " | ".join(c for c, _ in cols) + " | cost $ | wall min | user turns |",
                "|---|---|" + "---|" * len(cols) + "---|---|---|"]
        for arm in ("S", "K", "PL", "N"):
            sc = [json.loads(f.read_text()) for f in sorted(tdir.glob(f"{arm}-*/score.json"))]
            if not sc:
                continue
            rows.append("| " + " | ".join([arm, str(len(sc))] + [bracket([pooled(s, names) for s in sc]) for _, names in cols]
                        + [bracket([s["dev_cost_usd"] for s in sc]),
                           bracket([round((s["wall_s"] or 0) / 60, 1) for s in sc]),
                           bracket([s["user_turns"] for s in sc])]) + " |")
        print(f"## {tdir.name} — min / median / max per cell\n\n" + "\n".join(rows) + "\n")


if __name__ == "__main__":
    cmd = sys.argv[1:2]
    if cmd == ["calibrate"]:
        sys.exit(0 if calibrate(sys.argv[2]) else 1)
    elif cmd == ["run"]:
        score_run(sys.argv[2], sys.argv[3])
    elif cmd == ["summary"]:
        summary()
    else:
        sys.exit(__doc__)
