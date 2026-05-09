# Worktree №1 — hooks-expanded (промпт для исполнительного агента)

- **Цель**: реализовать 5 ценных новых хуков из P0-4 (`docs/RESEARCH-PATCHES.md`) — TaskCreated, ConfigChange, CwdChanged, PermissionDenied, StopFailure — со скриптами в `.claude/hooks/` и регистрацией в `.claude/settings.json`. Это даёт harness'у observability surface, на которую опираются последующие worktree'и.
- **Контекст**: harness уже имеет v0.1 trimmed catalog (5 кастом-агентов + мета-CLAUDE.md из коммитов после baseline `d6d922c`). Задача — добавить hooks layer поверх, без правок agents/CLAUDE.md.
- **Constraint**: подписка Claude Code в CLI. Никаких упоминаний `--betas`, `--max-budget-usd`, Managed Agents API. Hooks работают локально, через bash-скрипты.
- **Изоляция**: запуск через `Agent({isolation: "worktree", ...})` если рабочая worktree-инфра доступна; иначе — без isolation, но с git diff в конце для review.
- **Зависимость**: после Worktree №3 (✓ выполнено).

---

## Промпт для агента (копировать целиком)

> Ты исполняешь Worktree №1 — hooks-expanded — из Phase 2 плана для мета-harness под Claude Code 2.1.136 + Opus 4.7 на **подписке**.
>
> ## Контекст
> - В `.claude/` уже есть v0.1 harness (мета-CLAUDE.md + 5 кастом-агентов из коммитов после baseline). НЕ трогай существующие agents/CLAUDE.md.
> - `.claude/hooks/` — пустая директория. `.claude/settings.json` ещё нет.
> - Constraint: subscription-only. Никаких `--betas`, `--max-budget-usd`, Managed Agents API в скриптах или settings.
> - **Запрещено** править `docs/*.md`, `.claude/CLAUDE.md`, `.claude/agents/*.md`.
>
> ## Что создать
>
> ### 1. Пять hook-скриптов в `.claude/hooks/`
>
> Все скрипты — bash, исполняемые (`chmod +x`), читают JSON event payload из stdin, пишут логи в `.claude/memory/*.jsonl` (директория уже существует), exit code 0 для observability-хуков, exit 2 для блокирующих (если событие поддерживает блокировку — это нужно проверить через docs/реальное поведение).
>
> Шаблон скрипта (адаптируй под каждое событие):
> ```bash
> #!/usr/bin/env bash
> # <event-name> hook for harness v0.1
> # Reads hook event JSON from stdin per code.claude.com/docs/hooks-reference
>
> set -euo pipefail
>
> LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
> mkdir -p "$LOG_DIR"
>
> # Read full event payload
> payload="$(cat)"
> ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
>
> # ... event-specific logic ...
>
> exit 0
> ```
>
> #### 1.1 `.claude/hooks/block-empty-task-desc.sh` (TaskCreated)
> Use-case: блокирует спавн subagent'а, если description слишком короткий или пустой.
> Логика: распарсить `description` поле из payload (предполагаемое имя, проверь через debug-runner), если `len(description) < 30` или пустое — exit 2 с error message «TaskCreated blocked: subagent description must be ≥30 chars to be useful for routing». Иначе exit 0.
> Лог: append в `.claude/memory/task-created.jsonl` запись `{ts, decision: "allowed"|"blocked", desc_len, reason?}`.
>
> #### 1.2 `.claude/hooks/config-audit.sh` (ConfigChange)
> Use-case: append-only audit log изменений settings.
> Логика: append в `.claude/memory/config-audit.jsonl` запись `{ts, payload}`. Не блокирует. Async-friendly (exit 0 быстро).
>
> #### 1.3 `.claude/hooks/env-reload.sh` (CwdChanged)
> Use-case: direnv-style hint — при смене cwd предлагает перезагрузить env vars из `.envrc` (если файл есть).
> Логика: парсит `new_cwd` из payload, проверяет наличие `<new_cwd>/.envrc`, append в `.claude/memory/cwd-changes.jsonl` запись `{ts, old_cwd, new_cwd, envrc_present: bool}`. Не блокирует, не auto-source'ит .envrc (это policy decision разработчика).
>
> #### 1.4 `.claude/hooks/denied-log.sh` (PermissionDenied)
> Use-case: observability отказов permission. Накопление этого лога позволяет диагностировать approval-fatigue (84% reduction with sandboxing — см. RESEARCH-AUDIT.md B15).
> Логика: append в `.claude/memory/denied.jsonl` запись `{ts, tool, args_summary, reason?}`. Не блокирует.
>
> #### 1.5 `.claude/hooks/stop-recovery.sh` (StopFailure)
> Use-case: при провале Stop — добавляет recovery hint в `MEMORY.md` для следующей сессии (без перезаписи существующего MEMORY.md).
> Логика: парсит причину failure из payload, append в конец `MEMORY.md` (если файл существует) или create записи `## Recovery hint <ts>\n<reason>\n`. Если `MEMORY.md` отсутствует — append в `.claude/memory/recovery-hints.jsonl`.
>
> ### 2. `.claude/settings.json` — регистрация хуков
>
> Структура (per code.claude.com/docs/hooks-reference). Если точная схема settings.json для hooks отличается — адаптируй на основе live-проверки (`claude --help`, `claude doctor`, попытка загрузки).
>
> ```json
> {
>   "hooks": {
>     "TaskCreated": [
>       {
>         "hooks": [
>           {"type": "command", "command": ".claude/hooks/block-empty-task-desc.sh"}
>         ]
>       }
>     ],
>     "ConfigChange": [
>       {
>         "hooks": [
>           {"type": "command", "command": ".claude/hooks/config-audit.sh"}
>         ]
>       }
>     ],
>     "CwdChanged": [
>       {
>         "hooks": [
>           {"type": "command", "command": ".claude/hooks/env-reload.sh"}
>         ]
>       }
>     ],
>     "PermissionDenied": [
>       {
>         "hooks": [
>           {"type": "command", "command": ".claude/hooks/denied-log.sh"}
>         ]
>       }
>     ],
>     "StopFailure": [
>       {
>         "hooks": [
>           {"type": "command", "command": ".claude/hooks/stop-recovery.sh"}
>         ]
>       }
>     ]
>   }
> }
> ```
>
> ## Smoke-test (после создания)
>
> 1. **Permission/syntax check**: `bash -n .claude/hooks/*.sh` — синтаксис чист.
> 2. **Manual stdin test**: для каждого скрипта прогнать минимальный JSON через stdin:
>    ```
>    echo '{"description": ""}' | bash .claude/hooks/block-empty-task-desc.sh ; echo "exit=$?"
>    echo '{"description": "Use when developer requests a code review with at least 30 characters of context."}' | bash .claude/hooks/block-empty-task-desc.sh ; echo "exit=$?"
>    echo '{"setting":"test","old":1,"new":2}' | bash .claude/hooks/config-audit.sh ; echo "exit=$?"
>    echo '{"old_cwd":"/a","new_cwd":"/b"}' | bash .claude/hooks/env-reload.sh ; echo "exit=$?"
>    echo '{"tool":"Bash","reason":"sudo blocked"}' | bash .claude/hooks/denied-log.sh ; echo "exit=$?"
>    echo '{"reason":"context cap"}' | bash .claude/hooks/stop-recovery.sh ; echo "exit=$?"
>    ```
>    Для блокирующего скрипта (block-empty-task-desc.sh) пустой description должен дать exit 2; нормальный — exit 0. Остальные — exit 0.
> 3. **Live capture (если возможно без расхода кредитов)**: `claude --bare --print --include-hook-events --output-format=stream-json -p "list 1 file"` и поиск событий в выводе. Если требует API — пропусти (smoke-теста через stdin достаточно).
> 4. **Verify logs**: проверь что в `.claude/memory/` появились ожидаемые `.jsonl` файлы с записями.
> 5. `git status` и `git diff --stat`.
>
> ## Что НЕ делать
> - Не править `.claude/CLAUDE.md`, `.claude/agents/*.md`, `docs/*.md`.
> - Не использовать `--betas`, `--max-budget-usd` или beta headers в settings.json.
> - Не создавать хуки на старые 12 событий из v1 research'а — только эти 5 новых из P0-4.
> - Не делать exit-2 (блокировку) для observability-хуков (config-audit, env-reload, denied-log, stop-recovery) — они не должны мешать работе.
>
> ## Финальный отчёт (структура)
>
> ```
> ## Worktree №1 report
>
> ### Created files
> - .claude/hooks/block-empty-task-desc.sh (chmod +x, N lines)
> - .claude/hooks/config-audit.sh
> - .claude/hooks/env-reload.sh
> - .claude/hooks/denied-log.sh
> - .claude/hooks/stop-recovery.sh
> - .claude/settings.json (N hook events registered)
>
> ### Smoke-test results
> - bash -n: clean / errors
> - Manual stdin: per-script exit codes (table)
> - Logs created: .claude/memory/*.jsonl files (list)
> - Live capture: <output OR "skipped — would consume credits">
>
> ### Schema deviations
> Если live-проверка показала, что schema settings.json для hooks отличается от шаблона — описать здесь и адаптировать settings.json.
>
> ### git diff --stat
> <вывод>
>
> ### Issues / questions for review
> <если что-то не сошлось — например, событие не блокирует, имя поля payload другое>
> ```

---

## Когда запускать

После того как пользователь скажет «запускай Worktree №1». Я выполню `Agent` с промптом выше (try `isolation: "worktree"` first; если откажет — без isolation в main worktree, по образцу №3).

Если Worktree №1 принесёт schema deviations (формат payload отличается от ожидаемого, или settings.json hooks-блок имеет другую структуру) — фиксируем правки в `RESEARCH-PATCHES.md` (раздел «Phase 2 findings»).
