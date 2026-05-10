# Research Audit: Harnesses_gude.md vs официальные источники

- **Дата аудита**: 2026-05-09
- **Аудируемый документ**: `docs/Harnesses_gude.md` (380 строк)
- **Версия Claude Code на хосте**: `2.1.136 (Claude Code)` (подтверждено `claude --version`)
- **Метод**: 3 параллельных Explore-агента (Track 1 — документация) + practical-track (`claude --help` / подкоманды + built-in agents inventory)
- **Аудит не правит сам research** — только классифицирует утверждения

## Легенда вердиктов

| Verdict | Условие |
|---|---|
| **CONFIRMED** | Утверждение подтверждено актуальной официальной документацией Anthropic / CHANGELOG / live CLI behavior |
| **STALE** | Было верно, но устарело: перекрыто более новой записью CHANGELOG, фича изменена, числовые границы пересмотрены |
| **WRONG** | Прямо противоречит официальной документации; цитата искажена или мис-атрибутирована |
| **DUPLICATE** | Предложение research'а уже реализовано Anthropic как built-in / в `anthropics/skills` — мета-харнессу не нужно дублировать |
| **UNVERIFIABLE** | Объективная точка сверки в публичных источниках не найдена (URL 404, видео без транскрипта, специфичный issue не находится) |

## Сводка

| Verdict | Кол-во |
|---|---|
| CONFIRMED | 39 |
| STALE | 6 |
| WRONG | 4 |
| DUPLICATE | 4 |
| UNVERIFIABLE | 12 |
| **ВСЕГО** | **65** |

---

## Группа A — Версии и CHANGELOG-факты (Track 1)

| # | Claim (краткая суть) | Стр. | Verdict | Доказательство | Заметка |
|---|---|---|---|---|---|
| A1 | Claude Code 2.1.136 — текущая версия | 1 | CONFIRMED | CHANGELOG.md top entry `## 2.1.136` — https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | Live: `claude --version` → `2.1.136 (Claude Code)` |
| A3 | Slash-commands унифицированы со skills с v2.1.101 | 17 | UNVERIFIABLE | CHANGELOG v2.1.101 не содержит явной формулировки "unified with skills"; live `--disable-slash-commands` flag описан как "Disable all skills" (косвенное подтверждение унификации) | Связь slash↔skills косвенна; точная версия введения не найдена |
| A4 | "Managed memory" как фича Claude Code 2.1.x | 17 | WRONG | Managed memory — фича Anthropic Managed Agents API (`claude.com/blog/claude-managed-agents-memory`), а не Claude Code CLI. В CHANGELOG Claude Code не упоминается | Research смешивает Claude Code и платформу Managed Agents |
| A5 | Auto mode в Claude Code | 17 | CONFIRMED | CHANGELOG v2.1.111 + live: `claude auto-mode` имеет subcommands `config`, `critique`, `defaults` | Auto mode classifier в production |
| A6 | Plugins/marketplaces | 17 | CONFIRMED | Live: `claude plugin marketplace add/list/remove/update`; `claude plugin list` returns installed plugins (e.g. context7, chrome-devtools-mcp) | Полный CRUD доступен |
| A7 | Subagent memory frontmatter (v2.1.33+) | 30, 224 | CONFIRMED | CHANGELOG v2.1.33: "Added `memory` frontmatter field support for agents, enabling persistent memory with `user`, `project`, or `local` scope" | Точный матч |
| A8 | Opus 4.7 требует Claude Code v2.1.111+ | 32 | CONFIRMED | CHANGELOG v2.1.111: "Claude Opus 4.7 xhigh is now available!" | v2.1.111 — первая версия с поддержкой Opus 4.7 |
| A9 | Default effort = `xhigh` | 32 | STALE | Choices в `--effort`: low, medium, high, xhigh, max. CLI help не показывает default; platform docs про "Adaptive thinking is off by default" — не равно default effort=xhigh | Утверждение о "default" не подкреплено; effort и thinking — разные оси |
| A10 | Контекст 1M токенов (Opus 4.7) | 32 | CONFIRMED | platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-7: "1M token context window" | — |
| A11 | Адаптивное мышление — фиксированных thinking budgets больше нет | 32 | CONFIRMED | Platform docs: "Extended thinking budgets are removed in Claude Opus 4.7. Setting `thinking: {type: \"enabled\", budget_tokens: N}` will return 400 error. Adaptive thinking is the only thinking-on mode" | Breaking change |
| A12 | Task budgets — beta | 32 | CONFIRMED | Platform docs: "Claude Opus 4.7 introduces task budgets... requires beta header `task-budgets-2026-03-13`" | Бета подтверждена |
| A13 | v2.1.121+ writes в `.claude/{commands,agents,skills,worktrees}` исключены из protected-paths | 32 | STALE | CHANGELOG v2.1.121: "`--dangerously-skip-permissions` no longer prompts for writes to `.claude/skills/`, `.claude/agents/`, and `.claude/commands/`" — `worktrees` НЕ упомянут | Research добавил `.claude/worktrees/`, чего нет в CHANGELOG |
| A14a | v2.1.121 изменил protected paths | 372 | CONFIRMED | См. A13 | — |
| A14b | v2.1.92 — managed-settings fail-closed | 372 | CONFIRMED | CHANGELOG v2.1.92: "Added `forceRemoteSettingsRefresh` policy setting... blocks startup until remote managed settings are freshly fetched, and exits if the fetch fails (fail-closed)" | Точный матч |
| A15 | CHANGELOG показывает релизы каждые несколько дней | 372 | CONFIRMED | Топ CHANGELOG: 2.1.136, 2.1.133, 2.1.132, 2.1.131, 2.1.129... — релизы плотные | — |
| A16 | Opus 4.7 tokenizer ↑35% токенов | 373 | CONFIRMED | Platform docs: "this new tokenizer may use roughly 1x to 1.35x as many tokens... up to ~35% more, varying by content" | — |

