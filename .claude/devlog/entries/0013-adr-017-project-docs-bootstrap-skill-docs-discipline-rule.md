---
id: 13
date: 2026-05-10
title: "ADR-017: project-docs-bootstrap skill + docs-discipline rule"
tags: [adr, harness, docs]
status: complete
---

# ADR-017: project-docs-bootstrap skill + docs-discipline rule

## Контекст

Multi-turn discussion в этой сессии: пользователь попросил deeper synthesis на тему «как Meta orchestrator руководит командами разработчиков». Первый ответ (про harness hygiene) был отвергнут как «недостаточно информации»; второй (про project-level documentation contract: canonical layout, per-doc charter, update discipline, cold-start ritual, references на Anthropic + community) — принят. Затем пользователь попросил **перенести паттерн в harness как reusable component** и явно дал permission переписывать существующее ради качества.

Boundary check vs ADR-016 (self-описывающий skill anti-pattern): новый компонент НЕ описывает main thread сам себе (как retired meta-orchestrator skill); он конфигурирует окружение конкретного проекта (создаёт canonical `docs/`, лочит discipline через always-loaded rule). Это «environment configurator для inner executors» — где inner executors = Claude в будущих сессиях того же проекта + контрибьюторы команды.

Boundary check vs ADR-014 (single-incident → не invariant): pattern multi-source evidenced — Anthropic engineering blog, ADR community (Nygard 2011), DDD ubiquitous language (Evans), 6+ community curators в 12.x раздел. Не «один раз промазали».

## Изменения

**Новые файлы**:
1. `.claude/skills/project-docs-bootstrap/SKILL.md` — action-skill workflow (audit → scope → generate → lock-in → verify), 5 фаз, anti-patterns explicit.
2. `.claude/skills/project-docs-bootstrap/CONTRACT.md` — per-doc charter (7 doc типов) + skeletons + PR template + multi-stack guidance.
3. `.claude/rules/docs-discipline.md` — always-loaded invariant, 6 правил.

**Модифицированные**:
1. `docs/HARNESS-DECISIONS.md` — добавлен ADR-017 (~50 строк).
2. `.claude/CLAUDE.md` — Self-evolution + Reference materials (5 строк net).
3. `.claude/devlog/index.json` — регенерирован.

**Quality choices (deviation from default conservatism)**:
- Cut с 8 invariants до 6 в `docs-discipline.md`. Drop'нуты «cold-start test квартально» (ритуал, не invariant) и «CONVENTIONS as divergence» (self-evident из per-doc charter в CONTRACT.md).
- ADR-017 короче типичных ADR'ов в логе (`Эвидентс-точки` слиты в `Контекст`, `Урок процесса` не выделен). Source list — explicit references вместо vague «community evidence».
- Добавлена «Альтернатива (отвергнута, 2)» секция — обосновывает cut от 8 к 6 invariants.

**Inventory после**:
- `.claude/skills/`: `devlog`, `project-docs-bootstrap` (2 action-skills).
- `.claude/rules/`: `testing.md` (5 invariants), `docs-discipline.md` (6 invariants).

## Затронутые файлы

- `.claude/skills/project-docs-bootstrap/SKILL.md` — новый
- `.claude/skills/project-docs-bootstrap/CONTRACT.md` — новый
- `.claude/rules/docs-discipline.md` — новый
- `docs/HARNESS-DECISIONS.md` — добавлен ADR-017
- `.claude/CLAUDE.md` — обновлён Self-evolution + Reference materials
- `.claude/devlog/index.json` — регенерирован

## Проверка

```
$ ls .claude/skills/project-docs-bootstrap/
CONTRACT.md  SKILL.md

$ ls .claude/rules/
docs-discipline.md  testing.md

$ wc -l .claude/skills/project-docs-bootstrap/*.md .claude/rules/docs-discipline.md
   ... SKILL.md
   ... CONTRACT.md
   ... docs-discipline.md

$ python3 .claude/devlog/rebuild-index.py
index.json updated: 13 entries

$ claude --print  # available skills check (manual)
project-docs-bootstrap listed in skills inventory
```

## Что НЕ сделано (сознательно)

- НЕ автоматизированы PR template / Git hooks / CI checks для doc-with-code rule. Slippery slope в overgrown harness (ADR-007/010). Если empirical evidence покажет что rule систематически игнорируется без enforcement → отдельный ADR.
- НЕ создан отдельный slash command для bootstrap — skill сам invocable как `/project-docs-bootstrap`.
- НЕ перенесено `CONTRACT.md` в `docs/` harness'а — это документ, описывающий проектный layout, держится в скилле для self-containment.
- НЕ refactor'ed формат HARNESS-DECISIONS.md (~263 строки сейчас, было 384 до 0012). User open для рефакторинга, но это **отдельный** проход — открывать новым ADR-кандидатом, не смешивать с этой работой.

## Открытые вопросы для последующих ADR

1. **HARNESS-DECISIONS.md format itself**: каждый ADR ~50-100 строк с conventional sections (Контекст, Решение, Обоснование, Что НЕ делается, Альтернатива, Запрет на возврат, Эвидентс-точки, Урок процесса). Возможный refactor — tighter format (Decision / Why / Counter-evidence-required-to-revise) с per-ADR sized 20-40 строк. Trigger: следующий раз когда лог достигнет ≥350 строк или потребуется ещё один trim.
2. **Cross-project deployment**: harness живёт в `~/PROJECTS/Harnesses-Claude/`. Чтобы skill+rule применялись в других проектах, нужен mechanism (cp, symlink, deploy script). Пока — manual; добавить deployment runbook когда появится 3-й проект с этой потребностью.
3. **Skill validation через `skill-creator:skill-creator`**: skill написан вручную в каноническом формате. User mentioned skill-creator marketplace; запустить eval/benchmark на этой skill — кандидат на отдельный sprint.

## Related

- #5 (`adr-007-retire-6-skills-2-agents-built-ins`) — built-ins-first; новый skill закрывает реальный gap, не дублирует built-in.
- #11 (`adr-016-multi-agent-baseline-pilot-validation`) — environment-configurator vs self-description boundary, применён здесь.
- #12 (`trim-adr-log-retire-n-3-invariant`) — single-incident → не invariant; здесь recurring pattern multi-source evidenced.
