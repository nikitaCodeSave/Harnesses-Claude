---
id: 14
date: 2026-05-10
title: "ADR-018/019: tight format + tiered benchmark"
tags: [adr, harness, docs, benchmark]
status: complete
---

# ADR-018/019: tight format + tiered benchmark

## Контекст

Continuation сессии 2026-05-10. После ADR-017 (project docs bootstrap skill + discipline rule) пользователь явно дал три задачи: (а) skill-creator validation новой skill, (б) ADR-018 на refactor HARNESS-DECISIONS.md format, (в) проработка benchmark подхода для testing/validation harness changes.

Boundary check: все три — environment configurator changes для harness self, не self-description main thread'а. ADR-018 устанавливает format invariant для будущих ADR'ов (process discipline). ADR-019 systematizes pilot validation pattern из ADR-016 в repeatable methodology. Skill-creator validation проверила существующий artifact, не создала новый.

## Изменения

### (а) skill-creator validation results

Запущен `/skill-creator:skill-creator` в режиме focused review (без full eval loop — пользователь explicitly запросил «не rewrite»). Результаты:

**Solid (оставлено)**: anatomy compliant, frontmatter complete, body imperative, anti-patterns с why-объяснением, CONTRACT.md как on-demand reference.

**Применено P1+P2+P3**:
- P1 description rewrite: убрано «Не генерирует boilerplate» из description (это constraint, не trigger), добавлены implicit triggers («needs project navigation files», «empty docs/ in non-trivial codebase», «onboards a team»), pushy phrase «Use this skill whenever...». Description визуально подтверждена в available skills list после правки.
- P2 удалён `argument-hint`: декларировал `--audit | --bootstrap | --doc <name>` modes которых workflow не поддерживал — misleading.
- P3 перенос `CONTRACT.md` → `references/CONTRACT.md`: канонический skill anatomy per skill-creator references/. Обновлены 4 ссылки в SKILL.md.

**Deferred P4**: full eval loop (subagent runs, eval-viewer, iteration). Покрывается tier 2 в новом benchmark methodology (ADR-019) — не дублируется отдельной операцией.

### (б) ADR-018: tighter ADR format + compact index

**Новый format spec для ADR-018+**:
- 4 mandatory секции: Decision (1-2 lines, императивно) / Why (2-4 bullets) / Counter-evidence to revise (concrete trigger) / Supersedes
- Optional: Alternatives considered (только non-obvious)
- Target ≤30 строк per ADR

**Compact index** добавлен в начало `HARNESS-DECISIONS.md` — 1 line per ADR (id + decision TL;DR + status). Quick-scan без открытия full ADR'ов.

**Existing ADRs (002-017)** untouched per docs-discipline rule 3 (append-only history). Format note в compact index объясняет split: legacy 002-017 vs tight 018+.

**Правила обновления лога** обновлены — format spec for 018+, compact index discipline, automation roadmap.

ADR-018 сам написан в новом формате (proof of concept, ~25 строк).

### (в) ADR-019 + HARNESS-BENCHMARK.md: tiered benchmark methodology

**3-tier approach**:
- **Tier 0** (static checks, <10 sec, blocker): 11 checks включая CLAUDE.md size budget ≤200, SKILL.md ≤500, ADR-018+ ≤30, devlog index integrity, skill discovery, agent inventory, hook smoke, retired components guard, compact index sync.
- **Tier 1** (pilot project task suite, manual+scripted): fixture `~/PROJECTS/FastApi-Base` + 5-10 standard tasks (T01 feature, T02 bugfix, T03 refactor, T04 docs, T05 ops, T06 research, T07 test). Metrics: tokens, turns, files, success, duration. Threshold: ±20% tokens / ±2 turns / 100% success rate maintained.
- **Tier 2** (per-component evals): skill-creator workflow для skills, prompt corpus для agents.
- **Tier 3** (blind compare): ad-hoc через general-purpose judge agent.

**When to run**: matrix в `HARNESS-BENCHMARK.md` определяет triggers per tier. Tier 0 = pre-commit; Tier 1 = behavior-changing ADRs; Tier 2 = component changes.

**Reporting**: каждый behavior-changing ADR attaches benchmark report (Tier 0 pass/fail + Tier 1 deltas table + conclusion).

