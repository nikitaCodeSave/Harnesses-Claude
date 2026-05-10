# `.claude/hooks/` — guardrails и context-injection для Claude Code

Шелл-скрипты, которые Claude Code вызывает на конкретных событиях сессии.
Подключение — в `.claude/settings.json` (секция `hooks`). Каждый скрипт
получает JSON в stdin (payload события) и общается с Claude через
stdout/stderr + exit code.

## Зачем они нужны

Harness держится на foundational principle: **под Opus 4.7 минимум обвязки
даёт максимум продуктивности** (см. `docs/HARNESS-DECISIONS.md`).
Поэтому в `.claude/hooks/` лежат только те guardrail'ы и сигналы, которые
модель не делает нативно и которые **не дублируют built-in поведение**
Claude Code. Текущий состав — результат чистки через ADR-010 (5 hooks
удалены как избыточные).

## Текущий состав (4 hooks)

### `secret-scan.sh` — PreToolUse `Edit|Write|MultiEdit`

Блокирует запись файлов с захардкоженными секретами.

| Что детектит | Пример |
|---|---|
| AWS access key | `AKIAIOSFODNN7EXAMPLE` |
| GitHub token | `ghp_…`, `gho_…`, `ghs_…`, `ghu_…`, `ghr_…` |
| Generic API key/secret | `api_key="…24+ chars…"` |
| Private key | `-----BEGIN RSA PRIVATE KEY-----` |
| Slack token | `xoxb-…`, `xoxp-…` |

**Allow-list путей:** `*.env.example`, `*test*`, `*spec*`, `*fixture*`,
`*docs/*`, `*.md`, ADR/RESEARCH/PRACTICES — placeholder'ы там допустимы.

**При срабатывании:** `exit 2` + сообщение в stderr → Claude видит блок и
переключается на env-vars / secret manager. Не подмена секрет-менеджеру —
только защита от случайных коммитов.

**Лог:** `.claude/memory/secret-scan.jsonl`.

---

### `dangerous-cmd-block.sh` — PreToolUse `Bash`

Блокирует необратимые shell-команды до выполнения.

| Pattern | Что блокирует |
|---|---|
| `rm -rf /`, `rm -rf ~`, `rm -rf $HOME`, `rm -rf *` | wipe root/home/wildcard |
| `mkfs`, `dd if=… of=/dev/…`, `shred /` | filesystem destruction |
| `git push --force` на `main/master/prod/production/release` | force-push на protected branch |
| `git push --force --all` | force-push на все remotes |
| `:(){ :\|:& };:` | fork bomb |
| `chmod 777 /`, `chmod 777 ~` | broad chmod |
| `shutdown`, `halt`, `poweroff`, `reboot` | system power |

**Anti-false-positive:**
- если первое слово команды — `echo/printf/cat/true/false/:`, скрипт
  не сканирует (это text-output, паттерны внутри = data)
- содержимое одинарных и двойных кавычек вырезается до grep'а:
  `git commit -m "fix rm -rf bug"` пройдёт

**При срабатывании:** `exit 2` + причина в stderr.

**Лог:** `.claude/memory/dangerous-cmd.jsonl`.

---

### `auto-format.sh` — PostToolUse `Edit|Write|MultiEdit`

**Passive opt-in.** Прогоняет проектный форматтер по только что
записанному файлу — но **только если в корне проекта есть исполняемый
`.claude/format.sh`**. Harness не диктует форматтер (стек выбирает
проект); если файла нет — hook no-op.

PostToolUse по дизайну Claude Code не блокирует — даже падение форматтера
не отменяет уже состоявшийся write. Статус (`ok` / `failed` /
`not-configured`) логируется.

**Лог:** `.claude/memory/format-events.jsonl`.

**Пример `.claude/format.sh` для Python-проекта:**

```bash
#!/usr/bin/env bash
set -e
file="$1"
case "$file" in
    *.py) ruff format "$file" && ruff check --fix "$file" ;;
esac
```

Не забудьте `chmod +x .claude/format.sh`.

---

### `session-context.sh` — SessionStart

Инжектирует в начало сессии одну строку — имя последнего devlog-entry —
как `additionalContext`.

```
Last devlog entry: 0010-adr-15-retire-adr-005-implementation-warm-context-banned.md
```

**Почему так мало:** до ADR-010 hook был 58 строк (git branch/status/log
+ observability). Git-context уже инжектится built-in system-prompt'ом
Claude Code; дублировать запрещено. Осталось только harness-unique:
указатель на последнюю веху в `.claude/devlog/entries/`.

---

## Как Claude Code их вызывает

`.claude/settings.json`, секция `hooks`:

```json
{
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": ".claude/hooks/session-context.sh" }] }
  ],
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": ".claude/hooks/dangerous-cmd-block.sh" }]
    },
    {
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [{ "type": "command", "command": ".claude/hooks/secret-scan.sh" }]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [{ "type": "command", "command": ".claude/hooks/auto-format.sh" }]
    }
  ]
}
```

**Контракт hook'а:**
- stdin — JSON payload события (`tool_name`, `tool_input.command`,
  `tool_input.file_path`, `tool_input.content`, …)
- stdout:
  - на SessionStart: `{"additionalContext": "..."}` — попадёт в
    system-prompt
  - на остальных: обычно ничего
- stderr — текст для Claude (показывается на `exit 2`)
- exit codes:
  - `0` — allow / ok
  - `2` — **block** (для PreToolUse: tool не вызывается; для PostToolUse
    игнорируется — write уже произошёл)

Документация Claude Code: <https://docs.claude.com/en/docs/claude-code/hooks>

---

## Когда добавлять новый hook

**Не добавлять**, если задача:
- кодирует assumption «модель не умеет X», а Opus 4.7 умеет X нативно
- дублирует built-in инжекцию (git status, current dir, …)
- block-at-write вместо block-at-submit (anti-pattern из CLAUDE.md)
- observability ради observability без consumer'а

**Добавлять**, если зафиксировано **N≥3 случая** реальной потребности
на текущей модели, не покрытой built-in'ами и проектным CLAUDE.md
(см. «симметричное правило» в `.claude/CLAUDE.md`).

Любое расширение фиксируется ADR в `docs/HARNESS-DECISIONS.md` и
devlog-entry'ём.

---

## Отладка

```bash
# проверить, что hook исполняется без stdin (smoke-test)
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | .claude/hooks/dangerous-cmd-block.sh
echo "exit: $?"

# посмотреть логи
tail .claude/memory/secret-scan.jsonl    | jq .
tail .claude/memory/dangerous-cmd.jsonl  | jq .
tail .claude/memory/format-events.jsonl  | jq .

# временно отключить все hooks
claude --no-hooks    # см. CLI flags
```

Если hook падает с непонятной ошибкой — проверьте, что он исполняемый
(`chmod +x`), `jq` установлен, и shebang `#!/usr/bin/env bash` корректен.

---

## История

См. `docs/HARNESS-DECISIONS.md`:
- **ADR-009** — sandbox отключён, boundary держится через permissions + hooks
- **ADR-010** — удалено 5 observability/anti-pattern hooks, оставлен текущий минимум
