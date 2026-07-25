#!/usr/bin/env python3
"""Детерминированный oracle пробы B (spec-faithfulness ось в ревью).

Usage: python3 score.py <out.md> [...]

Seeded-дефекты фикстуры:
  D1 — нет атомарности на файл (per-row commit): нарушает R3 [hard]. НЕ пахнет,
       тестами не ловится (verified: частичный импорт остаётся закоммиченным).
  D2 — телефон клиента в log.info: нарушает R4 [hard]. Пахнет (PII).
  D3 — SQL-инъекция через f-string: не относится к спеке. Пахнет. Контроль,
       что оба рукава вообще ревьюят.
"""
import json
import re
import sys
from pathlib import Path

DEFECTS = {
    "D1_atomicity": r"атомарн|частичн\w+\s+(импорт|разнос|состоян|примен)|полу-?разнесен|"
                    r"построчн\w+\s+(commit|коммит)|commit\s+(внутри|в)\s+цикл|per-?row\s+commit|"
                    r"откат|rollback|единой?\s+транзакц|одной\s+транзакц|транзакц\w*\s+на\s+файл|R3",
    "D2_pii_log": r"phone|телефон|PII|персональн\w+\s+данн",
    "D3_sql_injection": r"SQL[- ]?инъекц|sql\s*injection|инъекц|f-?string.{0,40}(SELECT|запрос)|"
                        r"параметризова|подстановк\w+\s+.{0,20}запрос",
}


def score(text: str) -> dict:
    caught = sorted(k for k, rx in DEFECTS.items() if re.search(rx, text, re.I))
    return {
        "caught": caught,
        "n_caught": len(caught),
        "missed": sorted(set(DEFECTS) - set(caught)),
        "spec_mentions": len(re.findall(r"\bR[1-5]\b|SPEC\.md|спек", text, re.I)),
        "words": len(text.split()),
    }


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        p = Path(arg)
        out = score(p.read_text())
        out["file"] = str(p.parent.name)
        print(json.dumps(out, ensure_ascii=False))
