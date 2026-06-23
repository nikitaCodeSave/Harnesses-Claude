---
id: 110
date: 2026-06-23
title: "Campaign-кампании: scoped-доставка протокола, не single-canon — A/B + deep-research"
tags: [harness, benchmark, research, campaign]
status: complete
---

# Campaign-кампании: рычаг — scoped-доставка протокола, не single-canon (A/B + deep-research)

## Контекст
Оператор поднял реальную боль (триггер — фича dialog_analyzer): тяжело «вести» объёмную
многоспринтовую задачу — состояние расползается по 4–6 местам, беклог рассинхронизируется между
markdown-каноном и `features.json`-зеркалом, знания фрагментируются. Запрос: найти стандарт
«кампании» (единица крупнее одной задачи). Сначала — deep-research community/first-party (НЕ
изобретать), затем эмпирический A/B одного решения.

## Что сделано (Decision)

**1. Deep-research (103 агента, 21 источник, 20/25 claims подтверждены адверсариально).**
Консенсус: spec/PRD = single-source-of-truth → декомпозиция → пер-задачное исполнение с верификацией
→ персистентное внешнее состояние. Зрелые: Spec-Kit (90k★, `/analyze`+`/converge` против дрейфа),
cc-sessions (directory-task = «campaign unit»). Out-of-scope (API-constraint): BMAD 12-агентный
pipeline (= запрещённый PM→Architect→Dev→QA), Taskmaster (нужен API-key кроме OAuth-провайдера).
**Anthropic САМА ретайрит scaffolding** (sprint-contract убран в V2: «Opus 4.6 made decomposition
unnecessary») → подтверждает foundational-принцип. Топ-урок против фрагментации беклога: task-list
= ОДИН редактируемый носитель, генерируемый из PRD one-way. (memory [[reference-campaign-workflow-research]])

**2. Эмпирический A/B решения (a) «single vs dual canon беклога».** Фикстура
`.claude/benchmark/campaign-backlog-ab/`: seed-беклог 12 задач + 7 fresh-context сессий
(sync-prone ops: status-flip/add/reprioritize/split/supersede/defer/block/rename) + детерминированный
oracle (`score.py` vs `ground-truth.json`, провалидирован: perfect→1.0/drift0). Рукав A = два
редактируемых канона (статус-кво dialog_analyzer), рукав B = один канон + генерируемая проекция.

**3. Probe механизма доставки (2 контролируемых).** nested `CLAUDE.md` в рабочей директории
**доставляется и исполняется** свежими субагентами (probe2: агент записал `REVIEWED` вместо
запрошенного `reviewed`, сославшись на конвенцию каталога). Side-finding: инъекционно-формное
правило (probe1) корректно отвергается как prompt-injection — правило кампании должно читаться как
легитимная конвенция.

## Результат (главный вывод)

| Условие | Рукав | N | md acc | json acc | drift | consistent |
|---|---|---|---|---|---|---|
| inlined-protocol (pilot) | A / B | 1 | 1.0 | 1.0 | 0 | ✓ |
| **scoped-delivery** (протокол ТОЛЬКО в nested CLAUDE.md, НЕ ре-инжектится) | A | 3 | 1.0 | 1.0 | 0 | ✓ |
| **scoped-delivery** | B | 3 | 1.0 | 1.0 | 0 | ✓ |

**H0 подтверждён, single-canon как обязательный компонент ОТКЛОНЁН.** Под Opus 4.8 dual-canon
(рукав A) держит беклог с **drift=0** даже без ре-инъекции протокола — агенты читают scoped
CLAUDE.md (`consultedConventions:true` во всех сессиях) и синхронизируют оба файла вручную, включая
split+rename. Независимо проверено: scoped-A-r3 `features.json` правился руками (проектора в каталоге
нет) и совпал с ground-truth.

**Рычаг стандарта «кампании» = надёжная scoped-доставка протокола, а не структура данных беклога.**
Реальная боль dialog_analyzer была в том, что правило не доставлялось надёжно в момент работы, а не в
dual-структуре. Single-canon снимает лишь теоретическую drift-поверхность «бесплатно», но не требуется.

**Механизм доставки (verified claude-code-guide, 2026-06-23):** nested `CLAUDE.md` в campaign-dir —
детерминированный, in-spec, нулевой глобальный контекст-налог. `paths:` frontmatter **ненадёжен**
(эвристика + кластер открытых багов #16853/#16299/#21858/#23478, unfixed) — не строить на нём.
Гарантия для must-not-miss — SessionStart/CwdChanged hook (у нас уже cwd-aware инъекция).
(memory [[reference-paths-frontmatter-rules]])

## Затронутые файлы
- `.claude/benchmark/campaign-backlog-ab/` — фикстура A/B (seed, sessions, ground-truth, protocols,
  scoped/, project_backlog.py, score.py, seed-runs*.sh, README); `runs/` gitignored.
- memory: `reference_campaign_workflow_research.md` (new), `reference_paths_frontmatter_rules.md` (re-verified)

## Проверка
- oracle само-провалидирован: ground-truth→md+json дал 1.0/1.0/drift0
- 4 полных A-прогона (pilot N=1 + scoped N=3) = 28 dual-canon сессий, drift=0 во всех
- независимый eyeball scoped-A-r3: оба файла верны, json hand-edited
- deep-research: 5 ложных claims убиты адверсариально (в т.ч. «единый канонический state-файл»)

## Alternatives considered (отклонены)
- Принудительный single-canon беклога — H0: не даёт измеримого лифта под Opus 4.8 (§2 unearned).
- `paths:` frontmatter для scoped-правил — ненадёжен (баг-кластер).
- BMAD multi-agent pipeline / Taskmaster — anti-pattern / API-constraint.
Источники: github/spec-kit, bmad, cc-sessions, eyaltoledano/claude-task-master, anthropic.com/engineering
(effective-harnesses / context-engineering), code.claude.com/docs/en/{memory,large-codebases,hooks}.

## Related / next
- Follow-on (pending operator): стандарт «кампании» в kit `claude-code-harness` = **scoped nested
  CLAUDE.md с протоколом кампании** + декларация single-entry-point/lifecycle (live→archive), БЕЗ
  принуждения к single-canon. Перенос — отдельной сессией по решению оператора.
- Memory: [[reference-campaign-workflow-research]], [[reference-paths-frontmatter-rules]],
  [[reference_critique_fresh_context_lever]] (§8 independent verify применён).
