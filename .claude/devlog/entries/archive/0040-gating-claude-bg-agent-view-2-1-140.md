---
id: 40
date: 2026-05-13
title: "Расследование gating механизма claude --bg / Agent View (2.1.140)"
tags: [research, claude-code-builtins, factcheck, cli-gating]
status: complete
---

# Расследование gating механизма claude --bg / Agent View (2.1.140)

## Контекст

После релиза Claude Code 2.1.140 (changelog упоминает фикс `claude --bg` "connection dropped mid-request") оператор попросил протестировать функционал. Запуск `claude --bg "echo test"` неизменно возвращает `'--bg' is not enabled. If this is unexpected, retry in a moment.` — и в nested CLI context (внутри Claude Code session), и в свежем shell оператора. Расследование выявило, что это **не bug конфигурации**, а server-side cohort gating через account-level policy. Документация на [code.claude.com/docs/en/agent-view](https://code.claude.com/docs/en/agent-view) описывает feature как **research preview**, но не объясняет механизм активации.

## Эмпирически подтверждено

1. **Версия CLI**: `claude --version` → `2.1.140 (Claude Code)`. Threshold по доке = 2.1.139, требование выполнено.
2. **Симптом 1 — `--bg`**: `claude --bg "<prompt>"` → `'--bg' is not enabled. If this is unexpected, retry in a moment.` (exit 0). Воспроизводится у оператора в свежем shell и в nested context.
3. **Симптом 2 — `claude agents`**: выводит список subagent'ов и выходит с exit 0 (вместо открытия TUI). Совпадает с troubleshooting case из доки: *"If `claude agents` prints a count followed by your configured subagents and then exits, agent view is unavailable in your environment."*
4. **Supervisor никогда не стартовал**: `~/.claude/jobs/`, `~/.claude/daemon/`, `~/.claude/daemon.log` — **не существуют**.
5. **Локальные disable-флаги НЕ установлены**: ни `disableAgentView` в settings.json (project/user/local), ни `CLAUDE_CODE_DISABLE_AGENT_VIEW` env.
6. **Other experimental flags работают**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` активен → значит global feature-flag механизм не сломан. Per-feature gating.

## Root cause из бинарного анализа

В `/home/nikita/.local/share/claude/versions/2.1.140` (ELF, not stripped) точная функция блокировки:

```javascript
async function checkBgEligibility({H=false, cwd:$}={}) {
  let q = [];
  if (!R4("allow_remote_sessions")) {
    q.push({type: "policy_blocked"});
    bH("bg_remote_eligibility_check", "policy_blocked");
    return q;
  }
  // ... not_logged_in, github_app_not_installed checks
}
```

`R4("allow_remote_sessions")` — **server-side policy resolver**, читает account-level config (через Statsig/policy API). Сейчас возвращает `false` для нашего account.

**Все `allow_*` policies в бинаре**: `allow_all`, `allow_product_feedback`, `allow_quick_web_setup`, `allow_remote_control`, `allow_remote_sessions`, `allow_routines`. Нет ни `allow_background_sessions`, ни локального override для `allow_remote_sessions` — управление 100% server-side.

**Дополнительно**: ~60 строк `tengu_bg_*` в бинаре (`tengu_bg_dispatch`, `tengu_bg_attach`, `tengu_bg_daemon_install`, и т.п.) — это **telemetry event names** для Statsig, **не runtime gates**. Имплементация background-sessions полная, просто feature gate возвращает false.

## Что НЕ помогает (проверено)

| Попытка | Результат |
|---|---|
| Локальный disable-override в settings.json | Не существует enable-side флаг |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_VIEW=1` / similar env | Не распознаётся бинарём |
| `claude config` / `claude auto-mode` | Не управляют `allow_remote_sessions` |
| Retry после паузы | Сообщение «retry in a moment» — копи-паста, не triggered поведение |
| Свежий shell (не-nested) | Симптом идентичен — это не nested CLI issue |
| `claude doctor` | Интерактивный, требует human input — не подходит для batched diag |

## Гипотеза про "почему cohort gating через allow_remote_sessions"

Документация говорит про local sessions: *"Sessions are local: background sessions run on your machine"*. Но gate называется `allow_remote_sessions`. Объяснение — local Agent View **architecturally** использует тот же supervisor/daemon stack, что и Cloud-режим (Claude Code on the Web). Anthropic не различает gating на этом уровне: либо у тебя есть доступ к **background sessions infrastructure** (local + remote), либо нет.

## Рекомендации

1. **Не пытаться форсировать локально** — невозможно без модификации бинаря.
2. **Periodic recheck** — раз в неделю пробовать `claude --bg "test"`. Когда раскатают cohort, увидим session ID.
3. **Активные альтернативы прямо сейчас**:
   - `Bash run_in_background: true` — для long-running shell команд внутри Claude session
   - `Agent run_in_background: true` — для параллельных subagent'ов через Task tool
   - `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — уже включен, можно протестировать Agent Teams
4. **Если ускорить активацию нужно** — feedback в Anthropic (Pro/Max аккаунт может иметь priority в research-preview cohort'ах).
5. **При раскатке** — пере-проверить changelog 2.1.140 fix про "connection dropped mid-request" в реальном использовании; до этого момента сам fix не верифицируем.

## Затронутые файлы

- `.claude/devlog/entries/0040-bg-flag-investigation.md` (этот файл)
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/reference_bg_flag_gating.md` — memory с диагностикой для будущих сессий
- `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/MEMORY.md` — index обновлён

## Проверка

```bash
# Симптом блокировки (текущее состояние)
claude --bg "test" 2>&1
# → '--bg' is not enabled. If this is unexpected, retry in a moment.

claude agents
# → выводит список subagent'ов и exit 0 (НЕ TUI)

# Когда раскатают cohort — те же команды должны:
# claude --bg "test" → "backgrounded · <8-char-id>" + management hints
# claude agents → full-screen TUI с таблицей сессий
```

Binary evidence:
```bash
BINARY=/home/nikita/.local/share/claude/versions/2.1.140
strings -n 30 "$BINARY" | grep -E 'allow_[a-z_]+|bg_remote_eligibility_check'
```

## Related

- #37 — empirical fact-check 2.1.139 (предыдущая итерация проверки Agent View; уточняем: TUI mode требует server-policy активации, недоступен для нашего account на 2026-05-13)
- memory `reference_bg_flag_gating.md` — диагностические шаги и signature симптомов для будущих сессий
