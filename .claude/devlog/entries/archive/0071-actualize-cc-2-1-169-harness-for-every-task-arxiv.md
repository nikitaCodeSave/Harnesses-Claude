---
id: 71
date: 2026-06-09
title: "Actualize → CC 2.1.169 + harness for every task + arXiv"
tags: [harness, maintenance, versioning, sources, workflows, memory]
status: complete
---

# Actualize harness → CC 2.1.169 + «A harness for every task» + Code-as-Agent-Harness / EMBER

## Контекст
Оператор: «проведи анализ интернет-источников — может появились обновления по Claude
Code и агентной разработке; выполни все шаги и изучи статьи с arXiv». Baseline — devlog #70
(2026-06-07, срез на 2.1.168 + 3 источника), всего 2 дня назад. Research-пасс (4 параллельных
WebSearch + first-party WebFetch) выявил небольшую, но реальную дельту.

## Найдено (новее #70)
1. **CC 2.1.169** (Jun 8) — бинарь на машине уже 2.1.169.
2. **First-party пост, который #70 пропустил**: [«A harness for every task: dynamic workflows
   in Claude Code»](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)
   (Shihipar & Bidasaria, 2 июня) — **canonical источник самой Workflow/`ultracode` фичи**. #70
   процитировал мартовский Rajasekaran-пост, но не этот.
3. **arXiv 2605.18747 «Code as Agent Harness»** (survey, 18 мая) — трёхслойная таксономия.
4. **arXiv 2606.05894 EMBER** (июнь) — budgeted evidence-capsule retention.

## Сделано
**Step 1 — first-party dynamic-workflows post.** Добавлен в `external-sources.md` Блок 1 (T1).
Три failure-mode (*agentic laziness* / *self-preferential bias* / *goal drift*), которые
изолированные субагенты лечат структурно, внесены как **first-party обоснование §8** (fresh-context
≠ self-recheck) в `principles.md` §subagents + `multi-agent.md` §7.2. **Quarantine pattern**
(untrusted-content агенты лишены high-privilege действий) → `principles.md` §permissions +
`multi-agent.md` §7.1. Доведён до конца незавершённый #70 rename `/workflow`→`ultracode`: голый
`/workflow` как trigger — stale (first-party цитирует только keyword `ultracode` / «просто попроси»),
вычищен из `workflow.md` (×3, + исправлен framing «ultracode = setting» → «trigger word, не режим»),
`multi-agent.md`, `principles.md`, `builtins-inventory.md` И глобального скилла (native-capabilities,
harness-discipline, SKILL.md, bootstrap-checklist).

**Step 2 — version-stamp 2.1.168 → 2.1.169.** Глобальный `native-capabilities.md` (canonical срез)
+ новый bullet 2.1.169: `--safe-mode`/`CLAUDE_CODE_SAFE_MODE` (clean A/B baseline «модель vs
harness»), `disableBundledSkills`, `/cd`, `claude agents --json` (+`id`/`state`/`--all`),
worktree-edit-block hint, CLAUDE.md-threshold scaling от context-window, OTEL-cert trust. Lab-доки:
`builtins-inventory.md` (стампы + Delta-bullet + anchor-fix 211168→211169), `workflow-orchestration.md`
(`claude agents --json` + worktree-block factы), 4× `workflow-*.md` стампы, `benchmark.md`. CHANGELOG
в external-sources обновлён до 2.1.155→169.

**Step 3 — arXiv каталогизация (честно: vocabulary/validation, не новые инварианты).**
`2605.18747` (T3 survey) → `external-sources.md` Блок 5: даёт ярлыки нашему (filesystem-blackboard
= «blackboard + implicit-file-only», dynamic workflows = «objective-driven adaptive topology»,
sprint-contracts = «Planning as Contract Formation», loop/+AHE = «Governed Harness Mutation»). Его
open-challenge #1 (oracle adequacy «beyond final-task success») связан в `benchmark.md` с
Harness-Bench failure-taxonomy / Layer C. `2606.05894` EMBER → Блок 5 + `memory-layers.md`:
**method out of scope** (learned RL-policy, как SLIM/Meta-Harness), переносим только принцип
*evidence capsule = verbatim + retrieval-key + metadata*, который наши memory-файлы уже воплощают
(frontmatter `description` = key, `[[links]]` = metadata, source-backed не перефраз).

## Результат
Изменено 7 проектных доков (`principles`, `multi-agent`, `workflow`, `workflow-orchestration`,
`builtins-inventory`, `benchmark`, `external-sources`, `memory-layers`) + 4 файла глобального скилла.
Static-check чист: 0 stale `2.1.168`, 0 stale `/workflow`-trigger в live-слое. CLAUDE.md = 142 строки.
**Не делал:** новых инвариантов из single-survey (per «single-incident NOT invariant»); learned
memory-pipeline (наш anti-pattern). Открытый хвост #70 (failure-symptom taxonomy → Layer C axes)
остаётся кандидатом на P-итерацию — теперь подкреплён survey open-challenge #1.
