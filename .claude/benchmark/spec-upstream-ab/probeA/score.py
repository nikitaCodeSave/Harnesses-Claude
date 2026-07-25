#!/usr/bin/env python3
"""Детерминированный oracle пробы A (spec-synthesis: «что/зачем» vs «как»).

Usage: python3 score.py <output.md> [...]  — печатает JSON-строку на файл.

Метрики:
  impl_leaks   — сколько имплементационных приманок из грилла утекло в спеку (НИЖЕ лучше)
  facts_kept   — сколько обязательных бизнес-фактов сохранено (guard: НЕ должно упасть)
  hard_soft    — есть ли hard/soft-маркировка ограничений (descriptive)
  words        — длина документа
"""
import json
import re
import sys
from pathlib import Path

# Приманки-реализации: оператор проговорил их вскользь в гриле.
# Попадание в спеку = зафиксировано «как» за исполнителя.
LEAKS = {
    "table_imported_rows": r"imported_rows",
    "col_file_hash": r"file_hash|хеш\w*\s+файла|хэш\w*\s+файла",
    "col_row_no": r"row_no|номер\w*\s+строк",
    "path_module": r"bank_import\.py|app/services",
    "lib_pandas": r"pandas",
    "unique_index": r"уникальн\w*\s+индекс|unique\s+index",
}

# Обязательные бизнес-факты (что/зачем). Guard-метрика.
FACTS = {
    "idempotency": r"идемпотент|повторн\w+\s+(выгрузк|импорт|загрузк|файл)|тот\s+же\s+файл|двойн\w+\s+списан|повторн\w+\s+списан",
    "correction": r"(коррекц|корректиров)",
    "annulment": r"аннулир|сторнир|отмен\w+\s+(прежн|стар|предыдущ)",
    "audit_trail": r"аудит|кто\W{0,10}когда|журнал\w*\s+(измен|операц)|след\w*\s+измен",
    "atomicity": r"атомарн|целиком\s+либо|всё\s+или\s+ничего|все\s+или\s+ничего|частичн\w+\s+импорт|частичн\w+\s+разнос",
    "pii_not_logged": r"(телефон|PII|персональн\w+\s+данн)",
    "non_goals": r"автозапуск|S3\W*(событ|триггер)|друг\w+\s+банк|API\s+биллинга",
    "open_decision": r"не\s+найден|без\s+найденн|ненайденн|не\s+обнаруж|найденн\w*\s+(счёт|счет)|(счёт|счет|счета)\w*\s+.{0,25}не\s+(найд|обнаруж)|отсутству\w+\s+(счёт|счет)|неизвестн\w+\s+(счёт|счет|клиент)",
}

HARD_SOFT = r"\[hard\]|\[soft\]|hard\b.{0,12}soft|must-have|nice-to-have"


def score(text: str) -> dict:
    low = text.lower()
    leaks = sorted(k for k, rx in LEAKS.items() if re.search(rx, low, re.I))
    facts = sorted(k for k, rx in FACTS.items() if re.search(rx, low, re.I))
    return {
        "impl_leaks": len(leaks),
        "leak_ids": leaks,
        "facts_kept": len(facts),
        "facts_missing": sorted(set(FACTS) - set(facts)),
        "hard_soft": bool(re.search(HARD_SOFT, low, re.I)),
        "words": len(text.split()),
    }


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        p = Path(arg)
        out = score(p.read_text())
        out["file"] = p.name
        print(json.dumps(out, ensure_ascii=False))
