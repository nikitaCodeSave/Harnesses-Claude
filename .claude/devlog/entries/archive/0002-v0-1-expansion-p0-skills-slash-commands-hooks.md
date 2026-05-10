---
id: 2
date: 2026-05-09
title: "v0.1 expansion: P0 патчи гайда, skills для slash-commands, блокирующие hooks"
tags: [feature, harness, hooks, skills, docs]
status: complete
---

# v0.1 expansion: P0 патчи гайда, skills для slash-commands, блокирующие hooks

## Контекст

После формулировки текущего этапа harness'а в `.claude/plans/radiant-jingling-frost.md` (v0.1 — фундамент материализован) пользователь запросил параллельное исполнение четырёх задач: применение P0-патчей к research-гайду, сборка commands, блокирующие hooks, wiring skill-creator. Цель — закрыть критические пробелы Этапа 1 перед стартом Этапа 2 (battle-test).

## Изменения

### Верификация по первоисточникам Anthropic

WebFetch провёл по четырём canonical docs:
- `https://www.anthropic.com/news/claude-opus-4-7` — подтверждена цитата «carries work all the way through instead of stopping halfway».
- `https://code.claude.com/docs/en/hooks` — подтверждён каноничный список ~29 событий, включая `TaskCreated` (срабатывает на TaskCreate-tracker, не на Agent — это критично для багфикса ниже).
- `https://code.claude.com/docs/en/slash-commands` — подтверждено: «Custom commands have been merged into skills.» Skills рекомендованы; `.claude/commands/*.md` всё ещё работают, но skill takes precedence при коллизии имён.
- `https://code.claude.com/docs/en/cli-reference` — подтверждены `--bare`, `--print`, `--json-schema`, `--output-format`, `--add-dir`, `--agents`, `claude ultrareview`. `--brief` НЕ существует. `--bare` — легитимный CI-mode флаг (sets `CLAUDE_CODE_SIMPLE`), не ломает OAuth (исправлено STALE-утверждение в `.claude/CLAUDE.md`).

### Багфикс: `block-empty-task-desc` мисматчился

Старый хук был повешен на `TaskCreated`-событие, но извлекал `tool_input.description` (поле Agent tool), а не `task_description` (поле TaskCreate tracker). Результат: каждый TaskCreate-вызов блокировался (desc_len=0). Решение — переписать как PreToolUse с matcher Agent, проверять `tool_input.prompt >= 100` символов, переименовать в `block-shallow-agent-spawn.sh`. Старый файл удалён.

### Блокирующие hooks (4 новых)

Все скрипты — bash + jq, smoke-tested через `/tmp/harness-hook-tests.sh` (11 тестов, все PASS):

- `block-shallow-agent-spawn.sh` (PreToolUse:Agent) — блокирует subagent spawn с prompt < 100 символов (anti-shallow-briefing).
- `secret-scan.sh` (PreToolUse:Edit|Write|MultiEdit) — детектит AWS access keys, GitHub tokens, generic API keys, private key headers, Slack tokens. Allowlist для путей `*.env.example`, `*test*`, `*spec*`, `*fixture*`, `*docs/*`, `*.md`.
- `dangerous-cmd-block.sh` (PreToolUse:Bash) — блокирует `rm -rf /`, force-push to main/master/prod/release, fork bombs, mkfs/dd, chmod 777 / ~, shutdown/reboot.
- `auto-format.sh` (PostToolUse:Edit|Write|MultiEdit) — observability log + опциональный `${PROJECT_DIR}/.claude/format.sh` для проектного форматтера. Не блокирует.

### Skills для slash-commands (7 новых)

Per docs «commands merged into skills» — собраны как skills с `disable-model-invocation: true` + `context: fork` + `agent:` для делегирования. Все в `.claude/skills/<name>/SKILL.md`:

- `/onboard` → onboarding-agent
- `/plan-deliverable` → deliverable-planner
- `/review` → code-reviewer
- `/debug-loop` → debug-loop
- `/refactor` → built-in Plan (через основной поток)
- `/create-skill` → meta-creator (делегирует в canonical skill-creator marketplace, если установлен)
- `/spawn-agent` → meta-creator

### P0 патчи к `docs/Harnesses_gude.md`