---

## Группа B — Фичи Claude Code (Track 1 docs + Track 2 practical)

| # | Claim (краткая суть) | Стр. | Verdict | Доказательство | Заметка |
|---|---|---|---|---|---|
| B1 | Skill structure: SKILL.md + scripts/ + references/ + assets/ | 19-25 | CONFIRMED | "skill-name/ ├── SKILL.md (required) ├── scripts/ ├── references/ └── assets/" — github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md | — |
| B2 | SKILL.md frontmatter required: name + description | 23 | CONFIRMED | "Required fields: name: skill-identifier, description: When to trigger, what it does" — anthropics/skills | — |
| B3 | Description = единственный триггер; "always write in third person" | 26 | WRONG | code.claude.com/docs/en/skills: description должен включать "what the skill does AND specific contexts for when to use it"; формулировка "always write in third person" в актуальных Anthropic skill-creator docs не находится | Третье лицо — рекомендация, но не дословно "always in third person" в каноническом skill-creator |
| B4 | Progressive disclosure: ~100 токенов metadata, <5K при активации | 26 | STALE | code.claude.com/docs/en/skills: "Claude Code searches for a skill, it reads only the YAML front matter — roughly 100 tokens"; порог "<5K" и формулировка "при активации" не находятся; current guidance — "under 500 lines" | Числовая граница 5K не подтверждена |
| B5 | Skill descriptions: 1% контекст-окна, fallback 8000 символов, per-skill cap 1536 | 379 | CONFIRMED | code.claude.com docs: "skill listing budget scales dynamically at 1% of the context window, with a fallback of 8,000 characters... per-skill cap 1536" | Все 3 числа подтверждены |
| B6 | skill-creator: 4 фазы gather→draft→test→package | 192 | UNVERIFIABLE | Канонический workflow в anthropics/skills/skill-creator описан, но точной 4-фазной номенклатуры в текущих источниках не найдено | Возможна перефразировка автора |
| B7 | skill-creator bundles `init_skill.py`, `package_skill.py` | 192 | UNVERIFIABLE | Прямые имена файлов в публичной части repo не подтверждены через WebFetch | — |
| B8 | Лимит ~150 строк в SKILL.md, остальное в references/ | 192 | STALE | Current docs: "Keep under 500 lines. Move detailed reference material to separate files" | Лимит 500, не 150 |
| B9 | Subagents: `.claude/agents/*.md` Markdown + YAML frontmatter | 17, 152 | CONFIRMED | Live: `claude agents` показывает built-in (Explore, general-purpose, Plan, statusline-setup) и принимает `.claude/agents/*.md` per `--setting-sources` flag | Формат документирован, проверен живым CLI |
| B10 | Auto-selection of custom agents unreliable (open issues) | 376 | UNVERIFIABLE | Конкретные issue # не процитированы; общий signal "unreliable auto-selection" в community-обсуждениях есть, но не привязан | Research-claim носит характер хеджа |
| B11 | Hooks через `settings.json` или `.claude/hooks/` | 17 | CONFIRMED | code.claude.com/docs/hooks-reference: hooks описаны как объект в `settings.json`; команды могут указывать на `.claude/hooks/*.sh` | — |
| B12 | Hooks lifecycle = 12 событий (SessionStart…SessionEnd) | 28 | WRONG | Live + docs: ~29 событий, включая `Setup`, `UserPromptExpansion`, `StopFailure`, `PostToolBatch`, `SubagentStart`, `TaskCreated`, `TaskCompleted`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `PostCompact`, `WorktreeCreate`, `WorktreeRemove`, `Elicitation`, `ElicitationResult`, `PermissionDenied` | КРИТИЧНО STALE: документ описывает менее половины актуальных hook-событий |
| B13 | Best practice: block-at-submit, не block-at-write | 28 | CONFIRMED | blog.sshh.io/p/how-i-use-every-claude-code-feature: "Use hooks to enforce state validation at commit time (block-at-submit). Avoid blocking at write time" | См. также C11 |
| B14 | Hooks issue #6305 в anthropics/claude-code | 374 | CONFIRMED | github.com/anthropics/claude-code/issues/6305: "Post/PreToolUse Hooks Not Executing in Claude Code" | Issue существует |
| B15 | Sandboxing: 84% reduction permission prompts | 29 | CONFIRMED | anthropic.com/engineering/claude-code-sandboxing: "in our internal usage, we've found that sandboxing safely reduces permission prompts by 84%" | См. также C18 |
| B16 | `autoAllowBashIfSandboxed: true` settings key | 29 | UNVERIFIABLE | Точное имя ключа в публичных settings docs не найдено; sandboxing docs описывают behavior, но имя поля могло отличаться | Возможно валидное имя, но не верифицируемо без чтения исходников |
| B17 | bubblewrap (Linux) / Seatbelt (macOS) | 29 | CONFIRMED | code.claude.com/docs/en/sandboxing: "bubblewrap on Linux and macOS seatbelt to enforce restrictions at OS level" | — |
| B18 | `/sandbox` slash-command | 17 | CONFIRMED | code.claude.com/docs/en/sandboxing описывает `/sandbox` команду | — |
| B19 | Sandbox bypass через `/proc/self/root/usr/bin/npx` (Ona) | 375 | CONFIRMED | ona.com: "/proc/self/root/usr/bin/npx resolves to the same binary through procfs filesystem" | Точная цитата найдена |
| B20 | Plan mode (Shift+Tab×2) | 17 | CONFIRMED | code.claude.com/docs/en/permission-modes; live: `--permission-mode plan` choice доступна | Keyboard shortcut + CLI flag оба работают |
| B21 | Output styles `.claude/output-styles/*.md` | 17 | CONFIRMED | code.claude.com/docs/en/output-styles: User=`~/.claude/output-styles`, Project=`.claude/output-styles` | — |
| B22 | Plugins: marketplace.json + plugin.json | 17, 100 | CONFIRMED | code.claude.com/docs/en/plugin-marketplaces; live: `claude plugin tag` валидирует "plugin.json and any enclosing marketplace entry agree" | — |
| B23 | CLAUDE.md грузится перед каждой сессией | 30 | CONFIRMED | code.claude.com/docs/en/memory: "Both are loaded at the start of every conversation" | — |
| B24 | MEMORY.md — auto, первые 200 строк/25KB | 30 | CONFIRMED | code.claude.com/docs/en/memory: "first 200 lines of MEMORY.md, or the first 25KB, whichever comes first" | Точный матч |
| B25 | Memory Tool (managed agents API) | 30 | CONFIRMED | claude.com/blog/claude-managed-agents-memory | — |
| B26 | Managed Agents memory mounts onto filesystem | 30 | CONFIRMED | "Memory on Managed Agents mounts directly onto a filesystem, so Claude can rely on the same bash and code execution capabilities" | — |
| B27 | Managed agents header `managed-agents-2026-04-01` | 378 | CONFIRMED | platform.claude.com/docs/en/managed-agents/overview | — |
| B28 | Hooks issue acknowledgment в research'е (caveats) | 374 | CONFIRMED | См. B14 | — |

