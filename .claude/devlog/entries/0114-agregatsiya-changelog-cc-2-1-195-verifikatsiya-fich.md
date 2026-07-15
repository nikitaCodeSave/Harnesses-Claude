---
id: 114
date: 2026-06-27
title: "Агрегация changelog CC 2.1.195 + верификация фич"
tags: [docs, harness]
status: complete
---

# Агрегация changelog CC 2.1.195 + верификация фич

## Контекст
Оператор попросил проанализировать последние 10 релизов Claude Code (2.1.179–2.1.195) и собрать фичи, полезные для harness-лаборатории. Прогон сделан как research+verification: агрегация из локального кэша changelog + сверка каждого значимого claim против установленного бинаря 2.1.195 (не доверять changelog'у на слово). Источник: `~/.claude/cache/changelog.md` (свежий, обновляется самим CC), github.com в DENY → WebFetch не использовался.

## Изменения

**Методологическая находка (важнее самой агрегации):** прямой `grep -F "строка" $BIN` по бинарю Claude Code даёт **ложные негативы** — вернул 0/9 даже для заведомо present-строк (`CLAUDE_CODE_DISABLE_MOUSE_CLICKS`, `respondToBashCommands`, и т.д.). Причина: `~/.local/share/claude/versions/2.1.195` — Bun-скомпилированный ELF (~233M), строки лежат в сжатых/эмбеддед-секциях. Метод-чек на «claude»/«Anthropic»/«Effort level» поймал поломку **до** неверного вывода «фичи нет». Корректный метод: `strings -n 6 $BIN | grep` (+ `awk 'length<160'` против минифицированного JSX). Это §5 в действии — увидь, что оракул способен поймать сигнал, прежде чем доверять зелёному.

**Фичи, релевантные лаборатории (все verified на 2.1.195):**
- **Classifier denial-reasons видны** (2.1.193) — причина отказа в транскрипте, toast'е и `/permissions`→recent denials. Verified-строка: «No recent denials. Commands denied by the auto mode classifier will appear here». Прямо упрощает диагностику nested `claude --print` блоков (тема исследования harness'а).
- **`autoMode.classifyAllShell`** + настраиваемые `autoMode.{allow,soft_deny,hard_deny,environment}` с `$defaults`-наследованием (verified: `isAutoModeClassifyAllShellEnabled`).
- **Нативный блок деструктива** (2.1.183): `git reset --hard`/`checkout -- .`/`clean -fd`/`stash drop`, `commit --amend` чужого коммита, `terraform/pulumi/cdk destroy` — часть прежних DENY-правил harness'а покрыта из коробки (§7).
- **Workflow `agent({schema})`** abort-after-5 вместо бесконечного цикла валидации (2.1.186/187) — надёжность workflow-скриптов.
- **Background-субагенты** спрашивают разрешение в main session (не auto-deny), `Agent(type)` deny / `Agent(x,y)` allowed-types теперь энфорсятся (2.1.186) — годится как механический guardrail на состав субагентов.
- **CLI/эргономика:** `claude mcp login/logout <name>` (verified `claude mcp --help`); `/config key=value`; `--bg/--background`/`--effort`/`--fallback-model`/`--json-schema` (verified `claude --help`).
- **Смена дефолта:** `!`-команды теперь авто-провоцируют ответ модели; вернуть прежнее — `respondToBashCommands: false`.
- **Unattended:** `CLAUDE_CODE_MAX_RETRIES` cap 15 + `CLAUDE_CODE_RETRY_WATCHDOG` (для benchmark-раннеров); `CLAUDE_CLIENT_PRESENCE_FILE`; `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`.
- **Memory:** напоминание сжимать `MEMORY.md`-индекс у лимита (2.1.186).
- **Caveat:** OTEL `claude_code.assistant_response` логирует текст ответов модели (2.1.193) — у оператора `DISABLE_TELEMETRY=1`, не касается, но важно для целевых проектов.

## Затронутые файлы
- `~/.claude/projects/.../memory/feedback_classifier_blocks_nested_claude.md` — добавлен UPD-блок 2026-06-27 (denial-reasons видны, classifyAllShell, нативный деструктив-блок)
- `~/.claude/projects/.../memory/reference_cc_feature_verification_strings.md` — новая reference-память (strings|grep метод + где бинарь/кэш changelog)
- `~/.claude/projects/.../memory/MEMORY.md` — 2 индекс-строки (новая память + UPD хука classifier)
- `~/.claude/settings.json` — ранее в сессии: `CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1` (env)

## Проверка
- `claude --version` → 2.1.195; бинарь = Bun-ELF (`file` → ELF 64-bit, not stripped, 233M).
- `strings -n6 $BIN | grep -F` → 9/9 env/setting-строк present; classifier denial UI-строка present.
- `claude mcp --help` → `login`/`logout` субкоманды present (прямая проверка).
- `claude --help` → `--bg/--background`, `--effort`, `--fallback-model`, `--json-schema` present.
- Метод-валидация: прямой `grep $BIN` = 0 матчей на «claude»/«Anthropic» → метод признан невалидным, переключение на `strings`.

## Related
- #112 — анализ Steering Claude Code blog (тот же класс: research-pass по first-party CC + верификация на бинаре)
