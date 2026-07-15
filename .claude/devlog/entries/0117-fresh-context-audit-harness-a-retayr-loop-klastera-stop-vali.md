---
id: 117
date: 2026-07-15
title: "Fresh-context аудит harness'а: ретайр loop-кластера + stop-validation, актуализация до Sonnet 5 / CC 2.1.210"
tags: [harness, audit, cleanup, loop, hooks, currency]
status: complete
---

# Fresh-context аудит: retire loop-кластера + stop-validation, актуализация модели/currency

## Контекст

Оператор запросил независимый аудит harness'а **с чистым контекстом и без привязки к
правилам репо** — только самостоятельные знания агентов + доступ к интернету/MCP — чтобы
вырезать ошибочные/устаревшие/переусложнённые решения и оставить минимальное рабочее ядро
для ultracode-разработки. Запущен dynamic workflow (`ultracode`): 4 фазы, 32 агента, ~1.66M
токенов.

**Структура аудита:**
1. **Reality** — независимый ground-truth реального состояния Claude Code (через
   `claude-code-guide` + web, БЕЗ чтения доков репо): CC **v2.1.210** (проверено `claude --version`),
   модели Opus 4.8 / **Sonnet 5** (релиз 30.06.2026) / Haiku 4.5 / Fable 5, 5 built-in субагентов,
   `ultracode` = trigger-keyword, effort default `high`, 30 hook-событий, Agent SDK credit **paused**
   (не cancelled), `--bare` future-default.
2. **Review** — 5 параллельных скептиков по срезам (spine / components / docs-sprawl / evidence /
   currency), читающих файлы как *гипотезы к проверке*.
3. **Verify** — адверсариальная проверка каждой рекомендации delete/update (default-скептик):
   из 25 high/med рекомендаций **выжили 7, отклонены 18** (почти весь агрессивный docs-снос —
   overturned: on-demand Layer-6, near-zero стоимость, distinct concerns).
4. **Synthesize** — prune-план.

Все несущие факты перепроверены на диске main thread'ом до исполнения.

## Главный вывод

Ядро harness'а **здоровое и держит тезис «минимум обвязки»** (lean CLAUDE.md 143 стр.,
founding-принципы сверены с реальностью). Балласт сконцентрирован в **одном месте —
self-improvement-машинерии**, которая противоречит собственному тезису.

## Что сделано