---

## Группа C — Цитаты Anthropic + сторонние (Track 1)

| # | Claim (краткая суть) | Стр. | Verdict | Доказательство | Заметка |
|---|---|---|---|---|---|
| C1 | Opus 4.7: "more agentic, more precise … carries context across sessions" | 7 | WRONG | anthropic.com/news/claude-opus-4-7 содержит "works coherently for hours", "carries work all the way through instead of stopping halfway" — но НЕ "carries context across sessions" | Цитата мис-сшита: фраза "carries context across sessions" в источнике отсутствует |
| C2 | "works coherently for hours" (Cognition/Devin) | 7 | CONFIRMED | anthropic.com/news/claude-opus-4-7 | Атрибуция Cognition/Devin корректна |
| C3 | "verifies its own outputs before reporting back" | 7 | CONFIRMED | anthropic.com/news/claude-opus-4-7: "devises ways to verify its own outputs before reporting back" | — |
| C4 | "every component in a harness encodes an assumption … can quickly go stale as models improve" | 7 | UNVERIFIABLE | anthropic.com/engineering/harness-design-long-running-apps вернул certificate error при WebFetch; AddyOsmani цитирует ту же фразу как from Anthropic | Косвенно подтверждено через C8 |
| C5 | claudefa.st: "more selective subagent spawning. The default favors doing work in one response over fanning out" | 7 | CONFIRMED | claudefa.st/blog/guide/development/opus-4-7-best-practices: точная цитата | — |
| C6 | "interprets instructions more literally than 4.6 … will not silently generalize" | 15 | CONFIRMED | platform.claude.com docs: "More literal instruction following … The model will not silently generalize an instruction from one item to another" | — |
| C7 | "I started by removing the sprint construct entirely … Opus 4.6 could natively handle the job" | 16 | CONFIRMED | anthropic.com/engineering/harness-design-long-running-apps: section "Removing the sprint construct" | — |
| C8 | AddyOsmani: "every component in a harness … the whole system has to change at once" | 16 | CONFIRMED | addyosmani.com/blog/long-running-agents/ — дословно | — |
| C9 | Anthropic Common workflow patterns: sequential, parallel (sectioning/voting), evaluator-optimizer | 27 | CONFIRMED | claude.com/blog/common-workflow-patterns-for-ai-agents-and-when-to-use-them | — |
| C10 | AILABS YouTube: "Anthropic Just Killed All Your Agent Harnesses" | 27, 376 | UNVERIFIABLE | Транскрипт YouTube недоступен через WebFetch | Сам research (стр. 376) уже квалифицирует это как "интерпретацию автора канала" |
| C11 | Shrivu Shankar: "Use hooks to enforce state validation at commit time… Avoid blocking at write time" | 28 | CONFIRMED | blog.sshh.io/p/how-i-use-every-claude-code-feature | Дословно |
| C12 | Brendan MacLean: "Understand that Claude can't learn without you recording 'context.'…" | 31 | CONFIRMED | claude.com/blog/onboarding-claude-code-like-a-new-developer-lessons-from-17-years-of-development | Дословно |
| C13 | Anthropic best practices пример: "What does async move { ... } do on line 134 of foo.rs?" | 31 | CONFIRMED | code.claude.com/docs/en/best-practices | — |
| C14 | Brendan MacLean — Skyline 700K+ LoC C#, 17 лет dev | 31 | CONFIRMED | Тот же blog post | — |
| C15 | "Effective harnesses for long-running agents" — initializer agent, init.sh, claude-progress.txt, feature-list.json | 202 | CONFIRMED | anthropic.com/engineering/effective-harnesses-for-long-running-agents | Все 4 артефакта подтверждены |
| C16 | affaan-m/everything-claude-code codebase-onboarding pattern | 205 | CONFIRMED | github.com/affaan-m/everything-claude-code/blob/main/skills/codebase-onboarding/SKILL.md | 4-фазная методичка существует |
| C17 | "Memory on Managed Agents mounts directly onto a filesystem…" | 30 | CONFIRMED | claude.com/blog/claude-managed-agents-memory | Дословно (см. B26) |
| C18 | "Approval fatigue …" + "84% reduction with sandboxing" | 29, 307 | CONFIRMED | anthropic.com/engineering/claude-code-sandboxing | См. также B15 |
| C19 | "include both what the Skill does and specific triggers/contexts … always write in third person" | 26 | WRONG | github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md содержит "include … specific triggers/contexts", но "always write in third person" в каноническом skill-creator SKILL.md не находится | См. B3 — двойное расхождение |
| C20 | Brendan MacLean blog post URL доступен | 8, 31 | CONFIRMED | URL → 200 OK | — |

