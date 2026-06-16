---
id: 77
date: 2026-06-09
title: "Add long-running build kit to claude-code-harness Bootstrap"
tags: [feature, harness]
status: complete
---

# Add long-running build kit to claude-code-harness Bootstrap

## Контекст
Анонс Fable 5 (Mythos-class, tier над Opus) заострил, что ценность способной модели максимальна на «longer and more complex tasks» — а значит критерий успеха bootstrap'а глобального skill'а `claude-code-harness` это «проект выдержит длинную автономную разработку», а не «есть CLAUDE.md + settings.json». Аудит показал: Bootstrap был tuned под short-task (Phase 5 = «MVH most projects need forever»), а все long-horizon рычаги (oracle-loop, progress-file, feature-spec, fresh-context Evaluator) свалены в «optional next steps» и откладывались скопом, хотя их дешёвые формы (конвенции+файлы) — почти бесплатны по контексту.

Владелец задал руль: целевое качество + first-party Anthropic важнее внутренней истории репо. Поэтому правка grounded строго в двух T1-постах Anthropic, а не во внутренних ADR.

## Изменения
- **Bootstrap теперь ветвится:** MVH по умолчанию (libraries/scripts/short tasks) + **opt-in Phase 5 «Long-running build kit»** для sustained multi-session build. Kit (всё из first-party): runnable oracle/`init.sh` + e2e на старте сессии; feature-spec ledger (`passes:false`, «unacceptable to remove/edit tests»); progress/handoff-файл + commit-per-feature; session-start ritual; fresh-context Evaluator + live-app testing; session-0 green baseline. Реализовано как **conventions+файлы, не машинерия** (ноль hooks/subagents/pipelines).
- `## Working style` шаблона CLAUDE.md: добавлена строка spec-up-front → decompose into verifiable slices → high/xhigh effort для long-horizon/async.
- Phase Verify: добавлен прогон оракула («оракул real, не aspirational»).
- **F4 re-ground:** стампы Opus 4.8 / CC v2.1.169 → **v2.1.170** в 4 файлах; Fable 5 зафиксирован как canonical re-grounding checkpoint (native-capabilities «Changed in 2.1.170» + evidence-base re-grounding-заметка с T1-цитатой на анонс и progressive-simplification). Behavioral-инварианты остались model-agnostic. Историю change-log'ов (provenance) не трогал.

Валидация (Вариант A, по §5 самого skill'а — эмпирически, не аргументом): слепой worktree A/B — 2 bootstrap-агента (OLD checklist vs NEW) на **идентичном** seed-проекте «TaskTrackr», одна модель Opus 4.8 (тестировался skill, не модель). Fresh-context критик (judge≠author) оценил обе harness'ы по **Anthropic-sourced рубрике** из тех же двух постов → **WINNER: NEW decisively, без регресса минимализма** (каждый добавленный артефакт load-bearing, CLAUDE.md остался ≤200/indexer, ноль анти-паттернов). Две дешёвые правки из замечаний критика (C5 evaluator pointer + session-0 baseline) внесены до установки.

## Затронутые файлы
- `~/.claude/skills/claude-code-harness/references/bootstrap-checklist.md` — Phase 5 kit + working-style + Verify-оракул (145→201 строк)
- `~/.claude/skills/claude-code-harness/SKILL.md` — Mode 1 Bootstrap упоминает long-running-ветку
- `~/.claude/skills/claude-code-harness/references/native-capabilities.md` — стамп 2.1.170 + «Changed in 2.1.170» (Fable)
- `~/.claude/skills/claude-code-harness/references/evidence-base.md` — стамп 2.1.170 + Fable re-grounding-bullet (T1)
- `~/.claude/skills/claude-code-harness/references/{harness-discipline,audit-checklist}.md` — стамп 2.1.170
- Backup pre-edit версий: `.scratch/ab/skill-backup/`; A/B-артефакты: `.scratch/ab/`

## Проверка
- Структура skill'а после правок: фазы 0–7 упорядочены, стампы 2.1.170 в 4 файлах, Phase 5 anchors (`init.sh`/`passes:false`/`claude-progress`) присутствуют, markdown не сломан.
- A/B: fresh-context критик — verdict WINNER NEW, no minimalism regression (held-out Anthropic-рубрика, 7 критериев).

## Related
- #76 — sync canonical claude-code-harness (предыдущее состояние skill'а)
- #74, #75 — retire/prune project-docs-bootstrap (фон: bootstrap-доки нативны под Opus 4.8)
