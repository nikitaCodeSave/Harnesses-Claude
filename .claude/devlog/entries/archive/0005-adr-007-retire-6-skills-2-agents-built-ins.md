---
id: 5
date: 2026-05-09
title: "ADR-007 retire 6 skills + 2 agents как дубликаты built-ins"
tags: [refactor, harness, adr, cleanup]
status: complete
---

# ADR-007 retire 6 skills + 2 agents как дубликаты built-ins

## Контекст

Stage 2 battle-test на FastApi-Base + критический ревью пользователя выявили **системное нарушение foundational principle** в v0.1 expansion коммите (76c4f37). Создавая 7 user-triggered skills и 5 custom agents, я не верифицировал built-in/bundled каталог Claude Code 2.1.x. Поверхностный bug, который я фиксил в ADR-006 (mandatory interview из-за `AskUserQuestion` несовместимости с `context: fork`), был лишь верхушкой: половина harness skills вообще не должна была существовать.

Двойная ошибка процесса:
1. **Архитектурная**: `AskUserQuestion` + `context: fork` несовместимы (forked subagents работают в background mode, AskUserQuestion в них недоступен). Поправил мысленно, начал переписывать skills под main-thread workflow.
2. **Foundational principle**: built-in `/init`, `/team-onboarding`, `/memory`, `/review`, `/security-review`, `/debug` (bundled), `/simplify` (bundled), `/plan` уже покрывают сценарии, ради которых я создавал свои skills. Каждый мой skill — assumption «built-ins не справятся», которая не подтверждается. ADR-006 решал не ту проблему — настоящая проблема в том, что `/onboard` не должен существовать.

`/team-onboarding` — built-in v2.1.101+ (April 2026), generates teammate ramp-up guide from local Claude Code usage. Я его не помнил при v0.1 expansion. `/init` помнил, но игнорировал.

## Изменения

### Удалены skills (6)

| Skill | Заменён на |
|---|---|
| `skills/onboard/` | built-in `/init` (NEW project) + `/team-onboarding` (ramp-up) + `/memory` (refine) |
| `skills/review/` | built-in `/review` (in-session) + shell `claude ultrareview` (cloud) |
| `skills/debug-loop/` | bundled `/debug` |
| `skills/refactor/` | прямой `/plan` или Shift+Tab×2 (тонкий wrapper удалён) |
| `skills/create-skill/` | marketplace `skill-creator@anthropics-skills` (через `claude plugin install`) |
| `skills/spawn-agent/` | manual edit `.claude/agents/<name>.md` + built-in `/agents` view; либо `meta-creator` через Task tool |

### Удалены agents (2)

| Agent | Причина |
|---|---|
| `agents/onboarding-agent.md` | paired с удалённым `/onboard`, ADR-006 superseded |
| `agents/debug-loop.md` | paired с удалённым `/debug-loop`, дубликат bundled `/debug` |

### Сохранены skills (2)

- `devlog` — уникальная schema (entries/NNNN-slug.md + auto-index), не покрыто built-ins.
- `plan-deliverable` — deliverable-driven contract без декомпозиции (ADR-002 подход), не покрыто built-ins. Переведён на main-thread workflow без `context: fork` (см. ADR-007 anti-pattern).

### Сохранены agents (3)

- `deliverable-planner` — paired с `plan-deliverable` skill.
- `code-reviewer` — marginally сохранён: даёт structured JSON output, отличающийся от built-in `/review` UX. Может быть удалён в v0.3 если battle-test покажет что built-in `/review` достаточен.
- `meta-creator` — extending harness (создание agents/hooks). Вызывается через Task tool напрямую из main thread, без обёрток-skill.

### ADR-007 в `docs/HARNESS-DECISIONS.md`

Формализует cleanup + правило: «перед добавлением любого нового skill/agent — обязательная проверка built-in/bundled каталога через https://code.claude.com/docs/en/commands». ADR-006 помечен как superseded.

### Обновлены документы

- `.claude/CLAUDE.md` — добавлена таблица «Built-in onboarding & quality flow» (mapping сценариев на built-ins). Удалены ссылки на отозванные skills.
- `docs/STAGE-2-BATTLE-TEST.md` — workflow battle-test'а переписан под built-ins (`/init`, `/team-onboarding`, `/memory`, `/review`, `/debug`, `/simplify`).
- `.claude/CLAUDE.md` Reference materials — обновлён счётчик (3 custom subagents вместо 5).

### Cleanup в пилотах

В `/home/nikita/PROJECTS/FastApi-Base/.claude/` и `/home/nikita/PROJECTS/AI_analyst_migration_battletest/.claude/` удалены те же 6 skills + 2 agents. Мета-CLAUDE.md передеплоен. Inventory в обоих пилотах: 2 skills + 3 agents, диффы с harness'ом clean.

## Затронутые файлы

- DELETED: `.claude/skills/{onboard,review,debug-loop,refactor,create-skill,spawn-agent}/SKILL.md`
- DELETED: `.claude/agents/{onboarding-agent,debug-loop}.md`
- MODIFIED: `.claude/skills/plan-deliverable/SKILL.md` (без `context: fork`, main-thread workflow)
- MODIFIED: `.claude/CLAUDE.md` (Built-in flow table, обновлённые Reference materials)
- MODIFIED: `docs/HARNESS-DECISIONS.md` (добавлен ADR-007, ADR-006 помечен superseded)
- MODIFIED: `docs/STAGE-2-BATTLE-TEST.md` (workflow через built-ins)
- DELETED in pilots: те же 6 skills + 2 agents
- MODIFIED in pilots: `.claude/CLAUDE.md` (redeploy)

## Проверка

```bash
# harness inventory минимизирован:
ls -d .claude/skills/*/        # 2: devlog, plan-deliverable
ls .claude/agents/*.md         # 3: deliverable-planner, code-reviewer, meta-creator

# pilots зеркалят harness:
diff -q .claude/CLAUDE.md /home/nikita/PROJECTS/FastApi-Base/.claude/CLAUDE.md
diff -q .claude/CLAUDE.md /home/nikita/PROJECTS/AI_analyst_migration_battletest/.claude/CLAUDE.md

# ADR-007 на месте:
grep -A2 'ADR-007' docs/HARNESS-DECISIONS.md | head -5

# ADR-006 superseded:
grep 'SUPERSEDED' docs/HARNESS-DECISIONS.md
```

## Урок процесса

1. **WebFetch built-in catalog ДО реализации любого skill**. Foundational principle проверяется в моменте предложения, не в обзоре.
2. **AskUserQuestion + context: fork** — несовместимы (forked subagents работают в background mode). Если skill требует interaction с пользователем — main thread, без `context: fork`.
3. **«Я создал N полезных компонентов» ≠ harness стал лучше**. Harness стал лучше когда количество компонентов сократилось до минимально-необходимого (2 skills, 3 agents) с durable обоснованием каждого.

## Что НЕ сделано

- Не удалён `code-reviewer` agent — оставлен marginally на оценку battle-test. Если built-in `/review` достаточен для пилотов — кандидат на удаление в v0.3.
- В пилоте FastApi-Base остался ранее созданный `CLAUDE.md` (от старого `/onboard`). Пользователь решает — оставить или удалить. На следующем bootstrap'е использовать built-in `/init` (для NEW сценария) или `/memory` (для refine).

## Related

- #2 — v0.1 expansion (создал большинство удалённых здесь компонентов).
- #3 — permission whitelist (правка инфраструктуры, не затронута).
- #4 — ADR-006 (superseded этим ADR-007).
- ADR-007 в `docs/HARNESS-DECISIONS.md`.
