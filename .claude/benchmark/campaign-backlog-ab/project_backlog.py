#!/usr/bin/env python3
"""One-way проекция: backlog.md (канон) -> features.json (зеркало).

Рукав B запускает это из рабочей директории прогона после правки backlog.md.
Читает ./backlog.md, переписывает ./features.json. Детерминированно.
"""
import json
import re
import sys
from pathlib import Path


def parse_backlog_md(text: str):
    tasks = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4:
            continue
        cid = cells[0]
        # пропустить шапку и разделитель
        if cid.upper() == "ID" or set(cells[0]) <= {"-", ":", " "}:
            continue
        if not re.match(r"^PV-\d+[a-z]?$", cid):
            continue
        tasks.append(
            {"id": cid, "status": cells[1], "priority": cells[2], "title": cells[3]}
        )
    return tasks


def main():
    d = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    md = (d / "backlog.md").read_text(encoding="utf-8")
    tasks = parse_backlog_md(md)
    (d / "features.json").write_text(
        json.dumps({"tasks": tasks}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"projected {len(tasks)} tasks -> features.json")


if __name__ == "__main__":
    main()
