---
name: onboard
description: First-session bootstrap for a project. Detects mode (new vs mature), interviews developer for stack/acceptance criteria, produces a project-level CLAUDE.md in repo root. Use only on first contact with a repo or when an existing CLAUDE.md is empty/trivial.
disable-model-invocation: true
context: fork
agent: onboarding-agent
---

Запусти onboarding для текущего репозитория. Аргументы пользователя (если есть): $ARGUMENTS.

Phase 1 — detect mode:
- Empty / minimal scaffold → NEW project
- Has code, tests, docs → MATURE project

Phase 2 — выполни workflow согласно агенту onboarding-agent:
- NEW: интервью через AskUserQuestion (стек, target deployment, acceptance criteria первого deliverable, verification mechanism), создать `./CLAUDE.md` в корне репо (короткий, императивный).
- MATURE: запустить built-in `Explore` для архитектурной карты, дополнить существующий CLAUDE.md (не переписывать).

Не трогай `.claude/CLAUDE.md` — это мета-уровень, отдельный артефакт.
