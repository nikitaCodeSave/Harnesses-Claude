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

**Что инвариант НЕ запрещает**: сторонний CLI другого вендора, вызываемый
через Bash (или подключённый MCP-сервером) и работающий на собственной
подписке пользователя. Ограничение про **Anthropic API** — про способ
обращения к моделям Anthropic, не про запрет внешних инструментов. Действующий
пример — Codex CLI (`codex exec` через Bash) как cross-vendor ревьюер:
`.claude/docs/multi-agent.md` §7.3. Не «чистить» такие интеграции как нарушение.

## Перенос концепций из API-only фич

Допустим только при условии полной реализации на CLI-примитивах:
- hooks (PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, Stop)
- skills (action-skills в `.claude/skills/`)
- subagents (built-in Explore/Plan/general-purpose, custom в `.claude/agents/`)
- slash commands (`.claude/commands/`)
- `claude --print --add-dir --agents` для headless CI на OAuth-подписке

**Watch (re-checked 2026-06-17, first-party):** анонсированный на 15.06.2026 перевод
subscription-`claude -p`/Agent SDK на отдельный месячный Agent SDK credit **поставлен на паузу
в день вступления** («nothing changes for now» — Anthropic Help Center; это была 3-я попытка
сплита). На сегодня headless `claude --print` на OAuth-подписке (CI, benchmark-раннеры,
verify-фазы) **полностью цел** — тянет из обычных subscription-лимитов, отдельного credit нет.
`--bare` остаётся future-дефолтом для `-p` (пока opt-in; единственный режим, пропускающий OAuth →
требует API key). Перепроверить на следующем advance-notice Anthropic — watch-item открыт, не закрыт.

См. также `.claude/docs/principles.md` (active) — расширяет invariants.