**Implementation roadmap**:
- v1 (now): manual procedures, без automation.
- v2: `static-checks.sh` script.
- v3: scripted Tier 1 fixture runner.
- v4: pre-commit hook + CI mode.

ADR-019 в tight format (~25 строк), ссылается на `HARNESS-BENCHMARK.md` для деталей.

## Затронутые файлы

- `.claude/skills/project-docs-bootstrap/SKILL.md` — description rewrite (P1) + argument-hint removed (P2) + 4 path updates `CONTRACT.md` → `references/CONTRACT.md` (P3)
- `.claude/skills/project-docs-bootstrap/references/CONTRACT.md` — moved from sibling location (P3)
- `docs/HARNESS-DECISIONS.md` — Compact index добавлен в начало; ADR-018 + ADR-019 добавлены; Правила обновления лога расширены
- `docs/HARNESS-BENCHMARK.md` — новый methodology doc
- `.claude/CLAUDE.md` — Reference materials расширен ссылкой на HARNESS-BENCHMARK.md
- `.claude/devlog/entries/0014-*.md` — этот entry
- `.claude/devlog/index.json` — регенерирован

## Проверка

```
$ ls .claude/skills/project-docs-bootstrap/
SKILL.md  references/

$ ls .claude/skills/project-docs-bootstrap/references/
CONTRACT.md

$ grep -c "^## ADR-" docs/HARNESS-DECISIONS.md
15  # было 13 (ADR-018, ADR-019 added)

$ wc -l .claude/CLAUDE.md docs/HARNESS-BENCHMARK.md
135 .claude/CLAUDE.md  # было 131 (+4 строки)
... HARNESS-BENCHMARK.md

$ python3 .claude/devlog/rebuild-index.py
index.json updated: 14 entries
```

Tier 0 self-check на текущем harness state (manual):
- [✓] CLAUDE.md ≤ 200 строк (135)
- [✓] SKILL.md ≤ 500 строк (project-docs-bootstrap: ~135)
- [✓] ADR-018, ADR-019 ≤ 30 строк
- [✓] Devlog index regenerated successfully
- [✓] Skill frontmatter present (name + description)
- [✓] Compact index synchronized с `## ADR-` headers (15 entries each)

## Что НЕ сделано (сознательно)

- НЕ написан `.claude/benchmark/static-checks.sh` сейчас. Per ADR-019 roadmap v1 = manual procedures; script — v2 trigger когда ≥3 harness changes accumulated. Преждевременная automation = overengineering.
- НЕ запущена full Tier 1 task suite на FastApi-Base. Это первая итерация benchmark design — sample run на одном ADR'е будет следующим шагом для validation самой methodology. Сначала design lock-in, потом dogfood.
- НЕ rewritten existing ADRs (002-017) в tight format. Append-only history per docs-discipline rule 3. Compact index решает scan-cost без переписывания.
- НЕ автоматизирован compact index. Manual update OK при 15 ADR'ах; trigger для скрипта — ≥25.
- НЕ запущен skill-creator full eval loop на project-docs-bootstrap. Покрывается Tier 2 в benchmark methodology — будет запущен при следующем изменении skill'а.

## Открытые вопросы для последующих ADR

1. **Static-checks.sh implementation** — when ≥3 harness changes accumulate (skill update / agent change / hook modification). Vector: shell script с 11 checks из Tier 0.
2. **Fixture project decision**: использовать существующий `~/PROJECTS/FastApi-Base` или создать dedicated `~/PROJECTS/Harness-Bench-Fixture`. Trigger: первый случай когда FastApi-Base окажется несовместим (другой стек / closed-source state / structural changes).
3. **First benchmark dogfood** — запустить Tier 1 task suite на ближайшем behavior-changing ADR (например при изменении project-docs-bootstrap skill или новом hook'е). Validates methodology работает в реальности, ловит ли regressions, threshold realistic.

## Related

- #13 (`adr-017-project-docs-bootstrap-skill-docs-discipline-rule`) — ADR-017 ввёл append-only history rule, который ADR-018 prospective scope респектит.
- #11 (`adr-016-multi-agent-baseline-pilot-validation`) — ADR-016 pilot validation pattern → ADR-019 systematizes как Tier 1.
- #12 (`trim-adr-log-retire-n-3-invariant`) — trim'нул log до 263 строк; ADR-018 prevents regrowth через size budget.
