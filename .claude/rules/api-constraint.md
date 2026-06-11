# API constraint (harness invariant)

Harness работает строго на подписке Claude Code в CLI. **Anthropic API не используется**.

## Out-of-scope (требуют API key)

- managed-agents (Memory stores, Dreams, Outcomes)
- beta headers (`--betas`, `managed-agents-*`, `dreaming-*`)
- `--max-budget-usd`
- `ANTHROPIC_API_KEY`-зависимые потоки
- prompt caching / batch / files / citations API
- `claude --bare` (пропускает OAuth/keychain целиком — auth только `ANTHROPIC_API_KEY` /
  `apiKeyHelper`, per headless-док)

Если practice требует API-key — её нет в harness'е, точка.

## Перенос концепций из API-only фич

Допустим только при условии полной реализации на CLI-примитивах:
- hooks (PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, Stop)
- skills (action-skills в `.claude/skills/`)
- subagents (built-in Explore/Plan/general-purpose, custom в `.claude/agents/`)
- slash commands (`.claude/commands/`)
- `claude --print --add-dir --agents` для headless CI на OAuth-подписке

**Watch (2026-06, first-party):** с 15 июня 2026 subscription-`claude -p`/Agent SDK
тарифицируется из отдельного месячного Agent SDK credit; `--bare` анонсирован как будущий
дефолт для `-p` (bare пропускает OAuth → потребует API key). Паттерн `claude --print`
(headless CI, benchmark-раннеры, verify-фазы) — перепроверить после 15.06.2026.

См. также `.claude/docs/principles.md` (active) — расширяет invariants.
