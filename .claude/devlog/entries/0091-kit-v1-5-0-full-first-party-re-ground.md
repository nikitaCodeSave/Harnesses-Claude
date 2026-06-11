---
id: 91
date: 2026-06-11
title: "Kit v1.5.0: full first-party re-ground"
tags: [canon, plugin, release, audit, re-ground]
status: complete
---

# Kit v1.5.0: full first-party re-ground

## Контекст
Оператор спросил «вся ли информация плагина актуальна для CLI-подписки и последних
моделей/версий CC?». После урока Monitor (devlog #89) ответ дан не по памяти: 3 параллельных
fact-checker'а сверили каждый проверяемый claim native-capabilities/evidence-base/discipline
с first-party доками code.claude.com (~20 страниц WebFetch) и changelog'ом, с правилом
«авторитет существования — док, живой инвентарь — только доступность в профиле».

## Вердикт сверки
~85-90% claims CONFIRMED дословно (вкл. все 14 URL evidence-base — живые и соответствуют
заявленному). STALE-находки исправлены в v1.5.0:

- **Nested subagents (единственный жёсткий STALE)**: с 2.1.172 субагенты вкладываются до
  5 уровней — строка «cannot nest» устарела на следующий день после написания (доки
  sub-agents отстают от changelog). + добавлены fork-субагенты (/fork, 2.1.161),
  `maxTurns` / `isolation: worktree` / `memory:` (персистентная память агентов),
  deny `Agent(Explore)`.
- **ultrareview**: появилась first-party страница — 5–10 мин, $5–20/run usage credits,
  3 бесплатных на Pro/Max; мои community-цифры «~20 мин/$15–25» относились к другому
  продукту (GitHub Code Review app). Канонизировано `/code-review ultra`.
- **Dynamic workflows**: ярлык «research preview» снят доками; на Pro выключены по
  умолчанию; toggle называется «Ultracode keyword trigger».
- **Effort/Fable 5**: default `high` теперь формулируется для Fable 5+Opus 4.8/4.6+Sonnet;
  Fable-специфика (не дефолт ни на одном тарифе, ~2× цена, thinking не отключается, /fast
  не работает, safety-fallback на Opus); рекомендация «xhigh для hard tasks» ушла из доков —
  помечена 4.7-era provenance; /fast = research preview, usage credits ВНЕ подписочных
  лимитов (важно для CLI-subscription рамки).
- **Model-mapping** discipline: «Fable 5/Opus-class lead …» по собственному правилу re-map.
- **--bare rationale**: «skips OAuth entirely» (headless-док), вывод API-only стоит.
- Однострочные пробелы закрыты: Routines//schedule/RemoteTrigger (durable cron),
  PushNotification, Channels, claude-plugins-community, «background tasks не
  восстанавливаются на resume», CLAUDE_CODE_STOP_HOOK_BLOCK_CAP.

## Watch-item (зафиксирован в kit + lab api-constraint.md)
С **15.06.2026** subscription-`claude -p`/Agent SDK тарифицируется из отдельного месячного
Agent SDK credit; `--bare` анонсирован будущим дефолтом для `-p` (bare пропускает OAuth).
Все headless `claude --print` паттерны (CI, benchmark-раннеры, Phase 7 verify) —
перепроверить после этой даты.

## Не тронуто осознанно
colon-синтаксис `Bash(cmd:*)` в allowed-tools (доки показывают space-star, деприкация
colon не заявлена, работает — наблюдать); cron-детали (7d expiry/50 cap/jitter), TaskOutput
deprecated, PowerShell/LSP/WaitForMcpServers — за линзой минимализма.

## Verify
Источник каждого фикса — verbatim-цитата из first-party страницы (sub-agents, workflows,
agent-teams, model-config, fast-mode, goal, memory, hooks, scheduled-tasks, tools-reference,
plugins, cli-reference, headless, ultrareview, code-review, changelog, models/overview,
news/fable-5). Версии plugin/marketplace = 1.5.0, tag `claude-code-harness--v1.5.0`.