### A. Retire loop-кластера (HIGH — самореференсный research-балласт)
Ralph-loop мёртв с 2026-05-11 (PAUSED iter 37, «backlog exhausted»), но 3 его хука были
живьём вшиты в `settings.json`. По собственному журналу: 1 прогон ($72.50), fitness ≈ +0.000
на каждом accept'е (accept'ы = сам loop строит ещё loop-тулинг), holdout-oracle **ни разу не
запустил pytest** (баг discovery) → корректность не проверялась.
- `settings.json` → удалён весь блок `hooks` (SessionStart / PreToolUse / Stop).
- Удалены: `hooks/session-context.sh`, `hooks/loop-protected-guard.sh`, `hooks/cost-warn.sh`
  (unwired orphan), `commands/loop-status.md`, `hooks/README.md` (документировал 4 фантомных hook'а).
- `loop/` → архивирован в `docs/archive/loop-2026-05/` (git mv; негативный результат сохранён как урок).
- Каталоги `hooks/` и `commands/` исчезли (проектных хуков/команд больше нет).

### B. Retire stop-validation.sh (HIGH — эмпирически инертен)
Лог `memory/stop-validation.jsonl`: 521 вызов → **0 `pass`**, 205 `fail` (whole-repo ruff-шум,
включая `.scratch/`), 316 `skipped` (тесты в подкаталогах — discovery их не находил → test-gate
не сработал ни разу). Функция §5/§8 реальна, но не доставлена здесь.
- Удалён `hooks/stop-validation.sh` + Stop-wiring.

**Проверено (не регрессия):** глобальный `~/.claude/hooks/session-context.sh` покрывает
devlog + active-progress surfacing в каждом проекте; глобальный Stop-хук `test-quality-reminder.sh`
даёт advisory-проверку тестов (changed-files scoped, никогда не блокирует). Обе функции покрыты
глобально и корректнее.

### C. Актуализация модели/currency (HIGH/MED)
- **Sonnet 4.6 → Sonnet 5** в reasoning-tier: `principles.md:34`, `multi-agent.md:137,171`,
  `WORKFLOW.md`, `README.md`. Carve-out (не тронуто): `multi-agent.md:16` (4.7-era eval, провенанс),
  `:128` (историческая цитата Anthropic), `external-sources.md:74` (датированная regression-запись).
- **`/effort ultracode` — фабрикация** (`CLAUDE.md:69`): effort-enum закрыт (low..max), `ultracode` —
  prompt-keyword, не tier. Убрано, оставлен голый keyword.
- **De-version** 4× H1 `— Claude Code 2.1.169` (workflow-async/orchestration/cloud-offload/evolution).
- **Opus 4.7 → 4.8** в живой прозе (`workflow-cloud-offload.md:81`); carve-out: `benchmark.md:174`
  (датированное измерение) не тронуто.
- Self-пины → **2.1.210** (`README.md:3,94`, `WORKFLOW.md:3,157`); «актуально на» → 2.1.210
  (`benchmark.md:167`). «Since X» feature-provenance (`с 2.1.169`/`2.1.173`) НЕ бампалось.

### D. Doc-гигиена + dangling-refs от удалений (LOW)
- README счётчики: devlog 111/106 → **116** (32 live + 84 archive), docs 13 → **11**; дерево обновлено.
- `settings.json`: `npm publish:*`, `pip install:*` → ASK (сиблинги уже в ASK).
- `SKILL.md:10,189` — локальный `.claude/hooks/session-context.sh` → глобальный; devlog-путь → global.
- `harness-architecture.md:150-151` — hook-примеры genericized на глобальные.
- `principles.md:24,50,96`, `workflow-evolution.md:95`, `external-sources.md:70`, `benchmark.md:143,160` —
  вычищены ссылки на удалённые hooks/loop, loop-пути → archive, помечены retired.
- `workflow-async.md:16` — machine-specific `DISABLE_TELEMETRY` clause degeneralized.

**Отклонено проверкой на этапе аудита:** `workflow-*.md` family, meta-orchestrator-framing,
«30 hook-событий» (live-WebFetch подтвердил ровно 30), `settings.local.json` bypassPermissions,
Agent-SDK «paused»→«cancelled» (paused точнее), `benchmark` Layers B-D, `native-capabilities.md`-цитаты
(v2.1.195 корректна как цитата). Эти вердикты держатся.

### E. Follow-up: перецентровка архитектуры на реальный deliverable (директива оператора)

Оператор снял «отложенные» investigate-пункты: **результат проекта — не этот репозиторий, а
отгружаемый плагин `claude-code-harness` + глобальная обвязка `~/.claude/`** (единственный измеримый
результат + общая цель); это надо отразить в архитектуре, а теоретический over-build можно резать.
Сделано:
- **`harness-architecture.md` переписан** (322 → 158 строк): во главе — таблица реального deliverable
  (плагин / глобальная обвязка / лаборатория); уникальные таблицы сохранены (six loading layers,
  layer-selection, три границы, actor-views); вырезаны дубли (composition-matrix ≈ composition-table,
  compliance-checklist ≈ budgets-checklist, anti-patterns → указатель на CLAUDE.md).
- **`external-sources.md` (402 → 267)**: удалены Блоки 4/6/7/8/9 (independent practitioners /
  community essays / awesome-lists / memory-tooling / stale GitHub issues — link-farm). Сохранены
  Блоки 1-3 (first-party/insiders T1-T2), Блок 5 (research papers — грундят workflow-evolution/
  memory-layers), Блок 10 (T1-T7 rubric), footer.
- **`memory-layers.md`** — академическая преамбула + citation-dump сжаты до pointer'а + операт. ядра.
- **`benchmark.md`** — P3-P6 aspirational roadmap свёрнут в backlog-note (adopt-on-proof).
- **`external-sources.md:91`** — «~29 hook-событий» → 30 (сверено live-WebFetch).

## Урок

Loop — канонический пример overbuild'а, запрещённого founding-принципом: measurement-driven
self-improvement звучит правильно, но под способной моделью single-shot micro-A/B недомерен
под invocation-noise (CV~35%), а «quality oracle» без фактического запуска тестов = rubber-stamp.
Наблюдательный кросс-проектный аудит (#115) остаётся правильным evidence-слоем, а не numeric loop.

## Файлы

Удалены: `.claude/hooks/` (5 файлов), `.claude/commands/loop-status.md`. Архив: `loop/` →
`docs/archive/loop-2026-05/`. Правки: `settings.json`, `CLAUDE.md`, `README.md`, `WORKFLOW.md`,
`docs/{principles,multi-agent,harness-architecture,benchmark,external-sources,memory-layers,
workflow-async,workflow-orchestration,workflow-cloud-offload,workflow-evolution}.md`,
`skills/update-plan-progress/SKILL.md`.
