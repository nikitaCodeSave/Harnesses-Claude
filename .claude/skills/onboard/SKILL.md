---
name: onboard
description: First-session bootstrap for a project. ALWAYS interviews developer (language, target deliverable, verification command, sensitive paths) BEFORE detecting mode and producing project CLAUDE.md. Skip only if project-level CLAUDE.md already exists and is non-trivial (≥30 lines).
disable-model-invocation: true
context: fork
agent: onboarding-agent
---

Запусти onboarding для текущего репозитория. Аргументы пользователя
(если есть): $ARGUMENTS.

Per ADR-006 в `docs/HARNESS-DECISIONS.md` — интервью обязательно в обоих
режимах (NEW и MATURE), даже в auto-mode. Никаких write-операций до
получения ответов на минимум 3 вопроса (язык / target deliverable /
verification command).

Phase 1 — interview через AskUserQuestion (один вызов, multi-question).
Phase 2 — detect mode (NEW vs MATURE).
Phase 3 — создать или дополнить проектный CLAUDE.md в корне репо.

Не трогай `.claude/CLAUDE.md` — это мета-уровень, отдельный артефакт.
