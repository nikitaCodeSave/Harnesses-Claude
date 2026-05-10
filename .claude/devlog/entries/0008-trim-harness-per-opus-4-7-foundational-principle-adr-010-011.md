---
id: 8
date: 2026-05-10
title: "Trim harness per Opus 4.7 foundational principle (ADR-010, 011, 012)"
tags: [adr, refactor, harness]
status: complete
---

# Trim harness per Opus 4.7 foundational principle (ADR-010, 011, 012)

## Контекст

Аудит всего harness'а под цитаты Anthropic про Opus 4.7 best practices
(«spawns fewer subagents by default», «calls tools less often and reasons
more», «response length is calibrated to task complexity») выявил 6 hooks/
skills + 1 agent + 57 строк CLAUDE.md, которые кодируют assumptions, уже
снятые моделью или внешними механизмами. Foundational principle
(`docs/HARNESS-DECISIONS.md` ADR-007/009) применён системно.

## Изменения

**ADR-010**: удалено 5 observability/anti-pattern hooks + 1 дубликат skill.
**ADR-011**: удалён `code-reviewer` agent как дубликат built-in `/review`.
**ADR-012**: trim CLAUDE.md 127 → ~80 строк (decision tree, flow table → ADR refs).

`session-context.sh` упрощён до devlog-only (58 → 22 строки): git context
уже инжектится системным prompt'ом Claude Code блоком `gitStatus`.

## Затронутые файлы

- `docs/HARNESS-DECISIONS.md` — добавлены ADR-010, ADR-011, ADR-012
- `.claude/CLAUDE.md` — trim 127 → ~80 строк
- `.claude/settings.json` — удалены 4 hook event entries (`Agent` matcher из PreToolUse, `ConfigChange`, `CwdChanged`, `PermissionDenied`, `StopFailure`)
- `.claude/hooks/session-context.sh` — упрощён до devlog-only (58 → 22 строки)
- `.claude/hooks/block-shallow-agent-spawn.sh` — DELETED (Opus 4.7 spawns fewer subagents nativel)
- `.claude/hooks/stop-recovery.sh` — DELETED (засорял корневой MEMORY.md)
- `.claude/hooks/env-reload.sh` — DELETED (только логировал, ничего не делал)
- `.claude/hooks/denied-log.sh` — DELETED (низкий ROI)
- `.claude/hooks/config-audit.sh` — DELETED (git log уже это даёт)
- `.claude/skills/plan-deliverable/` — DELETED (дубликат deliverable-planner agent'а)
- `.claude/agents/code-reviewer.md` — DELETED (дубликат built-in /review)

## Проверка

```bash
ls .claude/hooks/             # 4 файла (was 9)
ls .claude/agents/            # 2 файла (was 3)
ls .claude/skills/            # 1 директория (was 2)
wc -l .claude/CLAUDE.md       # ~80 (was 127)
jq '.hooks | keys | length' .claude/settings.json  # 3 события (was 7)
```

## Related

- #5 — ADR-007 (retire 6 skills + 2 agents) — ровно тот же критерий применён к skills/agents
- #6 — ADR-008 (sandbox baseline + SessionStart hook + effort guidance) — partially superseded
- #7 — ADR-009 (retire sandbox baseline) — то же foundational principle применено к sandbox
