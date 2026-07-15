# A/B: single-canon backlog vs dual-canon (md↔json зеркала)

owner: nikitaCodeSave
last-updated: 2026-06-23
status: experiment (pilot)

Эмпирический A/B одного решения из campaign-workflow research (memory `reference-campaign-workflow-research`):
**беклог должен иметь РОВНО ОДИН редактируемый носитель, генерируемый one-way; зеркала рассинхронизируются.**

## Гипотеза

H1: рукав B (один редактируемый канон + генерируемая проекция) даёт **drift ≈ 0** и **status/priority accuracy выше**, чем рукав A (два редактируемых канона), при равном или меньшем cost.

H0: разницы нет (под Opus 4.8 модель синхронизирует два канона надёжно сама → решение (a) — overkill).

## Рукава

| Рукав | Канон | Зеркало | Протокол |
|---|---|---|---|
| **A** (baseline / статус-кво dialog_analyzer) | `backlog.md` (правится) | `features.json` (тоже правится вручную) | `protocols/A.md` |
| **B** (treatment) | `backlog.md` (единственный редактируемый) | `features.json` = `python3 project_backlog.py` (one-way) | `protocols/B.md` |

Изолированная переменная: dual-editable → single-editable. Канон в обоих рукавах = markdown (как в dialog_analyzer), чтобы НЕ смешивать с вопросом «какой файл канон».

## Workload

`sessions.json` — 7 fresh-context «сессий», каждая применяет sync-prone backlog-операции
(status-flip, add, reprioritize, split→subtasks, supersede, defer, block, rename/rescope).
Каждая сессия видит только текущие файлы + свою инструкцию + протокол рукава (не видит ground-truth).

## Oracle (детерминированный)

`ground-truth.json` — финальное состояние после всех 7 сессий (рассчитано вручную из seed + sessions).
`score.py <run_dir>` парсит `backlog.md` + `features.json`, печатает JSON:
- `md_core_accuracy` / `json_core_accuracy` — доля верных (existence+status+priority) по всем ground-truth задачам
- `drift_ids` / `drift` — задачи, где md и json расходятся (existence/status/priority) — **ключевая метрика**
- `consistent` — drift == 0
- `title_accuracy` (вторичная, normalized)

## Как прогнать

```bash
# 1. pre-seed run-dirs (по числу рукавов × прогонов)
bash .claude/benchmark/campaign-backlog-ab/seed-runs.sh <N>
# 2. workflow проигрывает сессии (см. progress-журнал / inline script)
# 3. score
for d in .claude/benchmark/campaign-backlog-ab/runs/*/; do
  echo "$d"; python3 .claude/benchmark/campaign-backlog-ab/score.py "$d"
done
```

Stat-протокол: Layer D (`.claude/docs/benchmark.md`) — N≥3, bracket [min,med,max], sign-inversion gate.
