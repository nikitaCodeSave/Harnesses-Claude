#!/usr/bin/env python3
"""Rebuild .claude/devlog/index.json from entries/**/*.md frontmatter.

Source of truth: markdown files in entries/. This script never writes to entries.
Run after adding a new entry, or as a pre-commit hook.

Usage: python3 .claude/devlog/rebuild-index.py
Exit: 0 ok / 1 schema/duplicate-id error.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

DEVLOG_ROOT = Path(__file__).parent
ENTRIES_DIR = DEVLOG_ROOT / "entries"
INDEX_PATH = DEVLOG_ROOT / "index.json"

REQUIRED_FIELDS = ("id", "date", "title")
OPTIONAL_FIELDS = ("tags", "status", "supersedes")


def parse_frontmatter(text: str) -> dict | None:
    """Minimal YAML-frontmatter parser. Supports str, int, and inline list [a, b]."""
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        return None
    out: dict = {}
    for line in m.group(1).splitlines():
        line = line.rstrip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if val.startswith("[") and val.endswith("]"):
            out[key] = [x.strip().strip('"\'') for x in val[1:-1].split(",") if x.strip()]
        elif val.isdigit():
            out[key] = int(val)
        else:
            out[key] = val.strip('"\'')
    return out


def slugify(s: str, max_len: int = 60) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s[:max_len].rstrip("-")


def collect_entries() -> tuple[list[dict], list[str]]:
    entries: list[dict] = []
    errors: list[str] = []
    if not ENTRIES_DIR.exists():
        return entries, [f"missing dir: {ENTRIES_DIR}"]

    for md_path in sorted(ENTRIES_DIR.rglob("*.md")):
        rel = md_path.relative_to(DEVLOG_ROOT)
        try:
            text = md_path.read_text(encoding="utf-8")
        except OSError as e:
            errors.append(f"{rel}: read failed ({e})")
            continue
        fm = parse_frontmatter(text)
        if fm is None:
            errors.append(f"{rel}: missing or malformed frontmatter")
            continue
        for field in REQUIRED_FIELDS:
            if field not in fm:
                errors.append(f"{rel}: required field '{field}' missing")
                break
        else:
            expected_slug = slugify(str(fm["title"]))
            stem = md_path.stem
            # filename pattern: NNNN-slug
            m = re.match(r"^(\d{1,6})-(.+)$", stem)
            if not m:
                errors.append(f"{rel}: filename must match NNNN-slug pattern")
                continue
            file_id = int(m.group(1))
            file_slug = m.group(2)
            if fm["id"] != file_id:
                errors.append(f"{rel}: frontmatter id {fm['id']} != filename id {file_id}")
                continue
            if file_slug != expected_slug:
                errors.append(f"{rel}: filename slug '{file_slug}' != slugify(title)='{expected_slug}'")
                continue
            entries.append({
                "id": file_id,
                "date": fm["date"],
                "title": fm["title"],
                "tags": fm.get("tags", []),
                "status": fm.get("status", "complete"),
                "supersedes": fm.get("supersedes"),
                "path": str(rel).replace("\\", "/"),
            })

    seen: dict[int, str] = {}
    for e in entries:
        if e["id"] in seen:
            errors.append(f"duplicate id {e['id']}: {seen[e['id']]} vs {e['path']}")
        else:
            seen[e["id"]] = e["path"]

    entries.sort(key=lambda e: e["id"])
    return entries, errors


def main() -> int:
    entries, errors = collect_entries()
    if errors:
        print("ERRORS:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    index = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "entry_count": len(entries),
        "entries": entries,
    }
    INDEX_PATH.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"index.json updated: {len(entries)} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
