---
id: 84
date: 2026-06-10
title: "Regulation v1 Phase 1→2: portable paths (R4), audit-role resolution fix (R6), plugin v1.1.0"
tags: [harness, regulation, plugin, hooks, external-audit]
status: complete
---

# Regulation v1 Phase 1→2: portable paths, audit-role resolution, plugin v1.1.0

## Контекст
Трек «Регламент v1» (план `.claude/plans/standard-v1-regulation.md`, прогресс
`.claude/progress/standard-v1.md`). После Phase 1 R1–R3 (#83) оставался R4 (гигиена путей)
и Phase 2 (упаковка). Session 2 нашла функц. дефект ключевой фичи: agents из `~/.claude/agents/`
НЕ резолвятся как `subagent_type` Task'а из контекста чужого проекта → plugin-доставленный
`/external-audit` не заработал бы в целевом проекте. Этот дефект (R6) приоритетнее R4-полировки.
Track A (прод-расследование migration) и Track B (фикс SGR CRITICAL) исключены оператором из
трека — фокус на регламенте/harness.

## Изменения
В `~/.claude` (репозиторий `dot-claude`, commit 2e4a1f2):
- **R6 — `commands/external-audit.md`:** спавн-механика ролей переписана. Вместо
  `subagent_type: <role>` (не резолвится cross-project) — `subagent_type: general-purpose` +
  первой строкой prompt'а чтение role-файла с диска по ROLE_DIR-fallback:
  `${CLAUDE_PLUGIN_ROOT}/agents/` → `~/.claude/agents/` → `.claude/agents/` (первый существующий
  через `ls`). Работает для всех 3 путей доставки. Шаг 2 (jq-валидация) приведён к тому же ROLE_DIR.
- **R4 — `settings.json`:** 5 абсолютных путей `/home/nikita/.claude/...` (4 hooks + statusline)
  → `$HOME/.claude/...`. Факт-чек подтвердил: hooks исполняются в shell-form (без `args`) → sh
  раскрывает `$HOME`; переменной для глобального `~/.claude` в CC нет, `$HOME/.claude` —
  каноничный переносимый вариант. Проверено `sh -c` — все 5 путей резолвятся в реальные файлы.
- **P1/P2 — манифесты + README:** `plugin.json` + `marketplace.json` 1.0.0→1.1.0 синхронно,
  оба проходят `claude plugin validate` (CC 2.1.170). README: 3 пути доставки (git-clone /
  plugin install / offline archive) с ЧЕСТНЫМ составом каждого — `/external-audit` живёт в корне
  слоя, не внутри директории плагина (`./skills/claude-code-harness`), поэтому в standalone-plugin
  пока НЕ входит (упаковка внутрь отложена до эмпирической проверки T1); + re-pin процедура
  (sync версий + validate; native-capabilities при minor-релизе CC).

## Факты, установленные факт-чеком (claude-code-guide)
- Plugin несёт commands+agents по конвенции (директории в КОРНЕ плагина, не в `.claude-plugin/`).
- `${CLAUDE_PLUGIN_ROOT}` раскрывается inline в теле command/agent плагина — основа R6-fallback.
- `claude plugin tag` СУЩЕСТВУЕТ (создаёт `{name}--v{version}` git-тег); `validate` валидирует манифест.
- Конфликт двух путей доставки (git-clone автозагрузка корня vs plugin = поддиректория) реален —
  external-audit нельзя одновременно дать обоим без дублирования; решение отложено до T1-эмпирики.

## Проверка
- `claude plugin validate` — passed на plugin.json и marketplace.json; версии равны 1.1.0.
- `settings.json` — 0 остаточных `/home/nikita`, JSON валиден, `$HOME` раскрывается (sh -c).
- **Fresh-context verify (§8, refute-режим) на весь набор** — поймал 2 дефекта, оба исправлены
  ДО коммита: (1) Шаг 2 команды хардкодил `~/.claude/agents/` мимо ROLE_DIR-fallback (подрывал
  цель R6); (2) рассинхрон devlog-диапазона #78–81 (marketplace) vs #78–82 (README). Прямое
  подтверждение принципа: автор пропустил, свежий контекст поймал.

## Затронутые файлы
- `~/.claude/commands/external-audit.md`, `settings.json`, `README.md`,
  `skills/claude-code-harness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (2e4a1f2)
- `Harnesses-Claude/.claude/progress/standard-v1.md` — Phase 1 4/4, Phase 2 P1/P2 done, next T1

## Related
- #83 — Phase 1 R1–R3 (playbook + /external-audit + harness-evolution)
- #82 — упаковка плагина v1.0.0 (этот цикл поднял до v1.1.0)
- #78 — план dogfood-трека (регламент = его продолжение)