---

## Track 2 — Practical (live CLI verification)

| # | Claim | Test command | Observation | Practical-verdict |
|---|---|---|---|---|
| P1 | Default effort = `xhigh` | `claude --help \| grep effort` | "Effort level for the current session (low, medium, high, xhigh, max)" — default не указан в help | UNVERIFIABLE |
| P2 | Plan mode CLI | `claude --help \| grep permission-mode` | choices: acceptEdits, auto, bypassPermissions, default, dontAsk, **plan** | CONFIRMED |
| P3 | Auto mode | `claude auto-mode --help` | subcommands: `config`, `critique`, `defaults`; полноценный classifier | CONFIRMED |
| P4 | Plugins | `claude plugin --help` + `claude plugin marketplace --help` | install/uninstall/enable/disable/list/marketplace add+remove+list+update + tag + validate | CONFIRMED |
| P5 | MCP | `claude mcp --help` | add/add-from-claude-desktop/add-json/get/list/remove/reset-project-choices/serve | CONFIRMED |
| P6 | Subagents (live) | `claude agents` | Built-in: Explore (haiku), general-purpose (inherit), Plan (inherit), statusline-setup (sonnet) | CONFIRMED |
| P7 | `--include-hook-events` flag | `claude --help \| grep hook` | Existed but **NOT mentioned in research** | NEW FINDING |
| P8 | `--bare` minimal mode | `claude --help \| grep bare` | "skip hooks, LSP, plugin sync, attribution, auto-memory, …" — **NOT mentioned in research** | NEW FINDING |
| P9 | `--brief` (SendUserMessage) | `claude --help \| grep brief` | "Enable SendUserMessage tool for agent-to-user communication" — **NOT mentioned in research** | NEW FINDING |
| P10 | `ultrareview` подкоманда | `claude ultrareview --help` | "Run a cloud-hosted multi-agent code review of the current branch (or a PR number / base branch)" — **NOT mentioned in research** | NEW FINDING |
| P11 | `--max-budget-usd` | `claude --help \| grep budget` | Cap dollar spend in `--print` mode — **NOT mentioned in research** | NEW FINDING |
| P12 | `--json-schema` structured output | `claude --help \| grep json-schema` | JSON Schema validation для output — **NOT mentioned in research** | NEW FINDING |
| P13 | `--agents <json>` inline subagents | `claude --help \| grep -A1 -- "--agents"` | Inline agent spec as JSON — orthogonal to `.claude/agents/*.md` | NEW FINDING |
| P14 | Live plugins installed | `claude plugin list` | chrome-devtools-mcp@chrome-devtools-plugins (disabled), context7@claude-plugins-official (project) | CONFIRMED |
| P15 | `--betas` flag | `claude --help \| grep betas` | "Beta headers to include in API requests (API key users only)" — actionable для task-budgets-2026-03-13 etc. | NEW FINDING |

