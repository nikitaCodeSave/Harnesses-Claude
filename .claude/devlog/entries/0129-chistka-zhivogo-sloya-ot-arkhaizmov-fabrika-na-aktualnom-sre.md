---
id: 129
date: 2026-08-07
title: "Чистка живого слоя от архаизмов: фабрика на актуальном срезе"
tags: [cleanup, docs, harness]
status: complete
---

# Чистка живого слоя от архаизмов: фабрика на актуальном срезе

## Контекст
Ресерч внешней дельты за три недели (ledger стоял на CC 2.1.211 / 16 июля, живая версия — 2.1.224)
показал, что живой слой фабрики держит устаревшее как действующее руководство: `/ultraplan`
удалён из CLI ещё в 2.1.222, а на нём был построен весь `workflow-cloud-offload.md`; в ките сотня
строк описывала баг WebSearch, закрытый фиксом 2.1.221. Плюс версионные пины расползлись по
доккам, хотя канон говорит: пин допустим ровно в одном файле.

Разделение, по которому шла чистка: **пин, который выступает руководством к действию** («на Opus
4.7 дефолт xhigh», «флаги добавлены в v2.1.142») — архаизм и убирается; **пин, который маркирует
возраст доказательства** («eval прошлого поколения, не перемерен») — провенанс и остаётся, иначе
старое измерение молча превращается в вечную истину. Архив (`docs/archive/`, devlog) не трогали —
frozen-слой по docs-discipline #3.

## Изменения

**Лаборатория (`.claude/`)**
- `workflow-cloud-offload.md` переписан без `/ultraplan`: планирование локальное по умолчанию,
  облачный канал — сессия Claude Code on the web в plan mode + `claude --teleport <id>`.
- `workflow.md`: `/review` теперь описан как алиас `/code-review` (прежнее «только GitHub PR» —
  фактическая ошибка); добавлены два anti-pattern'а из свежей first-party — инструкции самопроверки
  в промпте («use a subagent to verify» → over-verification) и markdown-спека там, где есть
  исполнимый артефакт.
- `workflow-orchestration.md` / `workflow-async.md`: снят построчный version-changelog; добавлены
  cross-session `SendMessage` + `ListAgents` с их security-инвариантами, снятый cap 200 субагентов,
  распространение worktree-изоляции на Bash, собственный worktree у `/fork`.
- `principles.md`: foundational подкреплён first-party эмпирикой (из системного промпта Claude Code
  вырезано >80% без потери на coding-евалах); в Memory-секцию добавлены gotchas-бюджет CLAUDE.md и
  `/doctor` как нативный аудитор слоя; cost envelope помечен как не перемеренный.
- `workflow-evolution.md`: «retire ritual — current gap» закрыт. `/doctor` считает реальные
  счётчики использования против context-cost — это и есть SLIM-ритуал, нативно.
- `external-sources.md`: вырезан дублирующий CHANGELOG-блок (v2.1.111…169), добавлены пять новых
  источников — context-engineering rules для Claude 5, Prompting Opus 5, AI-native SDLC security,
  how-we-contain-claude, три harness-паттерна Lance Martin, плюс arXiv 2607.14275 и HarnessX.

**Кит (плагин v1.21.4, он же глобальный скилл через symlink)**
- `native-capabilities.md` перегрунтован на CC 2.1.224 / Opus 5. Блок про падение WebSearch на
  `xhigh`/`max` сжат со ~110 строк до девяти: баг закрыт (перепроверено живьём на тех самых
  конфигурациях, что падали), сохранены переживающие его факты — родитель не видит `tool_result`
  делегата, `effort:` делегата действительно управляет уровнем, и уроки метода замера.
- Добавлена секция про `/doctor` как нативный аудит харнеса (мёртвые расширения против
  context-cost, rightsizing CLAUDE.md, бюджет листинга скиллов ~1% окна) и `prompt-audit` в
  bundled-скилле `claude-api`.
- Refresh-ledger обновлён: CC v2.1.224 · Claude 5 family · 2026-08-07 с перечнем проверенного.
- Version-пины убраны отовсюду, кроме `native-capabilities.md`; в `audit-checklist.md` §1 примеры
  различения «пин-поведение vs пин-провенанс» стали model-neutral.

## Затронутые файлы
- `.claude/docs/workflow-cloud-offload.md` — переписан без `/ultraplan`
- `.claude/docs/{workflow,workflow-orchestration,workflow-async,principles,workflow-evolution,external-sources,benchmark,harness-architecture,multi-agent}.md` — де-версионирование + новые факты
- `.claude/CLAUDE.md`, `.claude/rules/docs-discipline.md` — снятие привязок к поколению
- `~/PROJECTS/claude-code-harness/`: `plugins/harness/references/*.md` (включая
  `harness-discipline.md` — оттуда убрана устаревшая прескрипция «дай research-делегату
  `effort: high`, иначе поиск умрёт» — и `project-docs/workflow.md`), `SKILL.md`,
  `plugin.json` (1.21.3 → 1.21.4, devlog-плагин в локстепе), `CHANGELOG.md`

## Проверка
- Механические евалы кита (`./evals/run.sh mech`) — 9/9 PASS, включая целостность внутренних
  ссылок и локстеп версий.
- Внутренние ссылки лаборатории — отдельный скрипт-проход, 0 битых.
- Живые прогоны против утверждения, которое вырезали: `--effort max` на `claude-opus-5` и
  settings `effortLevel: xhigh` на `claude-opus-5[1m]` — WebSearch возвращает результаты (раньше
  эти конфигурации падали 2/2 и 4/4). Обратная проверка: `alwaysThinkingEnabled:false` + `xhigh`
  даёт немедленный 400 на весь запрос — ограничение API осталось, тихая деградация ушла.
- Кросс-вендорный ревьюер (Codex) прогнан по паре «старая/новая версия» двух ключевых файлов кита
  с задачей найти потерянное знание и противоречия — **5 находок, все приняты и исправлены**:
  потерянное предупреждение про `isApiErrorMessage` (фильтр по нему не видит отказов инструмента),
  потерянный урок «подписывай таблицу тем путём, которым мерил», неточная вводная про дефолты
  делегата (дефолт — наследование, а не отсутствие), пережившее правку «`/review` = PR-review»
  в `harness-discipline.md` и `project-docs/workflow.md`, и коллизия «чей effort несёт
  server-tool sub-request». Два первых прогона Codex до этого умерли: один по 30-минутному
  таймауту, второй — на сломанном bwrap-sandbox при явном `sandbox: read-only`.

## Related
- #128 — предыдущая запись, перегенерация артефактов лабы
- #126 — де-версионирование живого слоя, начатое при переходе на Opus 5; эта запись доводит его
  до конца и добавляет внешний intake
