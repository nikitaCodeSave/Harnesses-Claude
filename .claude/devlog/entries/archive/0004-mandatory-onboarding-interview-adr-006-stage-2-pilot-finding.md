---
id: 4
date: 2026-05-09
title: "Mandatory onboarding interview (ADR-006) после Stage 2 pilot finding"
tags: [bugfix, agents, harness, adr]
status: complete
---

# Mandatory onboarding interview (ADR-006) после Stage 2 pilot finding

## Контекст

Stage 2 battle-test на pilot'е FastApi-Base выявил harness-bug: `onboarding-agent` в auto-mode **пропустил interview phase** на mature-проекте. В выводе явно: «No interview was conducted — Auto-mode prefers action over questions». Pilot'ный CLAUDE.md создан с высоким качеством fingerprint'а и encoded invariants, но без подтверждённого языка (английский вместо желаемого русского), без подтверждённого target deliverable, без согласования verification gate с разработчиком.

Корневая причина — два места:
1. `.claude/agents/onboarding-agent.md` Phase 2 (MATURE) не описывал интервью (только NEW описывал).
2. Мета-`.claude/CLAUDE.md` guidance «trust the model, prefer action over questions» был унаследован и применён там, где он не должен — onboarding это единственное место, где questions ARE the action.

Доп-наблюдение про язык: pilot'ная сессия не наследует user-level `~/.claude/CLAUDE.md` language directive автоматически, если она зафиксирована в session-scope. Поэтому полагаться на «inheritance» нельзя — спросить надёжнее.

## Изменения

### ADR-006 — Onboarding всегда интервьюирует

Добавлен в `docs/HARNESS-DECISIONS.md`. Формализует:
- Onboarding-agent **обязан** проводить interview через `AskUserQuestion` в обоих режимах (NEW и MATURE), независимо от auto-mode.
- Минимум — 3 вопроса в одном вызове: язык, target deliverable, verification command. 4-й (опциональный) — sensitive paths/commands.
- Никакие write-операции в проектный CLAUDE.md не выполняются до получения ответов.
- Запрет на возврат: убирать `AskUserQuestion` из `onboarding-agent` или делать interview phase «опциональной по auto-mode» — запрещено.

### `.claude/agents/onboarding-agent.md` — переписан

Три обязательные фазы:
- **Phase 1 — Interview (MANDATORY)**: краткий repo scan для sensible defaults, потом ОДИН вызов AskUserQuestion с 3-4 вопросами.
- **Phase 2 — Detect mode**: NEW/MATURE по простым маркерам (≤10 файлов кода → NEW; есть code+tests+docs → MATURE).
- **Phase 3 — Write/extend CLAUDE.md**:
  - NEW: создать корневой CLAUDE.md ≤30 строк с stack/deliverable/verification/language directive + 3-5 invariants.
  - MATURE: если корневой CLAUDE.md ≥30 строк — append блок `## Onboarding notes <date>` с интервью-ответами; иначе создать с fingerprint + интервью + hard invariants.
  - Если репо >100 файлов — built-in `Explore` для архитектурной карты вместо прямой загрузки файлов.

Description в frontmatter теперь явно: «ALWAYS interviews developer ... BEFORE writing anything».

### `.claude/skills/onboard/SKILL.md` — обновлён

Description отражает новое требование. Body ссылается на ADR-006 и явно: «Никаких write-операций до получения ответов на минимум 3 вопроса».

### Redeploy в пилоты

Скопированы новые `onboarding-agent.md` и `onboard/SKILL.md` в:
- `/home/nikita/PROJECTS/FastApi-Base/.claude/`
- `/home/nikita/PROJECTS/AI_analyst_migration_battletest/.claude/`

Diff verify прошёл. Старый pilot'ный CLAUDE.md в FastApi-Base оставлен — на следующем `/onboard` агент проверит его длину и либо append'ит интервью-ответы (если ≥30 строк), либо переписать.

## Затронутые файлы

- `docs/HARNESS-DECISIONS.md` — добавлен ADR-006 (между ADR-005 и ADR-004 по структуре файла).
- `.claude/agents/onboarding-agent.md` — переписан целиком (3 фазы вместо 2).
- `.claude/skills/onboard/SKILL.md` — обновлён description + body со ссылкой на ADR-006.
- `/home/nikita/PROJECTS/FastApi-Base/.claude/agents/onboarding-agent.md` — redeploy.
- `/home/nikita/PROJECTS/FastApi-Base/.claude/skills/onboard/SKILL.md` — redeploy.
- `/home/nikita/PROJECTS/AI_analyst_migration_battletest/.claude/agents/onboarding-agent.md` — redeploy.
- `/home/nikita/PROJECTS/AI_analyst_migration_battletest/.claude/skills/onboard/SKILL.md` — redeploy.

## Проверка

```bash
# ADR-006 на месте:
grep -A1 'ADR-006' docs/HARNESS-DECISIONS.md | head -3

# onboarding-agent описание упоминает MANDATORY interview:
grep -i 'always interviews' .claude/agents/onboarding-agent.md

# Pilots receive identical files:
diff -q .claude/agents/onboarding-agent.md /home/nikita/PROJECTS/FastApi-Base/.claude/agents/onboarding-agent.md
diff -q .claude/skills/onboard/SKILL.md /home/nikita/PROJECTS/AI_analyst_migration_battletest/.claude/skills/onboard/SKILL.md
```

Полная валидация — re-run `/onboard` в pilot'е после удаления (или сохранения) сгенерированного CLAUDE.md.

## Что наблюдать на повторном запуске

В FastApi-Base:
- Если оставить существующий CLAUDE.md (он >30 строк, content-rich) — onboarding должен append блок «Onboarding notes 2026-05-09» с language=русский directive, уточнённым target deliverable, и подтверждённым verification gate (`pytest && ruff check && ruff format --check && mypy src`).
- Если удалить существующий — должен спросить и создать заново, language directive и invariants полностью per interview answers.

В AI_analyst_migration_battletest:
- Должен запустить `Explore` (репо большое), потом интервью, потом MATURE-flow.

## Что НЕ сделано

- Не удалён сгенерированный pilot CLAUDE.md в FastApi-Base — пусть пользователь решает (он содержательный, append-flow корректнее).
- Не добавлено наследование language directive из user-level `~/.claude/CLAUDE.md` через hook'и — это слишком хрупко, ADR-006 решает проблему явным интервью.

## Related

- #2 — v0.1 expansion (создал onboarding-agent в его старой форме).
- #3 — permission whitelist (предыдущая правка, разблокировала Stage 2 install).
- ADR-006 в `docs/HARNESS-DECISIONS.md` — формализует это решение.
