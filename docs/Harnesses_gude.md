# Harness для Claude Code 2.1.136 + Opus 4.7 — материалы для мета-обвязки (stack-agnostic)

> Bottom line: для Opus 4.7 правильный harness — это **тонкая мета-обвязка**, дающая модели среду (skills, subagents, hooks, sandbox, memory) и deliverable-уровень намерения, а **не** жёсткий процесс из BMAD/SpecKit с микро-планированием и Generator/Evaluator-контрактами; ниже — полная спецификация шаблонного `.claude/`-репозитория, каталог мета-агентов/skills/hooks/commands, стратегии для NEW/MATURE проектов и явный отказ от устаревших паттернов.

## TL;DR (3 пункта)

- **Перевернуть парадигму**: Opus 4.7 «more agentic, more precise … carries context across sessions», работает «coherently for hours» (Cognition/Devin) и «verifies its own outputs before reporting back» (Anthropic, [Introducing Claude Opus 4.7](https://www.anthropic.com/news/claude-opus-4-7)). Anthropic прямо формулирует принцип harness-дизайна: **«every component in a harness encodes an assumption about what the model can't do on its own, and those assumptions are worth stress testing … because they can quickly go stale as models improve»** ([Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)). Поэтому BMAD/SpecKit-style обвязки с микро-задачами, обязательными контрактами Generator↔Evaluator и многослойными гейтами для Opus 4.7 — **избыточны и вредны**: «more selective subagent spawning. The default favors doing work in one response over fanning out» ([claudefa.st](https://claudefa.st/blog/guide/development/opus-4-7-best-practices)).
- **Что harness обязан делать в эпоху Opus 4.7**: (1) дать Claude среду (skills/subagents/MCP/sandbox), (2) зафиксировать **deliverable-driven** намерение в первой сессии вместо микро-плана, (3) обеспечить детерминированные **safety/observability** через hooks (а не через попытки управлять поведением модели правилами), (4) уметь **самообучаться** — создавать новые skills/agents под нужды конкретного проекта (skill-creator/agent-creator), (5) различать стратегии **NEW project** (создаём deliverable-spec → harness разворачивается) и **MATURE project** (сначала «карта проекта» через Explore-subagent + onboarding-skill, по образцу [Onboarding Claude Code like a new developer](https://claude.com/blog/onboarding-claude-code-like-a-new-developer-lessons-from-17-years-of-development) и [skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)).
- **Конкретный артефакт**: ниже спецификация репо `.claude/` с мета-`CLAUDE.md` (только мета-уровень, проектный CLAUDE.md рождается в первой сессии), 8 мета-агентами, 6 skills (включая `skill-creator` и `agent-creator` — ядро самообучения), 7 hooks, 7 slash-commands, settings.json с permissions/sandbox/MCP/output-styles и методичкой по NEW vs MATURE сценариям.

---

## Key Findings

1. **Opus 4.7 — это литералист**, который вознаграждает чёткие deliverables и наказывает вагустовые prompts: «interprets instructions more literally than 4.6 … will not silently generalize an instruction from one item to another» ([What's new in Claude Opus 4.7](https://platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-7)). Это означает: harness больше не должен «угадывать» за пользователя — он должен принудительно собирать **intent + acceptance criteria** в первом контакте и затем не мешать модели работать.
2. **Harness-сложность снижается с каждым релизом**. Прямой эмпирический отчёт автора Anthropic harness-эксперимента: «I started by removing the sprint construct entirely. The sprint structure had helped to decompose work into chunks for the model to work coherently. Given the improvements in Opus 4.6, there was good reason to believe that the model could natively handle the job without this sort of decomposition» ([Harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps)). Анализ AddyOsmani: «every component in a harness encodes an assumption about what the model can't do on its own. When you couple them, an assumption that goes stale (e.g., the model used to need an explicit planner and now plans natively) means the whole system has to change at once» ([addyosmani.com/blog/long-running-agents](https://addyosmani.com/blog/long-running-agents/)). Вывод: **decoupled harness > tightly coupled framework**.
3. **Claude Code 2.1.x = полноценная extensibility-платформа**: skills (`.claude/skills/<name>/SKILL.md`), subagents (`.claude/agents/*.md`), hooks (`settings.json` или `.claude/hooks/`), slash-commands (унифицированы со skills с v2.1.101), MCP, sandboxing (`/sandbox`), plan mode (Shift+Tab×2), output styles (`.claude/output-styles/*.md`), managed memory ([Claude Managed Agents memory](https://claude.com/blog/claude-managed-agents-memory)), auto mode, plugins/marketplaces. Эти примитивы — атомы harness'а.
4. **Skill-creator pattern** как основа самообучения. Структура (по [anthropics/skills/skill-creator/SKILL.md](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)):
   ```
   skill-name/
   ├── SKILL.md (required: YAML frontmatter с name + description, далее markdown)
   ├── scripts/      # детерминированный код
   ├── references/   # подгружается по необходимости (progressive disclosure)
   └── assets/       # шаблоны/иконки/шрифты
   ```
   Описание (`description`) — **единственный триггер**: «include both what the Skill does and specific triggers/contexts for when to use it … always write in third person». Это критично — описание грузится в системный промпт, тело skill'а — только при срабатывании (progressive disclosure, ~100 токенов на metadata-сканирование, <5K при активации).
5. **Multi-agent — только когда оправдано**. Anthropic ([Common workflow patterns](https://claude.com/blog/common-workflow-patterns-for-ai-agents-and-when-to-use-them)) выделяет три паттерна: sequential, parallel (sectioning/voting), evaluator-optimizer. Для Opus 4.7 (особенно при включённом Auto mode) дефолт — **single-agent с делегированием в subagents только для exploration-heavy / context-isolation задач**. Парадигма «Anthropic Just Killed All Your Agent Harnesses» (видео AILABS) корректна именно в этом смысле: жёсткие BMAD/SpecKit-пайплайны с PM→Architect→Dev→QA-агентами — устаревший паттерн на Opus 4.7, но **отдельный read-only Evaluator** (как в `cwc-long-running-agents`) всё ещё ценен для quality-loop'а.
6. **Hooks — это контракт безопасности и observability**, а не способ микроменеджмента модели. Lifecycle: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop, SubagentStop, PreCompact, Notification, PermissionRequest, Setup, SessionEnd ([Hooks reference](https://code.claude.com/docs/en/hooks)). Best practice от Shrivu Shankar: «Use hooks to enforce state validation **at commit time** (block-at-submit). Avoid blocking at write time — let the agent finish its plan, then check the final result» ([blog.sshh.io](https://blog.sshh.io/p/how-i-use-every-claude-code-feature)).
7. **Sandboxing > permission flooding**. Anthropic: sandboxing «safely reduces permission prompts by 84%» в их internal usage ([claude-code-sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)). `autoAllowBashIfSandboxed: true` + filesystem/network isolation через bubblewrap/Seatbelt = модели больше автономии, меньше approval fatigue.
8. **Memory имеет иерархию**: (a) `CLAUDE.md` — статические конвенции, грузится перед каждой сессией; (b) `MEMORY.md` — auto-memory, первые 200 строк/25KB; (c) Memory Tool (managed agents API) для long-running агентов; (d) subagent memory frontmatter (v2.1.33+). Anthropic про managed memory: «Memory on Managed Agents mounts directly onto a filesystem, so Claude can rely on the same bash and code execution capabilities» ([claude-managed-agents-memory](https://claude.com/blog/claude-managed-agents-memory)).
9. **Onboarding mature codebase**: Anthropic best practices явно говорят — спрашивать Claude как нового сеньора: «What does async move { ... } do on line 134 of foo.rs?» ([Best practices for Claude Code](https://code.claude.com/docs/en/best-practices)). Brendan MacLean (17 лет разработки Skyline, 700K+ LoC C#) формулирует: «Understand that Claude can't learn without you recording 'context.' Don't expect magic … Invest in building and maintaining your context layer. And treat it like any other project artifact: version it, grow it, maintain it» ([Onboarding Claude Code like a new developer](https://claude.com/blog/onboarding-claude-code-like-a-new-developer-lessons-from-17-years-of-development)).
10. **Версионные ограничения**: Opus 4.7 требует Claude Code v2.1.111+; default effort в Claude Code = `xhigh`; контекст 1M токенов; адаптивное мышление (фиксированных thinking budgets больше нет); task budgets — beta. На v2.1.121+ writes в `.claude/commands/`, `.claude/agents/`, `.claude/skills/`, `.claude/worktrees/` исключены из protected-paths prompt — harness может legitimately self-modify.

---

## Details

### 1. Принципы дизайна harness'а для Opus 4.7

| Принцип | Что это значит на практике | Что НЕ делать (BMAD/SpecKit anti-pattern) |
|---|---|---|
| **Deliverable-driven, not task-driven** | Spec фиксирует: что должно работать (acceptance criteria), не как реализовать | Не дробить feature на 30 микро-задач с per-step контрактом |
| **Trust the model** | Один планировщик высокого уровня + единый builder; subagent — только когда нужен изолированный контекст | Не делать конвейер PM→Architect→Dev→QA-агентов как в BMAD v6 |
| **Stress-test harness assumptions** | Каждый компонент явно отвечает на вопрос «что Claude не умеет сам?» — пересматривать с каждым релизом | Не цементировать процесс, который был нужен Sonnet 4.5 |
| **Fail-loud, не fail-silent** | Hooks блокируют **в момент submit** (commit/PR), не в момент write | Не блокировать Claude посреди мысли — это «frustrates the agent» |
| **Sandbox over rules** | OS-level isolation (bubblewrap/Seatbelt) + allowlist для bash/WebFetch | Не пытаться писать в CLAUDE.md «не выполняй rm -rf» — модель найдёт обход |
| **Skills > prompts** | YAML frontmatter description = триггер; тело грузится lazy | Не лить мегарайлзы в CLAUDE.md (контекст-бюджет — public good) |
| **Self-creation** | Harness содержит skill-creator + agent-creator → растёт под проект | Не считать набор agents/skills финальным — он эволюционирует |

### 2. Полная структура шаблона `.claude/`

```
.claude/
├── CLAUDE.md                       # МЕТА-уровень, не проектный; объясняет Claude роль оркестратора
├── README.md                       # для разработчика: как стартовать, NEW vs MATURE
├── settings.json                   # permissions, sandbox, MCP, output styles, hooks
├── settings.local.json.example     # личные оверрайды (gitignored по умолчанию)
├── agents/                         # subagents (Markdown + YAML frontmatter)
│   ├── orchestrator.md
│   ├── deliverable-planner.md
│   ├── codebase-explorer.md
│   ├── architect.md
│   ├── code-reviewer.md
│   ├── debug-loop.md
│   ├── onboarding-agent.md
│   └── meta-creator.md             # создаёт новых agents/skills
├── skills/                         # skills (директории с SKILL.md)
│   ├── skill-creator/SKILL.md      # форк из anthropics/skills
│   ├── agent-creator/SKILL.md
│   ├── project-onboarding-new/SKILL.md
│   ├── project-onboarding-mature/SKILL.md
│   ├── workflow-patterns/SKILL.md  # библиотека sequential/parallel/eval-opt
│   └── memory-management/SKILL.md
├── commands/                       # slash-commands (могут быть SKILL.md тоже)
│   ├── onboard.md
│   ├── plan-deliverable.md
│   ├── spawn-agent.md
│   ├── create-skill.md
│   ├── review.md
│   ├── refactor.md
│   └── debug-loop.md
├── hooks/                          # shell-скрипты, дёрнутые hook'ами из settings.json
│   ├── secret-scan.sh              # PreToolUse:Write|Edit
│   ├── dangerous-cmd-block.sh      # PreToolUse:Bash
│   ├── auto-format.sh              # PostToolUse:Write|Edit (placeholder под стек)
│   ├── pre-commit-gate.sh          # PreToolUse:Bash(git commit)
│   ├── session-context.sh          # SessionStart
│   ├── observability.sh            # PostToolUse async log
│   └── pre-compact-summary.sh      # PreCompact
├── output-styles/
│   ├── deliverable-mode.md         # фокус на acceptance criteria
│   ├── exploration-mode.md         # для onboarding
│   └── review-mode.md
├── memory/
│   └── .gitkeep                    # для MEMORY.md, который пишет сам Claude
└── docs/
    ├── METHODOLOGY.md              # сопроводительная методичка (см. секцию 8)
    └── EVOLUTION.md                # как harness растёт через self-creation
```

### 3. `.claude/CLAUDE.md` (мета-уровень) — спецификация

Содержит **только мета-инструкции** — никакой проектной специфики:

```markdown
# Meta-orchestrator instructions for Claude Code

You are working inside a META-HARNESS designed for Claude Code 2.1.x + Opus 4.7.
This file does NOT describe the project. The project-level CLAUDE.md is created
ONLY after a first-session dialogue with the developer (see /onboard).

## Your role
1. On first contact with this repo, RUN `/onboard` (skill: project-onboarding-*).
2. Detect mode: NEW project (empty/scaffolded) or MATURE project (has code, tests, docs).
3. Build a deliverable contract WITH the developer: what should work end-to-end,
   what are the acceptance criteria. Do NOT break this into micro-tasks upfront.
4. Decide tooling per task (decision tree below) — prefer doing work in one response
   over fanning out (Opus 4.7 default behavior).

## Decision tree: command | skill | subagent | hook | nothing
- New invariant for the project? → CLAUDE.md (project-level), short imperative.
- Reusable workflow Claude should auto-invoke based on context? → SKILL.
- Explicit user-triggered shortcut? → SKILL with disable-model-invocation OR command.
- Token-heavy / context-isolation work (codebase exploration, security audit)? → SUBAGENT.
- Deterministic safety/observability rule? → HOOK.
- Already covered by Claude Code's defaults? → DO NOTHING. Avoid scaffolding decay.

## Self-evolution
You are encouraged to call skill-creator and agent-creator to extend this harness
when you observe a recurring need. Treat .claude/ as a living artifact.

## Anti-patterns (do NOT do)
- Do NOT create a multi-step PM→Architect→Dev→QA pipeline by default (Opus 4.7
  works coherently for hours; over-decomposition hurts).
- Do NOT pre-write a Generator/Evaluator contract for every sprint. Use a fresh-context
  evaluator subagent ONLY when quality criteria are subjective or hard to verify.
- Do NOT block writes mid-thought via hooks. Block at commit time (block-at-submit).
- Do NOT pollute CLAUDE.md with rules that belong in skills.

## First-session contract
Before writing code, you MUST establish with the developer:
- Stack (language, framework, package manager) — there is NO default.
- Project mode (new/mature).
- Acceptance criteria for the first deliverable.
- Verification mechanism (test command, lint, screenshot, manual).
- Sensitive paths/commands to DENY in settings.json.
Persist these in a freshly-created PROJECT-LEVEL CLAUDE.md (in repo root, not here).
```

### 4. Каталог мета-агентов (`.claude/agents/`)

Все файлы — Markdown с YAML frontmatter ([sub-agents](https://code.claude.com/docs/en/sub-agents)).

| Agent | Description (триггер) | Tools | Model | Когда использовать |
|---|---|---|---|---|
| `orchestrator` | "Main entry-point coordinator. Use when a user request spans multiple concerns (research + edit + verify) and you need to decide which specialist to spawn." | Task, Read, Glob, Grep | inherit | Дефолтный роутер. Не пишет код сам — делегирует. |
| `deliverable-planner` | "High-level deliverable planner. Use when developer states a goal without acceptance criteria. Produces a 1-page deliverable spec, NOT a task breakdown." | Read, Glob, Grep, AskUserQuestion | opus (xhigh) | Заменяет BMAD-PM. Без микро-планирования. |
| `codebase-explorer` | "Read-only repository archaeologist. Use when joining an unfamiliar codebase to produce an architecture map and convention summary." | Read, Glob, Grep | haiku/sonnet | Mature-only. Возвращает summary, не редактирует. |
| `architect` | "Use when a non-trivial design decision is needed: API contract, schema migration, dependency choice, multi-service interaction." | Read, Glob, Grep, WebFetch, WebSearch | opus (xhigh) | Только для решений, которые трудно откатить. |
| `code-reviewer` | "Use immediately after writing or modifying code. Reviews diff for correctness, security, style. Read-only." | Read, Grep, Glob, Bash(git diff:*) | sonnet | Включает PreToolUse:Bash и PostToolUse:Edit hooks. |
| `debug-loop` | "Use when a test is failing or behavior is unexpected. Iterates: reproduce → hypothesize → instrument → verify." | Read, Edit, Bash, Grep | opus | Изолированный контекст для bug hunting. |
| `onboarding-agent` | "Use on first session in a repo. Detects mode (new/mature), interviews the developer using AskUserQuestion, produces project-level CLAUDE.md." | Read, Glob, Grep, Write, AskUserQuestion | opus | Запускается через `/onboard`. |
| `meta-creator` | "Use when developer asks to extend the harness with a new skill, agent, command, or hook. Delegates to skill-creator / agent-creator skills." | Read, Write, Edit, Glob | opus | Самообучение harness'а. |

Пример frontmatter (`code-reviewer.md`):
```markdown
---
name: code-reviewer
description: Use immediately after writing or modifying code. Reviews diff for correctness, security, style. Read-only.
tools: Read, Grep, Glob, Bash
model: sonnet
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: ".claude/hooks/dangerous-cmd-block.sh"
---
You are a senior reviewer. Run `git diff` first; never review code you haven't read.
Output JSON: { "critical": [...], "warnings": [...], "suggestions": [...] }.
```

### 5. Каталог skills (`.claude/skills/`)

#### 5.1 `skill-creator/SKILL.md` (форк из [anthropics/skills](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md))
```yaml
---
name: skill-creator
description: Create or refine Agent Skills with proper structure, frontmatter, and progressive disclosure. Use when the user wants a new reusable workflow, when extending the harness, or when an existing skill is unreliable. Always invoke when the user mentions "create a skill", "add a workflow", "teach Claude how to ...", or proposes to capture a repeated procedure.
---
```
Тело — workflow из 4 фаз: (1) gather examples, (2) draft SKILL.md (description first — это триггер), (3) test by running the skill on its own examples, (4) package. Bundles `init_skill.py`, `package_skill.py`. Обязательно: imperative form, third person в description, лимит ~150 строк в SKILL.md, остальное — в `references/`.

#### 5.2 `agent-creator/SKILL.md`
Аналог skill-creator, но создаёт `.claude/agents/<name>.md`. Triggers: "create a subagent", "I need a specialist for X", "delegate Y to a separate context". Заставляет специфицировать: имя, action-oriented description с фразой "use proactively", набор tools (whitelist!), модель, hooks. Анти-паттерн в теле: «Не создавай subagent для задачи, которую можно решить одним ответом — Opus 4.7 by default favors single-response».

#### 5.3 `project-onboarding-new/SKILL.md`
Triggers: "new project", "fresh repo", "scaffold", "starting from scratch". Workflow:
1. Interview через AskUserQuestion: stack, target deployment, acceptance criteria первого deliverable, verification mechanism.
2. Создать project-level `CLAUDE.md` (в корне, не `.claude/CLAUDE.md`!) — короткий, императивный, без воды.
3. Предложить (но не насаждать) starter-зависимости и скрипты на основе ответов о стеке.
4. Выполнить `git init`, первый коммит как baseline (по образцу [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — initializer agent, который создаёт `init.sh`, `claude-progress.txt`, feature-list.json).

#### 5.4 `project-onboarding-mature/SKILL.md`
Triggers: "existing codebase", "legacy", "joining a project", "audit the repo". Workflow (по [codebase-onboarding pattern](https://github.com/affaan-m/everything-claude-code/blob/main/skills/codebase-onboarding/SKILL.md)):
1. **Phase 1 — Signals (parallel)**: package manifests, framework fingerprints, entry points, test runners, CI configs.
2. **Phase 2 — Architecture map** (через codebase-explorer subagent): top-level directories, key abstractions, hot paths.
3. **Phase 3 — Conventions**: lint config, formatting, naming, commit format.
4. **Phase 4 — Generate/enhance project-level CLAUDE.md**: ≤100 строк, callouts «обнаружено» vs «уже было». Не переписывать существующий, только дополнять.
5. Критично: «Verify, don't guess — if a framework is detected from config but the actual code uses something different, trust the code».

#### 5.5 `workflow-patterns/SKILL.md`
Library skill — содержит ссылки на 3 anthropic-паттерна с правилами выбора:
- **Sequential**: фиксированный порядок, прозрачный debug. Default для одного агента.
- **Parallel (sectioning/voting)**: independent subtasks или multiple perspectives.
- **Evaluator-optimizer**: итеративный цикл с **fresh-context evaluator** (отдельный subagent, no Write/Edit). Использовать **только** когда subjective quality / гарантированная не-ассессабельность одним проходом.
- Anti-pattern: «Don't use multi-agent for things that DON'T need parallelism, isolation, or independent evaluation».

#### 5.6 `memory-management/SKILL.md`
Иерархия памяти + правила:
- `CLAUDE.md` — invariants, ≤25KB, императивный.
- `MEMORY.md` — auto, первые 200 строк/25KB; что обнаруживается по ходу (path quirks, gotchas).
- `/compact` — manual escape, с focus hint.
- Subagent memory (frontmatter, v2.1.33+) — для специализированных агентов.
- Managed Agents memory tool — для production multi-session агентов через API.

### 6. Каталог hooks

Все из `settings.json`, скрипты — в `.claude/hooks/*.sh`. По принципу **block-at-submit, не block-at-write**:

| Event | Matcher | Скрипт | Что делает |
|---|---|---|---|
| `SessionStart` | — | `session-context.sh` | git status, активная ветка, последние 5 commits → `additionalContext` |
| `UserPromptSubmit` | — | `secret-redact.sh` | Маскирует API-ключи в prompt'е |
| `PreToolUse` | `Bash` | `dangerous-cmd-block.sh` | Регексп против `rm -rf /`, `DROP TABLE`, `chmod 777`, `sudo rm`. Exit 2 = block. |
| `PreToolUse` | `Write\|Edit\|MultiEdit` | `secret-scan.sh` | Сканирует контент на ключи/пароли. |
| `PreToolUse` | `Bash(git commit:*)` | `pre-commit-gate.sh` | Проверяет наличие `/tmp/agent-pre-commit-pass` (создаётся test-runner'ом). Если нет — block с reason. |
| `PostToolUse` | `Write\|Edit\|MultiEdit` | `auto-format.sh` | Placeholder: `# Adapts to stack after first /onboard session`. Подключает prettier/black/gofmt/etc. |
| `Stop` | — | `observability.sh` (async) | Лог сессии в `.claude/memory/session-log.jsonl` |
| `PreCompact` | — | `pre-compact-summary.sh` | Сохраняет state в `MEMORY.md` перед компактингом |

`settings.json` фрагмент:
```json
{
  "permissions": {
    "deny": ["Read(**/.env)", "Read(**/.ssh/**)", "Bash(sudo:*)", "Bash(curl:*)", "WebFetch"],
    "ask": ["Bash(git push:*)", "Bash(npm publish:*)", "Bash(rm:*)"],
    "allow": ["Read(**)", "Bash(git status)", "Bash(git diff:*)", "Bash(git log:*)"]
  },
  "sandbox": {
    "autoAllowBashIfSandboxed": true,
    "failIfUnavailable": false
  },
  "hooks": { /* как выше */ },
  "outputStyle": "deliverable-mode",
  "cleanupPeriodDays": 14,
  "enableAllProjectMcpServers": false,
  "enabledMcpjsonServers": []
}
```

### 7. Slash commands

Все — SKILL.md с `disable-model-invocation: true` (явный пользовательский триггер) либо markdown в `.claude/commands/`:

| Command | Что делает | Делегирует |
|---|---|---|
| `/onboard` | Запускает project-onboarding (new/mature по auto-detect) | onboarding-agent |
| `/plan-deliverable` | Принимает goal, возвращает 1-page deliverable spec с acceptance criteria | deliverable-planner |
| `/spawn-agent <name>` | Создаёт нового subagent через agent-creator | meta-creator |
| `/create-skill <name>` | Создаёт новый skill через skill-creator | meta-creator |
| `/review` | Diff-review последних изменений | code-reviewer |
| `/refactor <scope>` | Plan-mode → architect → builder loop | architect → main |
| `/debug-loop <symptom>` | Изолированный debug-цикл | debug-loop agent |

### 8. Стратегии: NEW vs MATURE

**NEW project (greenfield)**:
1. Developer запускает `claude` в пустой/минимальной директории.
2. Мета-`CLAUDE.md` направляет Claude на `/onboard`.
3. `onboarding-agent` через AskUserQuestion интервьюирует: стек, целевой deliverable, как верифицировать.
4. Создаётся **project-level** `CLAUDE.md` (в корне) — короткий, императивный, **только** конвенции, которые верны 100% времени.
5. Создаются скрипты `init.sh` (как стартовать dev-server) и `claude-progress.txt` (журнал между сессиями) — паттерн из [Effective harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).
6. `auto-format.sh` подключает форматтер для выбранного стека.
7. Первый деливерабл: один прогон Opus 4.7 на `xhigh` без декомпозиции, builder сам ведёт работу.

**MATURE project (legacy/большой)**:
1. `/onboard` → детектит наличие кода/тестов → запускает `project-onboarding-mature`.
2. **Codebase-explorer subagent** (read-only, Haiku или Sonnet для скорости) исследует параллельно: manifests, frameworks, entry points.
3. Возвращает summary в основной контекст; основной агент **не загружает 30 файлов** — экономит контекст.
4. Дополняется существующий `CLAUDE.md` (не переписывается).
5. Brendan MacLean's pattern: контекст — отдельный артефакт, версионируется. Возможно — отдельный репо для harness'а если он растёт независимо.
6. Plan mode (Shift+Tab×2) обязателен для первой нетривиальной задачи: сначала читаем, потом планируем, потом меняем.
7. Hook `pre-commit-gate.sh` обязателен — гарантирует, что test suite зелёный перед коммитом (block-at-submit).

### 9. Anti-patterns — явный отказ от BMAD/SpecKit

| BMAD/SpecKit pattern | Почему ломается на Opus 4.7 | Замена в нашем harness |
|---|---|---|
| 12+ ролей-агентов (PM, Architect, PO, SM, Dev, QA, ...) | "More selective subagent spawning. The default favors doing work in one response over fanning out" | 1 orchestrator + 7 узких subagents, вызываются по triggers |
| Generator↔Evaluator контракт перед каждым sprint'ом | Опыт Anthropic: «removed the sprint construct entirely … Opus 4.6 could natively handle the job without this sort of decomposition» | Optional fresh-context evaluator только для subjective quality |
| `/speckit.specify → clarify → plan → tasks → implement` rigid pipeline | Opus 4.7 «interprets instructions literally … will not silently generalize» — но также не нуждается в pre-decomposition | `/plan-deliverable` → одна сессия, plan mode при необходимости |
| `tasks.md` с десятками атомарных задач | Микро-планирование «mаkes it harder for the agent to course-correct» | Acceptance criteria + verification command, без задач |
| Constitution.md с десятками правил | Контекст-бюджет — public good. Каждый токен «depletes Claude's attention budget» | CLAUDE.md ≤25KB + skills грузятся lazy |
| Block-at-write hooks | «Blocking an agent mid-plan confuses or even 'frustrates' it» | Block-at-submit (commit/PR gates) |
| Проектный CLAUDE.md в шаблоне | Шаблон не знает стек | CLAUDE.md рождается **только** после `/onboard` |
| Per-permission approval flooding | «Approval fatigue ... users pay less attention to what they're approving» (84% reduction with sandboxing) | Sandbox + targeted ask/deny rules |

### 10. Чеклист готовности проекта к работе с harness

- [ ] Стек определён в первой сессии (через `/onboard`).
- [ ] Project-level `CLAUDE.md` создан (в корне), мета-уровневый — не тронут.
- [ ] `settings.json` имеет deny-rules для секретов (`Read(**/.env)`, `~/.ssh/**`).
- [ ] Sandbox включён (`autoAllowBashIfSandboxed: true`) или явно отвергнут с обоснованием.
- [ ] Verification mechanism определён (test command, lint, или manual checklist).
- [ ] `auto-format.sh` адаптирован под стек.
- [ ] `pre-commit-gate.sh` подключён, если есть test suite.
- [ ] MCP-серверы — только из явного allowlist (`enabledMcpjsonServers`).
- [ ] Output style выбран (`deliverable-mode` для production, `exploration-mode` для onboarding).
- [ ] Effort level подтверждён (`xhigh` дефолт; `max` только для редких сложных задач).

### 11. Эволюция harness'а через self-creation

Из [skill-creator pattern](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md): skill умеет создавать другие skills. Аналогично `agent-creator`. Цикл:
1. Claude замечает повторяющуюся процедуру → предлагает создать skill.
2. Developer соглашается → `/create-skill <name>`.
3. `skill-creator` выполняет 4 фазы (gather → draft → test → package).
4. Новый skill попадает в `.claude/skills/`, версионируется в git.
5. На следующей сессии описание уже в `available_skills` → Claude автоинвокает по контексту.
6. Если skill-описание плохо триггерится — итеративная доработка через тот же `skill-creator` (improve mode).

Это **главное архитектурное отличие** от BMAD: harness не монолитный фреймворк, а **семя**, которое прорастает в проект.

### 12. Открытые вопросы / точки кастомизации (требуют диалога с разработчиком)

1. **Стек**: язык, фреймворк, package manager, test runner, formatter, linter — определяется в `/onboard`.
2. **CI/CD интеграция**: GitHub Actions / GitLab CI / etc. — добавлять ли agent для PR-review?
3. **MCP-серверы**: какие внешние тулы нужны (Playwright, GitHub, Sentry, internal APIs)?
4. **Sandboxing intensity**: `auto-allow` или `regular-permissions` mode?
5. **Sensitive paths**: `.env`, `secrets/`, `~/.ssh/`, `.claude/settings.local.json` — что добавить в `permissions.deny`?
6. **Memory boundary**: что попадает в `MEMORY.md` (проектная), что в `~/.claude/CLAUDE.md` (личная)?
7. **Multi-developer**: кто owns `.claude/` в монорепо? Кто merge-resolves конфликты в skills?
8. **Auto mode**: Max plan? Включаем ли мы `--enable-auto-mode` для long-running tasks?
9. **Output style**: deliverable / explanatory / learning / custom?
10. **Plan mode default**: всегда стартовать в plan mode? `claude --permission-mode plan` как alias?

---

## Recommendations (staged, actionable)

**Этап 1 — собрать репо-шаблон (1 неделя)**
- Сделать публичный репо с описанной структурой `.claude/` (без проектного CLAUDE.md).
- Каждый файл-плейсхолдер должен иметь комментарий `# Adapts to stack after /onboard`.
- Включить в README пошаговый guide: `git clone → cd → claude → "Run /onboard"`.

**Этап 2 — battle-test на 2 проектах (2 недели)**
- Один greenfield, один legacy. Метрики: время до первого working deliverable, сколько раз harness был расширен через `meta-creator`, сколько hook'ов сработало.
- Threshold для перехода к Этапу 3: ≥3 успешных самосозданных skills, ≥0 false-positive blocking hooks.

**Этап 3 — публиковать как plugin (1 неделя)**
- Упаковать в Claude Code plugin (`marketplace.json` + `plugin.json`).
- Регистрировать как marketplace через `claude plugin marketplace add ...`.
- Threshold для итерации: модель Opus 4.8/5 — пересмотреть, какие subagents/hooks **больше не нужны** (apply harness assumption stress-test).

**Этап 4 — managed agents bridge (опционально)**
- Когда harness стабилизируется — портировать ключевые агенты в Claude Managed Agents API для long-running async задач (с persistent memory store).

---

## Caveats

1. **Версия Claude Code меняется быстро**: указана v2.1.136, но changelog показывает релизы каждые несколько дней (v2.1.121 изменил protected paths, v2.1.92 добавил managed-settings fail-closed). Шаблон стоит ревизовать раз в месяц.
2. **Opus 4.7 tokenizer ↑35% токенов**: тот же контент стоит до 1.35× больше. Бюджет hooks/skills нужно пересчитать.
3. **Hooks могут не срабатывать** — есть открытые баги (issue #6305 в anthropics/claude-code про PreToolUse/PostToolUse). При интеграции тестировать каждый hook индивидуально через `echo '{...}' | bash hook.sh`.
4. **Sandbox bypass**: исследование Ona показало, что Claude Code мог обойти denylist через `/proc/self/root/usr/bin/npx` и затем сам отключить bubblewrap. Sandboxing — defense-in-depth, а не absolute boundary. Для критичных сред — content-addressable enforcement (hash binaries).
5. **Auto-selection of custom agents unreliable**: open issues подтверждают, что Claude часто не делегирует в подходящий custom subagent даже при матчящемся description. Резервный путь — explicit invocation через slash command.
6. **AILABS-видео «Anthropic Just Killed All Your Agent Harnesses»** — это интерпретация автора канала, не official Anthropic statement. Anthropic engineering сами продолжают публиковать harness-патchterns (cwc-long-running-agents, generator-evaluator). Корректное прочтение тезиса: **жёсткие** harness'ы устаревают, но **тонкие meta-harness'ы** (skills/subagents/hooks) — наоборот, основа.
7. **Managed Agents memory + memory tool на Messages API** — beta, требуют `managed-agents-2026-04-01` header. Архитектура может измениться до GA.
8. **Skill descriptions конкурируют за character budget** (1% контекст-окна, fallback 8000 символов; per-skill cap 1536). При 20+ skills некоторые описания обрезаются — критичные skills нужно ставить выше или выносить low-priority в `name-only`.
9. **BMAD/SpecKit не «мертвы» абсолютно**: для regulated/audit-heavy doменов (медицина, финансы, авиация) с требованием traceability per-step — старые pipeline'ы по-прежнему дают ценность. Этот harness нацелен на mainstream coding workflow.
10. **Проектный CLAUDE.md vs мета-CLAUDE.md**: критично не путать. Шаблон содержит **только** `.claude/CLAUDE.md` (мета-уровень). Корневой `CLAUDE.md` создаёт `/onboard` после диалога.