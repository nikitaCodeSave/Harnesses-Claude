---
id: 6
date: 2026-05-09
title: "ADR-008 sandbox baseline + SessionStart context hook + effort guidance"
tags: [feature, harness, hooks, security, adr]
status: complete
---

# ADR-008 sandbox baseline + SessionStart context hook + effort guidance

## Контекст

Прогон по 6 canonical Anthropic статьям (harness-design, effective-harnesses, sandboxing, opus-4-7-best-practices, multi-agent-systems, common-workflow-patterns) выявил три baseline practice, явно рекомендованных Anthropic, у которых в harness'е НЕ было реализации. После ADR-007 cleanup'а (минимизация дубликатов built-ins) — это дополнение реальных недостающих компонентов, не overengineering.

## Изменения

### 1. Sandbox enabled (`.claude/settings.json`)

Canonical baseline per [code.claude.com/docs/settings#sandbox](https://code.claude.com/docs/en/settings):

```json
"sandbox": {
  "enabled": true,
  "autoAllowBashIfSandboxed": true,
  "failIfUnavailable": false,
  "filesystem": {
    "allowWrite": ["/tmp", "/var/tmp", "~/.cache"],
    "denyRead": ["~/.aws/credentials", "~/.aws/config", "~/.ssh", "~/.gnupg",
                 "~/.kube/config", "~/.docker/config.json", "~/.netrc", "~/.pgpass"]
  },
  "network": {
    "allowedDomains": ["github.com", "*.github.com", "raw.githubusercontent.com",
                       "objects.githubusercontent.com", "api.anthropic.com",
                       "code.claude.com", "claude.com", "anthropic.com",
                       "*.npmjs.org", "registry.npmjs.org", "pypi.org",
                       "*.pypi.org", "files.pythonhosted.org",
                       "deb.debian.org", "archive.ubuntu.com", "security.ubuntu.com"]
  }
}
```

Эффект: per Anthropic — «sandboxing safely reduces permission prompts by 84%». Уровень OS-level isolation (bubblewrap на Linux/WSL2, Seatbelt на macOS). Working directory writable по default. Эмпирически подтверждено: sandbox активировался в текущей сессии через ConfigChange hook reload, `/tmp` стал read-only до добавления в `allowWrite`.

Permission whitelist (106 allow / 23 ask / 13 deny) сохранён — sandbox это «вдобавок», не «вместо»: OS-level boundary + app-level UX.

### 2. SessionStart hook (`.claude/hooks/session-context.sh`)

Effective harnesses pattern: сессия читает git log + progress + verification state на старте. Скрипт инжектит compact `additionalContext` JSON:

```
Session start (auto via SessionStart hook):
- Branch: <current branch>
- Working tree: <N> modified file(s)
- Recent commits:
  <hash> <message>
  ... (last 5)
- Last devlog entry: <filename>
```

Не блокирует. Логирует в `.claude/memory/session-starts.jsonl`. Skip silently если cwd не git repo.

Wired в `settings.json` под `SessionStart` event (новый event для нашего harness'а).

### 3. Effort & sandbox defaults в `.claude/CLAUDE.md`

Добавлена секция перед Foundational principle:
- Effort: `xhigh` default per Best Practices Opus 4.7. `max` редко (diminishing returns + overthinking). `low/medium` — cost constraints. `high` — concurrent sessions.
- Sandbox: указано что включён, обоснование (84% reduction), pointer на settings.json.

## Что НЕ добавляется (verified по тем же статьям)

Foundational principle stress-test пройден:

| Pattern из статей | Решение | Обоснование |
|---|---|---|
| Planner/Generator/Evaluator triad | НЕ добавлять | Anthropic harness-design: «removed Generator entirely, Opus 4.6 handles natively». ADR-002 уже запрещает. |
| `init.sh` для dev-сервера | НЕ в harness baseline | Project-specific. Принадлежит проектному CLAUDE.md/scripts. |
| `feature-list.json` с pass/fail | НЕ в harness baseline | Heavy для small projects. Devlog покрывает retrospective; `/plan-deliverable` — forward-looking. |
| PreCompact summary hook | НЕ добавлять | Opus 4.7 1M context делает auto-compact редким. Marginal value на baseline уровне. |
| Output styles (deliverable/exploration/review) | НЕ добавлять | Opus 4.7 нативно адаптируется к запросу. |
| MCP wiring (Playwright/GitHub/Sentry) | НЕ в harness baseline | Project-specific. |
| Custom planner/evaluator subagents | НЕ добавлять | Built-in `/plan` + main thread покрывают. ADR-001/007. |

## Затронутые файлы

- `.claude/settings.json` — добавлен sandbox блок (canonical baseline + SessionStart hook wiring).
- `.claude/hooks/session-context.sh` — новый, executable, smoke-tested.
- `.claude/CLAUDE.md` — добавлена секция «Effort & sandbox defaults».
- `docs/HARNESS-DECISIONS.md` — добавлен ADR-008 со ссылками на 6 canonical статей.

## Проверка

```bash
# settings.json валиден, sandbox активен:
python3 -c "import json; d=json.load(open('.claude/settings.json')); \
  print('sandbox.enabled:', d['sandbox']['enabled']); \
  print('hooks events:', list(d['hooks'].keys()))"
# → sandbox.enabled: True
# → hooks events: ['SessionStart', 'PreToolUse', 'PostToolUse', 'ConfigChange',
#                  'CwdChanged', 'PermissionDenied', 'StopFailure']

# SessionStart hook возвращает additionalContext JSON:
echo '{}' | bash .claude/hooks/session-context.sh
# → {"additionalContext": "Session start (auto via SessionStart hook):\n- Branch: ...

# Все 11 предыдущих hook smoke tests продолжают PASS (regression check):
bash /tmp/harness-hook-tests.sh
# → Results: 11 passed, 0 failed

# Эмпирически: после ConfigChange settings.json reload, /tmp стал read-only
# до явного addition в filesystem.allowWrite. Это validation что sandbox
# реально активен на этой машине (Linux + bubblewrap).
```

## Что вернуть после Stage 2

- Tuning sandbox `network.allowedDomains` если pilot'у нужны specific domains (Slack/Sentry/internal).
- Tuning `filesystem.allowWrite` если pilot'у нужны specific paths (например `/var/run/docker.sock`).
- Возможно расширение SessionStart context (CI status, recent test results) — если battle-test покажет потребность.

## Related

- #5 — ADR-007 cleanup (предшествующая запись).
- ADR-008 в `docs/HARNESS-DECISIONS.md`.
- Источники в ADR-008: 6 canonical Anthropic статей (ссылки в самом ADR).
