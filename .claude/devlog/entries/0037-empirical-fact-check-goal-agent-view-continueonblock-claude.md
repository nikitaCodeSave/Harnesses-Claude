---
id: 37
date: 2026-05-12
title: "Empirical fact-check /goal + agent view + continueOnBlock (Claude Code 2.1.139)"
tags: [research, claude-code-builtins, harness-integration, factcheck]
status: complete
---

# Empirical fact-check /goal + agent view + continueOnBlock (Claude Code 2.1.139)

## Контекст

Оператор предложил «полноценный рефакторинг harness'а под built-ins Claude Code 2.1.139» на основе чужого текста про «мета-роль агента». В тексте утверждалось: `/goal` — built-in с Haiku-evaluator, `/spec` — для plan-блоков, `continueOnBlock` — новый hook field, agent view = TUI для параллельных сессий. Принято решение: эмпирически проверить каждый факт **до** правок harness'а — потому что `feedback_grow_with_community` требует первичных источников, а foundational principle запрещает обвязку под недоказанные assumption'ы.

## Что подтверждено эмпирически

1. **Версия CLI**: `claude --version` → `2.1.139 (Claude Code)`. Бинарь: `/home/nikita/.local/share/claude/versions/2.1.139` (ELF).
2. **`/goal` — built-in**. `strings` нашёл: `/goal clear to stop early`, `/goal <condition> to set another`, `No goal set. Usage: /goal <condition>`, `/goal is only available in trusted workspaces…`, `/goal is disabled by your organization's policy (disableAllHooks)`.
3. **`/goal` работает в `--print` headless без trust dialog**. Live test в `/tmp/claude-goal-test/`: `claude --print --permission-mode acceptEdits "/goal The file file.txt … contains FOO"` → `num_turns=4`, `stop_reason=end_turn`, файл реально изменён до `FOO`.
4. **Гибрид Opus + Haiku в `/goal`**. Один прогон: Opus 4.7 1M ($0.109, основная работа) + Haiku 4.5 ($0.003, служебная). Утверждение чужого текста про «Haiku-evaluator» — правдоподобно (есть Haiku invocation), но не доказано однозначно (Haiku может быть classifier/summary/evaluator — три кандидата).
5. **`continueOnBlock` — реальное поле**. Строка `continueOnBlock` присутствует в бинаре 2.1.139. Поведение эмпирически НЕ проверено в нашем контексте.
6. **`claude agents` — TUI subcommand** (не CLI). `claude agents --help` показывает только `--setting-sources` → full-screen UI. Документация: `code.claude.com/docs/en/agent-view`.
7. **Внутренние функции `/goal`**: `goalNonInteractive`, `restoreGoalFromTranscript`, `findGoalToRestore`, `active_goal`. Поддерживается resume goal'а через transcript.

## Что в чужом тексте оказалось НЕВЕРНО или не для нашего проекта

- **`/spec`** — НЕ нативная команда. В бинаре 2.1.139 не найдена. Custom skill из `dialog_analyzer` или выдумка.
- **«multi-step pipeline неформальная → /spec → /goal → subagent → реализация → hook → review»** — описывает workflow другого проекта, не наш harness.
- **«добавить .md с описанием роли мета-ведущего»** — anti-pattern: дублирует `.claude/CLAUDE.md` + `.claude/docs/multi-agent.md`. Прямо запрещено foundational principle.

## Главная корректировка предпосылки

**Первоначальная гипотеза «retire custom-loop runner'ы в пользу `/goal`»** — ОПРОВЕРГНУТА чтением `.claude/benchmark/headless-runner.sh` и `battle-test-runner.sh`. Это **measurement pipelines** (clone fixture → inject → build → grade → report), а `/goal` — runtime loop control **внутри** одной `claude --print` сессии. Разные уровни абстракции. Замены не происходит.

Реальная точка интеграции — **prompt-engineering**: `/goal …` можно вставить в `prompt.txt` для battle-test-runner Phase 3 как acceptance condition. Это локальное усиление, не структурное изменение.

## Изменения

- **Создано** `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/reference_goal_agentview_empirical.md` — reference memory с verified/unverified утверждениями + cost watch.
- **Обновлён** `.claude/docs/benchmark.md` — добавлен раздел «Native `/goal` и `claude agents` — где применимы, где нет» в конец. Явно сказано что runner'ы и `/goal` на разных уровнях абстракции.
- **Обновлён** `~/.claude/projects/.../memory/MEMORY.md` — индекс пополнен ссылкой на новую reference memory.
- **НЕ создано**: новые skills/agents/hooks/ADR. Foundational principle: built-in's эмпирически не оправдывают создание обвязки в нашем контексте сейчас.

## Что осталось untested и почему

- **`continueOnBlock` поведение в наших hooks** — есть в бинаре, но live test не проводился. Кандидат для будущего trial, когда понадобится: например, `loop-protected-guard.sh` мог бы возвращать reject + `continueOnBlock: true` для soft-warnings вместо жёсткого block. Сейчас preconditions не появились.
- **`claude agents` для parallel benchmark runs** — TUI требует interactive trust dialog для нашего проекта (`hasTrustDialogAccepted: False` в `~/.claude.json`). Untested как параллельный runner для Layer D n=3..5 protocol. До адопции нужен проверочный прогон с (а) worktree-isolation между сессиями, (б) отсутствием гонок при записи `reports/`, (в) per-process применением `.claude/settings.json`.

## Cost watch

Один тривиальный `/goal` (одна Edit, 4 turn'а, 14s) — **$0.113**. Для long-running goals предсказуемо $1+. Любое будущее использование `/goal` в benchmark/runner — обязано иметь явное `stop after N turns` либо внешний `timeout` для cost containment.

## Связь с harness

- `.claude/docs/benchmark.md` — обновлён.
- `~/.claude/projects/.../memory/reference_goal_agentview_empirical.md` — детальный fact-check.
- `~/.claude/projects/.../memory/feedback_classifier_blocks_nested_claude.md` — классификатор пропустил nested `claude --print '/goal …'` под explicit user imperative 2026-05-12 (consistent с предыдущей эмпирикой).
- `~/.claude/projects/.../memory/feedback_grow_with_community.md` — practice применена: первичная верификация через binary+live-test, не через внутренний artifact.
