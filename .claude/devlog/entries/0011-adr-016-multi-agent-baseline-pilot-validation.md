---
id: 11
date: 2026-05-10
title: "ADR-016: multi-agent baseline + pilot validation"
tags: [adr, harness]
status: complete
---

# ADR-016: multi-agent baseline + pilot validation

## Контекст

Сессия 2026-05-10 расширяла harness дисциплиной multi-agent под Opus 4.7. По ходу работы возникли два диалоговых поворота, изменивших scope:
1. Запрос пользователя «information should be in active access у claude through skills + reference files, не через раздутый CLAUDE.md» — скомпилирован полный baseline + создан skill `meta-orchestrator` для active progressive disclosure.
2. Пользователь explicitly указал, что **main thread = meta-orchestrator** (это я, кто общается с пользователем) — skill, описывающий main thread сам для себя, дублирует meta-CLAUDE.md, это anti-pattern.

Параллельно проведён pilot test на `~/PROJECTS/FastApi-Base` (frozen Stage 2 baseline после v0.1 expansion) с migration к актуальному harness state. Pilot test выявил existing harness bug в `session-context.sh` (`set -euo pipefail` + `ls /empty-glob/[0-9]*.md` = exit 2), не показывавшийся в harness self-tests где devlog непустой.

## Изменения

**Новые артефакты**:
- `docs/MULTI-AGENT-BASELINE.md` — full reference (12 разделов, evidence-based: Anthropic empirical 90.2% / 4×/15× tokens / 80% variance объясняется token usage; «multi-agent ill-suited для most coding»). On-demand, не self-loaded.
- ADR-016 в `docs/HARNESS-DECISIONS.md` — фиксирует self-описывающие skills как anti-pattern + pilot validation pattern.

**Изменения meta-CLAUDE.md**:
- Foundational principle расширен higher-order orchestration refinement: skill / agent / hook как environment configurator для inner executors — допустимы; как duplicate-of-built-in или self-description main thread'а — anti-pattern.
- `Sub-agent spawn policy` — main thread = meta-orchestrator declared explicit; ill-suited-for-most-coding (Anthropic) добавлен; ссылка на baseline для on-demand.
- `Self-evolution` skills counter актуализирован (1) + явная anti-pattern строка про self-описывающие skills.
- `Reference materials` — добавлен `docs/MULTI-AGENT-BASELINE.md`.

**Bugfix**:
- `.claude/hooks/session-context.sh` line 14: добавлен `|| true` после `ls ... | sort | tail -1` для безопасности под `set -euo pipefail` на empty-glob.

**Retired в этой же сессии**:
- `.claude/skills/meta-orchestrator/SKILL.md` (создан и удалён в сессии — self-описывающий, дубликат meta-CLAUDE.md).

**PRACTICES-FROM-PROJECTS.md**:
- §10.11.2 закрыт ссылкой на §12.4 (paths-scoped rules — нативно поддерживается в Claude Code 2.0.64+).
- §12 brainstorm — 8 подсекций с источниками (Anthropic official, curated lists, reference impls, paths-scoped разборы, конкурентный контекст, tooling, концептуальные эссе, multi-agent).
- §13 N-counter — таблица 4 ADR-кандидатов с N=0, symmetric rule machinery для будущих ADR'ов.

**Pilot validation**:
- FastApi-Base `.claude/` приведён к harness baseline: 4 hooks / 1 skill (devlog) / 2 agents (deliverable-planner, meta-creator), settings.json hooks events 7 → 3, removed: 5 hooks (block-shallow-agent-spawn, stop-recovery, env-reload, denied-log, config-audit), 1 skill (plan-deliverable), 1 agent (code-reviewer).
- Backup pre-migration: `/tmp/FastApi-Base.claude.bak.20260510-121448`.
- Runtime tests: `claude agents` показал 6 active (2 project + 4 built-in); `claude --print` discovered `devlog` skill correctly; hook bugfix smoke 3/3 pass.

## Затронутые файлы

- `.claude/CLAUDE.md` — Foundational principle higher-order refinement, Sub-agent spawn policy rewrite, Self-evolution counter + anti-pattern строка, Reference materials дополнен.
- `.claude/hooks/session-context.sh` — bugfix `|| true` на line 14.
- `docs/HARNESS-DECISIONS.md` — ADR-016 (новый), Active inventory's Out-of-scope обновлён.
- `docs/MULTI-AGENT-BASELINE.md` — новый файл, ~230 строк.
- `docs/PRACTICES-FROM-PROJECTS.md` — §10.11.2 закрытие, §12 brainstorm (новый), §13 N-counter (новый), §12.8 cross-link на baseline.

## Проверка

- **Static**: `bash -n` для всех hooks → 4/4 OK; `python3 .claude/devlog/rebuild-index.py` → success.
- **Hook bugfix**: 3/3 регресс-cases (harness with entries → JSON output, pilot empty → silent exit 0, pilot 1 entry → JSON output).
- **Pilot runtime**:
  - `claude agents` → 2 project + 4 built-in, `code-reviewer` correctly absent.
  - `claude --print "Перечисли только имена доступных тебе skills и agents..."` → `devlog` listed, `meta-orchestrator` correctly absent после rollback'а.
  - Migration inventory aligned harness ↔ pilot.
- **User observation**: каноничный test — пользователь explicitly выявил self-description duplication между skill и CLAUDE.md.

## Related

- #10 — ADR-15 retire ADR-005 implementation (warm-context anti-pattern, predecessor по теме «не дублировать существующие primitives»).
- ADR-016 в `docs/HARNESS-DECISIONS.md` — формальное решение, эта запись фиксирует session changes.
- ADR-007 (built-ins-first) — расширен новой категорией anti-pattern boundary (self-description).
- ADR-010 (anti-spam observability hooks) — concept'но связан, тот же foundational principle direct применён.
