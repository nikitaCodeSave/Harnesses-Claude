#!/usr/bin/env python3
"""Oracle пробы B2 — silent spec-defect (нарушение, не читаемое из кода).

Seeded: D4 — коррекция не оставляет аудит-следа (нет posting_audit, нет записи
«было/стало/когда»). Нарушает R2 [hard] и AC3. Из кода как дефект не читается:
код чистый, тесты (3/3) зелёные, атомарность/PII/SQL — в порядке.
"""
import json, re, sys
from pathlib import Path

AUDIT = r"аудит|audit[- ]?(trail|след)|posting_audit|аннулир\w*.{0,40}(истор|след|запис)|" \
        r"(истор|след|запис)\w*.{0,40}аннулир"
AC3 = r"\bAC3\b|критери\w*\s*3|\bR2\b"

if __name__ == "__main__":
    for arg in sys.argv[1:]:
        t = Path(arg).read_text()
        print(json.dumps({
            "run": Path(arg).parent.name,
            "D4_audit_caught": bool(re.search(AUDIT, t, re.I)),
            "refs_R2_AC3": bool(re.search(AC3, t, re.I)),
            "spec_mentions": len(re.findall(r"\bR[1-5]\b|SPEC\.md|спек", t, re.I)),
            "words": len(t.split()),
        }, ensure_ascii=False))
