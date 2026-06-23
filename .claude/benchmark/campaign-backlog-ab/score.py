#!/usr/bin/env python3
"""Детерминированный oracle для A/B single-canon vs dual-canon.

Usage: python3 score.py <run_dir>
Печатает JSON-метрики, сравнивая run_dir/backlog.md и run_dir/features.json
с ground-truth.json (лежит рядом со скриптом).

Метрики:
  md_core_accuracy   — доля верных (existence+status+priority) по всем GT-задачам, из backlog.md
  json_core_accuracy — то же из features.json
  drift / drift_ids  — задачи, где md и json расходятся (existence/status/priority) — КЛЮЧЕВАЯ
  consistent         — drift == 0
  title_accuracy_md  — вторичная, normalized title-match из md
  *_errors           — список конкретных расхождений с GT (для разбора)
"""
import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def norm_title(t: str) -> str:
    return re.sub(r"\s+", " ", t.strip().lower())


def parse_md(text: str):
    tasks = {}
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4:
            continue
        cid = cells[0]
        if cid.upper() == "ID" or set(cells[0]) <= {"-", ":", " "}:
            continue
        if not re.match(r"^PV-\d+[a-z]?$", cid):
            continue
        tasks[cid] = {
            "status": cells[1].lower(),
            "priority": cells[2].upper(),
            "title": cells[3],
        }
    return tasks


def parse_json(text: str):
    tasks = {}
    try:
        data = json.loads(text)
    except Exception:
        return tasks
    for t in data.get("tasks", []):
        if "id" not in t:
            continue
        tasks[t["id"]] = {
            "status": str(t.get("status", "")).lower(),
            "priority": str(t.get("priority", "")).upper(),
            "title": str(t.get("title", "")),
        }
    return tasks


def core_accuracy(parsed, gt):
    """existence+status+priority по всем GT-задачам. 3 поля на задачу."""
    total = 0
    ok = 0
    errors = []
    for cid, g in gt.items():
        # existence
        total += 1
        if cid in parsed:
            ok += 1
        else:
            errors.append(f"{cid}: отсутствует")
            total += 2  # status+priority тоже считаются провалом
            continue
        p = parsed[cid]
        total += 1
        if p["status"] == g["status"].lower():
            ok += 1
        else:
            errors.append(f"{cid}: status {p['status']!r} != {g['status']!r}")
        total += 1
        if p["priority"] == g["priority"].upper():
            ok += 1
        else:
            errors.append(f"{cid}: priority {p['priority']!r} != {g['priority']!r}")
    # лишние задачи (есть в parsed, нет в GT)
    for cid in parsed:
        if cid not in gt:
            errors.append(f"{cid}: лишняя (нет в ground-truth)")
            total += 1
    return ok, total, errors


def compute_drift(md, js):
    ids = set(md) | set(js)
    drift_ids = []
    for cid in sorted(ids):
        if cid not in md or cid not in js:
            drift_ids.append(cid)
            continue
        if (
            md[cid]["status"] != js[cid]["status"]
            or md[cid]["priority"] != js[cid]["priority"]
        ):
            drift_ids.append(cid)
    return drift_ids


def title_accuracy(parsed, gt):
    ok = 0
    for cid, g in gt.items():
        if cid in parsed and norm_title(parsed[cid]["title"]) == norm_title(g["title"]):
            ok += 1
    return round(ok / len(gt), 3)


def main():
    run_dir = Path(sys.argv[1])
    gt_raw = json.loads((SCRIPT_DIR / "ground-truth.json").read_text(encoding="utf-8"))
    gt = {t["id"]: t for t in gt_raw["tasks"]}

    md = parse_md((run_dir / "backlog.md").read_text(encoding="utf-8"))
    js_path = run_dir / "features.json"
    js = parse_json(js_path.read_text(encoding="utf-8")) if js_path.exists() else {}

    md_ok, md_total, md_err = core_accuracy(md, gt)
    js_ok, js_total, js_err = core_accuracy(js, gt)
    drift_ids = compute_drift(md, js)

    out = {
        "run": run_dir.name,
        "md_core_accuracy": round(md_ok / md_total, 3),
        "json_core_accuracy": round(js_ok / js_total, 3),
        "drift": len(drift_ids),
        "drift_ids": drift_ids,
        "consistent": len(drift_ids) == 0,
        "title_accuracy_md": title_accuracy(md, gt),
        "md_errors": md_err,
        "json_errors": js_err,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
