# API constraint (harness invariant)

Harness работает строго на подписке Claude Code в CLI. **Anthropic API не используется**.

## Out-of-scope (требуют API key)

- managed-agents (Memory stores, Dreams, Outcomes)
- beta headers (`--betas`, `managed-agents-*`, `dreaming-*`)
- `--max-budget-usd`
- `ANTHROPIC_API_KEY`-зависимые потоки
- prompt caching / batch / files / citations API
- `claude --bare` (per `claude --help` strictly требует `ANTHROPIC_API_KEY`)

Если practice требует API-key — её нет в harness'е, точка.

## Перенос концепций из API-only фич

Допустим только при условии полной реализации на CLI-примитивах:
- hooks (PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, Stop)
- skills (action-skills в `.claude/skills/`)
- subagents (built-in Explore/Plan/general-purpose, custom в `.claude/agents/`)
- slash commands (`.claude/commands/`)
- `claude --print --add-dir --agents` для headless CI на OAuth-подписке

См. также `.claude/docs/principles.md` (active) — расширяет invariants.