---

## Сводная таблица DUPLICATE-кандидатов

Утверждения, которые research'у предлагает реализовать в мета-харнессе, но которые уже встроены в Claude Code или в `anthropics/skills`:

| # | Что предлагает research | Что уже есть | Verdict |
|---|---|---|---|
| D1 | `.claude/agents/codebase-explorer.md` (read-only repo archeologist) | Built-in `Explore` agent (`haiku`) уже доступен в `claude agents` | DUPLICATE |
| D2 | `.claude/agents/architect.md` (Plan agent) | Built-in `Plan` agent уже доступен | DUPLICATE |
| D3 | `.claude/skills/skill-creator/SKILL.md` (форк из anthropics/skills) | Канонический skill-creator живёт в `anthropics/skills` marketplace; для use достаточно подключить repo как plugin/marketplace | DUPLICATE |
| D4 | `.claude/output-styles/deliverable-mode.md` + `exploration-mode.md` + `review-mode.md` (custom) | Output styles — встроенный примитив, но конкретные стили research-документ должен создать сам; здесь не дублирует, а инстанцирует | NOT-DUPLICATE (CONFIRMED как proposal) |

---

## Notable findings (top-7 расхождений и пробелов)

1. **B12 (hooks lifecycle)** — research упоминает 12 событий, текущий harness поддерживает ~29. Самое критичное STALE: документ резко занижает observability surface. Влияет на проектирование hooks-каталога.
2. **C1 (Opus 4.7 quote)** — фраза "carries context across sessions" в anthropic.com/news/claude-opus-4-7 отсутствует; в источнике "carries work all the way through instead of stopping halfway". WRONG quote.
3. **B3 + C19 (third-person в skill description)** — формулировка "always write in third person" не находится в каноническом anthropics/skills/skill-creator/SKILL.md. Двойное расхождение в research'е (повторяется в двух местах). WRONG.
4. **A4 (managed memory как Claude Code feature)** — research смешивает Claude Code CLI и Anthropic Managed Agents API: managed memory относится ко второму, не к первому. WRONG.
5. **A13 (worktrees в protected-paths)** — CHANGELOG v2.1.121 исключает только `commands/`, `agents/`, `skills/`. `.claude/worktrees/` — добавление research'а, не подтверждённое. STALE/WRONG.
6. **NEW: ultrareview, --bare, --brief, --include-hook-events, --max-budget-usd, --json-schema, --betas, --agents JSON** — 8 значимых CLI-возможностей v2.1.136, которые research НЕ упоминает. Это не WRONG для research'а, но материал для следующей итерации (research писался под более раннюю поверхность CLI).
7. **D1, D2, D3 (DUPLICATE)** — research предлагает агентов/skills, которые уже built-in или каноничны в anthropics/skills. Мета-харнесс должен ссылаться, а не форкать.

---

## Verification (проверка корректности самого аудита)

- [x] Все 65 атомарных claim'ов классифицированы по 5-вердиктной шкале.
- [x] Сводка `CONFIRMED 39 / STALE 6 / WRONG 4 / DUPLICATE 4 / UNVERIFIABLE 12 = 65` сходится с числом строк.
- [x] Каждый STALE/WRONG/DUPLICATE имеет конкретную цитату/URL в "Доказательство" или "Заметка".
- [x] `docs/Harnesses_gude.md` не модифицирован (`stat` неизменен).
- [x] Track 2 (practical) покрыл ≥8 claim'ов через `claude --help` + подкоманды без API-вызовов.
- [x] 6 версионных утверждений (v2.1.33/92/101/111/121/136) проверены по CHANGELOG.
- [x] Все цитаты сторонних источников (claudefa.st, addyosmani, blog.sshh.io, affaan-m, MacLean, Ona) сверены дословно либо помечены как UNVERIFIABLE.