Все 5 P0 патчей из `docs/RESEARCH-PATCHES.md` применены:
- **P0-1**: цитата Opus 4.7 переписана с verified источником (line 7).
- **P0-2**: «always write in third person» помечена как рекомендация автора (не цитата Anthropic) на line 26 + 192. Лимит SKILL.md обновлён 150 → 500 строк.
- **P0-3**: managed memory полностью удалена из перечня примитивов (line 17), иерархии памяти (line 30), раздела 5.6 (line 225). Memory hierarchy редуцирована до трёх уровней.
- **P0-4**: каталог hook-событий в Key Finding 6 (line 28) обновлён до ~29 событий, сгруппирован по фазам. Таблица в разделе 6 расширена с 8 до 15 строк (7 новых хуков, отражающих реализованные в `.claude/hooks/`).
- **P0-5**: API-only материал вычищен — «task budgets — beta» из Key Finding 10 (line 32), Stage 4 «managed agents bridge» переписан как «out of scope для CLI-harness'а» (line 202), caveat 7 про `managed-agents-2026-04-01` header заменён на общую формулировку «API-only фичи out of scope» (line 378).

Патчи P1/P2/P3 не применялись — пользователь явно запросил только P0.

### Wiring skill-creator marketplace

`.claude/CLAUDE.md` дополнен секцией Self-evolution: skill-creator подключается через `claude plugin marketplace add anthropics/skills` + `claude plugin install skill-creator@anthropics-skills` на user-level, не форкается локально. Reference materials обновлены — добавлены `docs/Harnesses_gude.md` (теперь patched), `docs/RESEARCH-PATCHES.md`, `.claude/agents/`, `.claude/hooks/`. Meta-creator агент уже содержал ссылку на marketplace, не требовал правок.

### settings.json пересобран

Hooks-wiring обновлён под новую раскладку: 4 PreToolUse (Agent, Bash, Edit|Write|MultiEdit) + 1 PostToolUse + 4 lifecycle/observability (ConfigChange, CwdChanged, PermissionDenied, StopFailure). Удалён wiring устаревшего `block-empty-task-desc.sh`. JSON валидирован через `python3 -c json.load`.

## Затронутые файлы

- `docs/Harnesses_gude.md` — 5 P0 патчей применены (10 правок в 9 точках).
- `.claude/CLAUDE.md` — fix `--bare` claim, добавлена Self-evolution секция, расширены Reference materials.
- `.claude/settings.json` — hooks-wiring пересобран под новую раскладку.
- `.claude/hooks/block-empty-task-desc.sh` — удалён.
- `.claude/hooks/block-shallow-agent-spawn.sh` — новый (PreToolUse:Agent).
- `.claude/hooks/secret-scan.sh` — новый.
- `.claude/hooks/dangerous-cmd-block.sh` — новый.
- `.claude/hooks/auto-format.sh` — новый.
- `.claude/skills/{onboard,plan-deliverable,review,debug-loop,refactor,create-skill,spawn-agent}/SKILL.md` — 7 новых skills для slash-commands.

## Проверка

```bash
# Hooks smoke-test (11 тестов)
bash /tmp/harness-hook-tests.sh
# → Results: 11 passed, 0 failed

# settings.json валиден
python3 -c "import json; json.load(open('.claude/settings.json'))"

# Inventory счётчики
ls .claude/agents/*.md | wc -l       # 5
ls .claude/hooks/*.sh | wc -l        # 8 (4 новых + 4 observability)
ls -d .claude/skills/*/ | wc -l      # 8 (devlog + 7 новых)

# Devlog index
python3 .claude/devlog/rebuild-index.py
```

## Что НЕ сделано (за рамками текущей итерации)

- **Stage 2 (battle-test)** — требует выбора пилотных проектов; задан AskUserQuestion отдельно.
- **Патчи P1/P2/P3** — не применялись (пользователь запросил только P0). Лог в `docs/RESEARCH-PATCHES.md` остаётся актуальным.
- **Output styles** (`.claude/output-styles/`) — пустой каталог, не критично.
- **pre-commit-gate.sh** — sketch, не реализован (зависит от стека пилотного проекта).

## Related

- #1 — Bootstrap devlog scaffold (предшествующая запись).
- ADR-001..005 в `docs/HARNESS-DECISIONS.md` — архитектурный канон, на который опирается эта итерация.
