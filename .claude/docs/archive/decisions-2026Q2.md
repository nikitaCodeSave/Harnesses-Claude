# Harness Decisions Log (ADR-style)

Канон архитектурных решений для мета-harness'а. Каждое решение фиксирует **что отвергнуто**, **почему**, **что вместо**.

> Все ADR применяют Foundational principle, зафиксированный в `.claude/CLAUDE.md`.

## Preamble — Anthropic Opus 4.7 evidence

Anthropic про Opus 4.7 ([best practices](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)):
«spawns fewer subagents by default», «calls tools less often and reasons
more», «response length is calibrated to task complexity». Эти три цитаты —
эмпирическое основание для retirement-решений ниже: anti-spam обвязка,
output-styles, forced-decomposition — устаревшие assumptions под Opus 4.7.
См. ADR-010/011/012 для конкретных применений.

## Compact index

| ADR | Decision (TL;DR) | Status |
|---|---|---|
| 002 | Не выносить TDD-тройку субагентов (test-writer/impl/refactor) | active |
| 003 | TDD/BDD не зашит в harness как мета-обвязка (вместо — `rules/testing.md`) | active |
| 004 | Devlog: `index.json` (auto) + `entries/*.md` (source of truth) | active |
| 007 | Built-ins-first: retire 6 skills + 2 agents как дубликаты | active |
| 009 | Retire sandbox baseline (workflow friction > security gain) | active |
| 010 | Trim observability hooks + redundant skill (anti-spam inversion) | active |
| 011 | Retire code-reviewer agent (duplicates `/review`) | active |
| 012 | Trim meta-CLAUDE.md (decision tree → ADR refs) | active |
| 013 | Cross-session memory: auto-memory canonical, no claude-mem / MCP memory | active |
| 014 | Built-in `/init` не интервьюирует — by design под Opus 4.7 | active |
| 15  | Retire ADR-005 implementation (managed-memory port-over) | active |
| 016 | Self-описывающие skills как anti-pattern + higher-order orchestration | active |
| 017 | Project docs contract: bootstrap skill + always-loaded discipline rule | active |
| 018 | Tighter ADR format (≤30 строк) + compact index, prospective | active |
| 019 | Tiered harness benchmark methodology (Tier 0/1/2 + ad-hoc T3) | active |
| 020 | project-docs-bootstrap дополнения после first dogfood (3 fix-in-place) | active |

> Format note: ADR-002…017 в legacy формате (50-100 строк, 7-8 секций). ADR-018+ в tight формате (≤30 строк, 4 mandatory секции). См. ADR-018.

---

## ADR-002 — TDD-тройка субагентов: НЕТ

- **Контекст**: соблазн вынести RED → GREEN → REFACTOR в три отдельных субагента (test-writer / impl / refactor) для «чистой изоляции фаз».
- **Решение**: **не выносим**.
- **Обоснование**:
  1. Изоляция контекста — решение для Sonnet 3.5 / Opus 3, не для 4.7. Opus 4.7 «works coherently for hours» (RESEARCH-AUDIT.md C2) и «carries work all the way through instead of stopping halfway» (C2).
  2. Стоимость = потеря конвенций проекта: test-writer не видит `conftest.py`, фикстуры, naming style, существующие tests. Это даёт вторичную работу на «адаптацию» каждого его выхода.
  3. 3× round-trip ухудшает координацию — точно совпадает с симптомом «проблемы в росте» из foundational principle.
  4. Прямо противоречит уже зафиксированному в `.claude/CLAUDE.md` принципу: «не создавать многоступенчатый PM→Architect→Dev→QA pipeline».
- **Альтернатива**: фазы RED/GREEN/REFACTOR держим в одном контексте через `TaskCreate` с pass-критериями каждой фазы. `code-reviewer` (read-only) дёргается после GREEN если diff нетривиален.
- **Запрет на возврат**: добавлять test-writer / impl-agent / refactor-agent в `.claude/agents/` запрещено без пересмотра этого ADR.

## ADR-003 — TDD/BDD как мета-обвязка: НЕТ

- **Контекст**: возможность зашить TDD/BDD framework в harness — отдельный skill, оркестратор для red-green-refactor цикла, BDD-Gherkin-парсер, и т.п.
- **Решение**: **не зашиваем**. Вместо мета-обвязки — единая страница правил `.claude/rules/testing.md` (≤25 строк, 5 правил).
- **Обоснование**:
  1. Opus 4.7 без обвязки сам предлагает тесты, запускает pytest, видит регрессии в выводе. Обвязка не добавляет capability — она дублирует то, что модель уже делает.
  2. BDD/Gherkin осмысленен только при наличии product-аналитиков, пишущих сценарии на языке домена. Без них Gherkin = бюрократия.
  3. Мета-фреймворк с фазами «specify → tests-first → implement → green» — это repackage BMAD/SpecKit anti-pattern, который уже отвергнут в research'е (раздел 9 Harnesses_gude.md).
- **Альтернатива**: `.claude/rules/testing.md` — короткий инвариант, читается перед каждой code-сессией (через Skill auto-invoke по контексту или просто как часть проектного CLAUDE.md).

## ADR-004 — Devlog format: index.json (auto) + entries/*.md (truth)

- **Контекст**: нужен журнал решений / прогресса между сессиями. Два writable источника = рассинхрон.
- **Решение**:
  - `entries/YYYY/NNNN-slug.md` — единственный source of truth. Markdown с YAML frontmatter (формат skill'ов из anthropics/skills).
  - `index.json` — производный, **никогда не правится руками**. Регенерируется из `entries/**/*.md` через `rebuild-index.py`.
- **Решённые проблемы**:
  - **id-конфликты**: `rebuild-index.py` валидирует уникальность числовых id, бросает ошибку при дубле.
  - **slug-разнобой**: детерминированный slugify (lowercase + alnum + `-` collapse + truncate).
  - **архивация**: каталог `entries/YYYY/` — естественная партиция по году.
  - **«index в JSON»**: удовлетворено — index машиночитаем для скриптов и UI.
- **Артефакты**: `.claude/devlog/{rebuild-index.py, index.json, entries/}`.
- **Use cases**:
  - `rebuild-index.py` — pre-commit или manual после добавления entry.
  - Чтение из index — `claude-progress` аналог из Effective Harnesses (RESEARCH-AUDIT.md C15), но без bespoke txt-формата.

## ADR-007 — Built-ins-first revisited: retire 6 skills + 2 agents как дубликаты

- **Дата**: 2026-05-09
- **Контекст**: Stage 2 battle-test на FastApi-Base + критический ревью пользователя выявили **системное нарушение foundational principle** в v0.1 expansion коммите (76c4f37). Я создал 7 user-triggered skills и пять custom agents без верификации built-in каталога Claude Code 2.1.x. Поверхностный bug (`AskUserQuestion` несовместим с `context: fork`, фикс был в ADR-006) вёл к более глубокому: половина skills вообще не должна была существовать.
- **Решение**: удалить из harness'а компоненты, дублирующие built-ins или bundled skills:
  - `skills/onboard/` → дубликат `/init` (NEW project bootstrap CLAUDE.md) + `/team-onboarding` (v2.1.101+, ramp-up для team handoff) + `/memory` (refine existing CLAUDE.md).
  - `skills/review/` → дубликат built-in `/review`. Для cloud multi-agent — shell `claude ultrareview`.
  - `skills/debug-loop/` → дубликат bundled `/debug`.
  - `skills/refactor/` → тонкий wrapper («use Plan to design») без value над прямым `/plan` или Shift+Tab×2.
  - `skills/create-skill/` → дубликат canonical `skill-creator` из marketplace `anthropics/skills`. Установка через `claude plugin install skill-creator@anthropics-skills` на user-level.
  - `skills/spawn-agent/` → low-value wrapper над manual edit `.claude/agents/<name>.md` + built-in `/agents` view. Создание агентов остаётся через `meta-creator` subagent (вызываемый напрямую через Task tool).
  - `agents/onboarding-agent.md` → отзывается вместе с `/onboard` skill.
  - `agents/debug-loop.md` → отзывается вместе с `/debug-loop` skill.
- **Финальный inventory harness'а**:
  - `.claude/skills/`: только `devlog` (уникальная schema + auto-index) и `plan-deliverable` (deliverable-driven contract без декомпозиции — уникальный подход не покрыт built-ins).
  - `.claude/agents/`: `deliverable-planner`, `code-reviewer`, `meta-creator`. `code-reviewer` остаётся marginally — даёт structured JSON output, отличный от built-in `/review` UX.
- **Обоснование**:
  1. Foundational principle (zafiksirován в `.claude/CLAUDE.md`): «если Opus 4.7 уже умеет X нативно — компонент не добавляется». Built-ins покрывают onboarding/review/debug/refactor нативно лучше. Каждый дубликат — assumption «модель/built-ins не справятся», которая не подтверждается.
  2. Built-ins (`/init`, `/team-onboarding`, `/review`, `/debug`, `/simplify`, `/plan`, `/memory`) maintained Anthropic'ом, evolve вместе с CLI. Наши копии — frozen, drift гарантирован.
  3. Контекст-бюджет: 7 skill descriptions всегда грузятся в системный промпт. Каждый дубликат отъедает character budget без выигрыша.
  4. Language preference (которая всплыла в pilot): Opus 4.7 нативно отвечает на языке запроса. Не нужен skill-уровень для language directive — только опциональная строка `Working language: <язык>` в проектном CLAUDE.md, если важно зафиксировать durably.
- **ADR-006 superseded**: проблема, которую ADR-006 решал (mandatory interview в `/onboard`), становится moot вместе с удалением `/onboard`. Built-in `/init` и `/team-onboarding` сами решают что и как спрашивать; harness не вмешивается.
- **Альтернатива (отвергнута)**: оставить наши skills как «harness-flavored alternatives» с добавленной project-spec логикой. Отвергнута: (а) project-spec логика принадлежит проектному CLAUDE.md, не harness skills; (б) maintaining двух поверхностей (наша + built-in) — anti-pattern foundational principle.
- **Запрет на возврат**: воссоздавать `.claude/skills/onboard|review|debug-loop|refactor|create-skill|spawn-agent` или `.claude/agents/onboarding-agent|debug-loop` — запрещено без пересмотра этого ADR. Перед добавлением любого нового skill/agent — обязательная проверка built-in/bundled каталога через `https://code.claude.com/docs/en/commands`.
- **Урок процесса**: для любого нового harness-компонента — WebFetch built-in catalog ДО реализации. Foundational principle проверяется не в обзоре, а в моменте предложения компонента.

## ADR-009 — Retire sandbox baseline (workflow friction > security gain)

- **Дата**: 2026-05-09
- **Контекст**: ADR-008 включал sandbox в harness baseline ссылаясь на canonical Anthropic recommendation («84% reduction in permission prompts»). Эмпирическое использование в этой же сессии показало:
  1. Sandbox активировался автоматически после ConfigChange hook reload и заблокировал writes в pilot-проекты (`/home/nikita/PROJECTS/FastApi-Base/`, `/home/nikita/PROJECTS/AI_analyst_migration_battletest/`) — это desired security posture в abstract, но конкретно для harness'а где Stage 2 install требует cross-project deploy — это блокировало работу.
  2. `/tmp` стал read-only до явного добавления в `filesystem.allowWrite`, что сломало 11/11 hook smoke tests (которые пишут payload в `/tmp`). Пришлось добавлять `/tmp`, `/var/tmp`, `~/.cache` — это де-факто откатывает значимую часть isolation'а.
  3. Bubblewrap создавал артефакты в cwd (character device `.bash_profile` с owner `nobody`, fake overlay для dotfiles), что ломало `git add -A` в harness репо.
  4. Network allowlist требует maintenance per-project: каждый новый dev domain (Slack, Sentry, internal API, registry mirror) — explicit add. Approval-fatigue переезжает с permission prompts на «забыл добавить в allowedDomains».
- **Решение**: **полностью удалить** `sandbox` блок из harness baseline `.claude/settings.json`. Boundary policy держится через:
  - `permissions.{allow,ask,deny}` whitelist (106/23/13 правил, см. devlog #3);
  - проектные hooks (`secret-scan.sh`, `dangerous-cmd-block.sh`);
  - стандартный auto-mode classifier Claude Code.
- **Обоснование**:
  1. **Foundational principle инверсия**: «sandbox baseline» был добавлен по canonical recommendation Anthropic, но эмпирически добавил friction > чем убрал. Под Opus 4.7 минимум обвязки = больше продуктивности; sandbox оказался обвязкой, которая мешает, не помогает в текущем рабочем контексте.
  2. **Use case mismatch**: Anthropic sandboxing рекомендация целевая для untrusted code execution, experimental scripts, third-party agent workflows. Harness используется для разработки между доверенными проектами одного владельца — модель угроз другая.
  3. **Defense-in-depth остаётся**: secret-scan hook (PreToolUse:Edit/Write) блокирует writes секретов; dangerous-cmd-block hook (PreToolUse:Bash) блокирует destructive команды; permissions.deny запрещает чтение `~/.ssh`, `~/.env`, etc. на app-level.
  4. **Per-project escape hatch**: если конкретный проект требует sandbox (например, тестирование untrusted package), включается через `settings.local.json` (gitignored) — без правки harness baseline.
- **Что НЕ меняется** в harness'е:
  - SessionStart hook (`session-context.sh`) — остаётся, не связан с sandbox.
  - Effort guidance в meta-CLAUDE.md — остаётся.
  - Permission whitelist (106 allow / 23 ask / 13 deny) — остаётся, primary boundary.
  - `secret-scan.sh`, `dangerous-cmd-block.sh` — остаются.
- **Supersedes**: ADR-008 раздел про sandbox (1-й из 3 пунктов). SessionStart hook и effort guidance из ADR-008 остаются in force.
- **Урок процесса**: canonical recommendation из docs не = «обязательно для нашего harness'а». Каждое заимствование должно проходить foundational principle stress-test В РАБОЧЕМ КОНТЕКСТЕ, не только в обзоре статьи. Эмпирика > рекомендации, когда рекомендация конфликтует с реальным workflow.
- **Запрет на возврат**: возвращать sandbox в harness baseline (`.claude/settings.json` в репо) запрещено без empirical evidence что workflow friction исчез или модель угроз изменилась. Per-project sandbox в `settings.local.json` — допустимо.

## ADR-010 — Trim observability hooks + redundant skill (foundational principle inversion)

- **Дата**: 2026-05-10
- **Контекст**: Аудит harness'а под Opus 4.7 best practices ([cite](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code): «spawns fewer subagents by default», «calls tools less often and reasons more», «response length is calibrated to task complexity») выявил 6 компонентов harness'а, которые кодируют assumptions, уже снятые моделью или внешними механизмами.
- **Решение**: удалить 5 hooks + 1 skill, упростить SessionStart hook.
  - `.claude/hooks/block-shallow-agent-spawn.sh` — блокирует `Agent` с prompt < 100 chars. Opus 4.7 «spawns fewer subagents by default» и брифует их thoughtfully нативно (system prompt уже содержит «Brief the agent like a smart colleague»). Хук = dead weight + блокирует валидные краткие prompts.
  - `.claude/hooks/stop-recovery.sh` — пишет error reason в `MEMORY.md` в **корне репо**, что засоряет user-level memory space (`~/.claude/projects/.../memory/`); transcript и логи уже содержат причину. **Use-case scope** (clarification 2026-05-10): удаление обосновано тем, что harness используется в **интерактивных** TUI-сессиях, где Stop виден сразу и читается из transcript'а. При появлении фоновых сценариев (`claude --print` в cron, daemon-like agents) — re-evaluate через триггер из meta-CLAUDE.md «Re-evaluation triggers».
  - `.claude/hooks/env-reload.sh` — pure observability, **только логирует .envrc presence, ничего не делает**. Нулевая ценность; модель сама прочитает .envrc если нужно.
  - `.claude/hooks/denied-log.sh` — append-only лог permission denials; permission UI в TUI уже видим в реальном времени.
  - `.claude/hooks/config-audit.sh` — append-only лог config changes; `git log .claude/settings.json` даёт то же.
  - `.claude/skills/plan-deliverable/` — **дубликат** `deliverable-planner` agent'а (тот же 4-секционный контракт Goal/AC/Verification/Out-of-scope, та же anti-decomp посылка). Single-source violation.
  - `.claude/hooks/session-context.sh` — упрощён до devlog-only injection (58 → 22 строки). Git context уже инжектится Claude Code в системный prompt блоком `gitStatus`; harness-уникальное — только last devlog filename.
- **Что НЕ удаляется**:
  - `secret-scan.sh`, `dangerous-cmd-block.sh` — real security boundaries (компенсируют отсутствие sandbox per ADR-009).
  - `auto-format.sh` — opt-in verification signal (passive: ничего не делает если нет `.claude/format.sh` в проекте).
  - `session-context.sh` — slim form, devlog reference уникален.
- **Обоснование**:
  1. **Foundational principle прямо**: компонент кодирует assumption «модель не умеет X»; Opus 4.7 умеет X нативно → удалить (ADR-007 уже применил тот же критерий к skills/agents).
  2. **Цитата Anthropic**: «It spawns fewer subagents by default» — `block-shallow-agent-spawn.sh` лечит проблему которой больше нет.
  3. **Memory namespace hygiene**: `stop-recovery.sh` пишет в `MEMORY.md` в корне рабочего дерева, что (а) загрязняет user-space (б) конфликтует с official auto-memory.
  4. **Observability ROI**: `denied-log`, `config-audit`, `env-reload` — лог-файлы которые не читаются. Если debugging hooks будет нужен — temporarily активируется через `settings.local.json`.
  5. **Single-source-of-truth**: `plan-deliverable` skill и `deliverable-planner` agent — две поверхности одного контракта; agent (auto-invoke) сильнее skill (manual `/plan-deliverable`), оставлен agent.
- **Эффект**: hooks 9 → 4 (–56%); skills 2 → 1; settings.json hook events 7 → 3; ~250 строк кода удалены; системный prompt каждой сессии теряет 5 hook-описаний.
- **Запрет на возврат**: воссоздавать любой из удалённых компонентов запрещено без empirical evidence что Opus 4.7 регрессировал на соответствующей capability. Per-project debugging-hooks через `settings.local.json` — допустимо.

## ADR-011 — Retire code-reviewer agent (duplicates /review under Opus 4.7)

- **Дата**: 2026-05-10
- **Контекст**: `code-reviewer` создан в ADR-001 (v0.1) с marginally-уникальным аргументом: structured JSON output отличался от built-in `/review` UX. Pre-Opus-4.7 это имело вес — модель могла «забыть» формат вывода в long sessions. Под Opus 4.7 «response length is calibrated to task complexity» + main thread может вернуть JSON по explicit запросу, без agent-spawn round-trip.
- **Решение**: удалить `.claude/agents/code-reviewer.md`. Diff-review остаётся через built-in `/review` (или main thread + `git diff`).
- **Обоснование**:
  1. **Foundational principle**: «fewer subagents by default» (Opus 4.7 cite). Custom agent дублирует built-in capability, отнимает context budget системного prompt'а (description + tools list).
  2. **Built-ins-first invariant** (ADR-007): built-in `/review` evolved Anthropic'ом, наша копия frozen. Drift гарантирован.
  3. **JSON output не уникальная capability**: main thread по запросу вернёт ту же JSON структуру (`critical/warnings/suggestions`); workflow тривиален (3 шага).
  4. **Глубокое review**: `claude ultrareview` (cloud-hosted multi-agent) уже покрывает out-of-session случай.
- **Альтернатива (отвергнута)**: оставить как «harness-flavored review с fixed JSON schema». Отвергнута: schema из 14 строк markdown — не ценность; built-in эволюционирует, мы не успеваем; main thread может выполнить роль read-only reviewer без spawn.
- **Эффект**: agents 3 → 2 (`deliverable-planner`, `meta-creator`).
- **Запрет на возврат**: воссоздавать `code-reviewer` agent запрещено без пересмотра. Если понадобится structured review — напрямую попросить main thread вернуть JSON.

## ADR-012 — Trim meta-CLAUDE.md (decision tree + flow table → ADR refs)

- **Дата**: 2026-05-10
- **Контекст**: meta-CLAUDE.md дорос до 127 строк, частично дублируя ADR'ы (decision tree `command|skill|subagent|hook|nothing` — модель решает по контексту нативно; built-in flow table — повторение ADR-007). Системный prompt каждой сессии грузит CLAUDE.md → лишние строки = постоянный context-tax.
- **Решение**: trim 127 → ~80 строк.
  - **Foundational principle переехал наверх** — это центр, должен читаться первым. Добавлены 3 цитаты Anthropic про Opus 4.7 как evidence.
  - **Decision tree** (`command|skill|subagent|hook|nothing`) удалён: Opus 4.7 решает по контексту нативно; критерий «компонент кодирует assumption?» уже в foundational principle.
  - **Built-in flow table** (9 строк): сжато до референса к ADR-007.
  - **Reference materials**: 14 → 8 строк, обновлены под актуальный inventory (4 hooks, 2 agents, 1 skill).
  - **Boundaries posture**: 8 → 3 строки + ссылка на ADR-009.
- **Обоснование**:
  1. **Foundational principle применён к самому CLAUDE.md**: «не лить мегарайлзы — контекст-бюджет public good» (anti-pattern уже зафиксирован в самом файле).
  2. **DRY**: ADR'ы — source of truth для decisions; CLAUDE.md ссылается, не повторяет.
  3. **Opus 4.7 native ranking**: с less prompt-engineering модель работает лучше на agentic-задачах.
- **Что НЕ trim'нуто**:
  - **API constraint** — external constraint, модель не знает по умолчанию.
  - **Built-ins first** — каноничный инвариант, постоянно проверяется.
  - **First-session contract** — built-in `/init` не знает наших инвариантов.
  - **Effort defaults** — model-tuning гайд.
  - **Anti-patterns** — quick reference.
- **Запрет на возврат**: возвращать decision tree / built-in flow table в CLAUDE.md запрещено — они существуют в HARNESS-DECISIONS.md и ADR-007.

## ADR-013 — Cross-session memory: auto-memory canonical, no claude-mem / MCP memory

- **Дата**: 2026-05-10
- **Контекст**: Cross-session memory — единственная capability, где Opus 4.7 не справляется in-session нативно (контекст обрывается между сессиями). Возникает периодический соблазн поставить `claude-mem` (community plugin) или MCP memory server в baseline harness'а. Auto-memory в `~/.claude/projects/<slug>/memory/` уже работает: `MEMORY.md` как индекс + типизированные файлы (user/feedback/project/reference) + автозагрузка `MEMORY.md` в каждую сессию + типизированные правила что писать/не писать (см. user-level harness instructions «auto memory»).
- **Решение**: cross-session memory покрыта **auto-memory**. `claude-mem`, локальный harness-mem layer, MCP memory server в `.claude/settings.json` baseline — НЕ добавляются.
- **Обоснование**:
  1. **API constraint**: auto-memory работает на CLI-подписке без `ANTHROPIC_API_KEY`. MCP memory servers, требующие API-key, отпадают по тому же инварианту, что и managed-agents (ADR-005).
  2. **Типизация уже есть**: разделение user/feedback/project/reference даёт ту же сегментацию, что dreams/scope в managed-agents API. Single-user harness не нуждается в RO/RW ACL поверх (ADR-005 отверг это для memory-stores).
  3. **Dual-write = drift**: параллельный slot (auto-memory + claude-mem) создаст ту же проблему, что `index.json` vs `entries/*.md` в ADR-004. Single source of truth — auto-memory.
  4. **Foundational principle**: компонент кодирует assumption «модель не помнит между сессиями»; assumption истинна, но **уже снята** существующим механизмом (auto-memory). Дубликат запрещён тем же критерием, что built-ins-first.
- **Альтернатива (отвергнута)**: `claude-mem` plugin как user-level дополнение (без harness baseline). Отвергнута: даже user-level установка создаёт два writable пути для memory; конфликт неизбежен при auto-save в обоих местах.
- **Запрет на возврат**: ставить `claude-mem` / MCP memory server в harness `.claude/settings.json` запрещено без empirical evidence что auto-memory недостаточна для конкретного классa задач (не «было бы удобнее»). Per-project MCP memory через `settings.local.json` для специфического use-case (например, persistent vector store для RAG-проекта) — допустимо.

## ADR-014 — Built-in `/init` не интервьюирует — это by design под Opus 4.7

- **Дата**: 2026-05-10
- **Контекст**: ADR-007 закрыл ADR-006 как moot, аргументируя что built-in `/init` и `/team-onboarding` «сами решают что и как спрашивать». Это был **inference из docs**, не верифицированная эмпирика. Прогон POC в `/tmp/init-poc/` (Claude Code 2.1.138, чистый Python-проект с pyproject/src/tests/README, изолированный git repo, `claude --print "/init"`) показал: built-in `/init` **не задаёт ни одного вопроса** и пишет CLAUDE.md на основе repo-state на английском по default'у. Промежуточная реакция: восстановить ADR-006 invariant в форме «mandatory AskUserQuestion после /init» в meta-CLAUDE.md. **Эта реакция была неверной** — пользователь напрямую возразил: формальный upfront-контракт (язык / deliverable / verification) не является обязательным и важным в agentic-разработке под Opus 4.7. Контракт строится **итеративно из conversation**, не из upfront-интервью.
- **Решение**: **no action**. ADR-007 в части закрытия ADR-006 остаётся в силе. Empirical fact (`/init` не интервьюирует) фиксируется как evidence для будущих re-evaluation, **не превращается в invariant**. Расширение раздела `First-session contract` в meta-CLAUDE.md, добавленное в промежуточной попытке (mandatory AskUserQuestion), **откачено**; раздел остаётся как soft guidance, явно помеченный «не invariant».
- **Что НЕ делается**:
  - НЕ возрождается `.claude/skills/onboard/` или `onboarding-agent` — ADR-007 в этой части в силе.
  - НЕ вводится «mandatory AskUserQuestion после /init» в meta-CLAUDE.md — попытка нарушила foundational principle (кодировала assumption «модель не построит контракт итеративно» в момент, когда пользователь подтверждает что Opus 4.7 строит).
  - НЕ переписывается ADR-006/007 — их история и логика остаются как есть; этот ADR — point-in-time evidence, не пересмотр.
- **Обоснование (final)**:
  1. **Single-incident observation**: один эмпирический случай (FastApi-Base battle-test, ADR-006 контекст), и пользователь явно говорит что не считает это критичным под Opus 4.7. Single incident → не invariant.
  2. **Foundational principle direct**: invariant «mandatory interview» кодирует assumption «без формального контракта проектная работа не запустится». Под Opus 4.7 — assumption ложна; контракт-куски (язык / deliverable / verification) появляются органически в первой релевантной задаче и фиксируются по факту.
  3. **Эмпирический fact ценен сам по себе**: знание «built-in /init не интервьюирует» — reference для будущих споров. Если когда-то в Claude 5.x `/init` начнёт интервьюировать или появится подтверждённый pain-point — этот transcript будет точкой сравнения.
- **Supersedes**: ничего. ADR-007 в части закрытия ADR-006 — в силе.
- **Запрет на возврат**: возвращать «mandatory AskUserQuestion после /init» в meta-CLAUDE.md запрещено без empirical evidence что Opus 4.7 регулярно проигрывает контракт-куски в agentic workflow И подтверждённого user-feedback'а что это критично.
- **Эвиденс-точка** (transcript 2026-05-10, Claude Code 2.1.138, fixture `/tmp/init-poc/`):
  - **Команда**: `cd /tmp/init-poc && claude --print "/init"`
  - **Полный output** (1 строка): «Создал `CLAUDE.md` с кратким описанием проекта (минимальный FastAPI на `src/main.py`), командами для тестов/линта/запуска и заметкой о том, что `pytest` нужно запускать из корня репозитория…»
  - **Сгенерированный CLAUDE.md** содержит секции: `## Project`, `## Commands`, `## Layout note`. На английском. **Не содержит**: language preference, target deliverable, verification gate as binding contract — что **OK** под user-confirmed agentic workflow.
  - **AskUserQuestion вызовов**: 0.
- **Урок процесса**: расширение правила ADR-007 — проверять не только existence, но и behavior built-in'а через POC. Любой аргумент формы «built-in покрывает X» требует transcript-доказательства. Single-incident observation не превращается в invariant без подтверждения что промах повторяется.

## ADR-15 — Retire ADR-005 implementation: managed-memory port-over распределён по built-in примитивам

- **Дата**: 2026-05-10
- **Контекст**: ADR-005 (2026-05-09) фиксировал «берём три» из managed Memory/Dreams: `_manifest.yml` per-store, PreToolUse exit 2 на RO-store, SessionStart hook со списком stores. Через сутки code-review harness'а другим агентом обнаружил: ни одна из трёх капабилити не материализована. `_manifest.yml` отсутствует, `secret-scan.sh` блокирует write по pattern'ам секретов (а не по store ACL), `session-context.sh` отдаёт только last devlog filename. За эти же сутки приняты ADR-013 (auto-memory canonical) и ADR-014 (built-in `/init` не интервьюирует — by design), а в обсуждении возникло предложение skill/command «warm-context» для прогрева контекста на старте сессии. Stress-test предложения через foundational principle показал, что три капабилити ADR-005 уже распределены по built-in механизмам, а warm-context не имеет эмпирических оснований.
- **Решение**: ADR-005 в части implementation **retire**. ADR-15 фиксирует mapping капабилити на существующие built-in примитивы и двойной запрет на возврат.
- **Mapping**:
  | ADR-005 capability                  | Покрытие в текущем harness'е                                                                                                |
  | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
  | `_manifest.yml` + RO/RW scope       | `.claude/rules/*.md` auto-loaded built-in'ом как project instructions (verified: `testing.md` в системном prompt'е этой сессии без явного `Read`) + auto-memory типизация (user/feedback/project/reference) — type-segmentation уже даётся механизмом |
  | PreToolUse exit 2 на RO-store       | Не нужен: `rules/` редактирует человек, не задачи модели; sensitive paths закрыты `permissions.deny` (`.env`, `.ssh`, `credentials.json`, `*.pem`, `*.key`) + `secret-scan.sh` |
  | SessionStart hook со списком stores | Active inventory section в HARNESS-DECISIONS.md + Reference materials в meta-CLAUDE.md (документированный pattern); `session-context.sh` инжектит harness-уникальное (last devlog), `gitStatus` Claude Code инжектит сам (verified в этой сессии) |
- **Обоснование**:
  1. **Foundational principle direct (ADR-005 implementation)**: компонент кодировал assumption «нужен централизованный store registry с ACL»; в single-user harness'е без параллельных subagent-writes — assumption ложна. Type-segmentation auto-memory + auto-load `.claude/rules/` покрывают use-case дешевле, без `_manifest.yml` для одного store.
  2. **Foundational principle (warm-context)**: skill/command для прогрева кодирует assumption «модель не знает где найти контекст». Под Opus 4.7 — false: 5 источников auto-loaded в системный prompt (CLAUDE.md, `.claude/rules/*.md`, `MEMORY.md`, `gitStatus`, last devlog filename), модель «calls tools less often and reasons more», читает on demand. Эмпирических промахов нет → не добавляется. Slash command как тонкий prompt-template — допустим только при подтверждённой повторяющейся потребности.
  3. **Single source of truth (per ADR-013)**: дублирование memory-путей создаёт drift; managed-memory port-over конкурирует с auto-memory.
- **Запрет на возврат (двойной)**:
  1. Воссоздавать локальную имплементацию managed Memory/Dreams (`_manifest.yml`, store-ACL hooks, dreamer pipelines) — **запрещено** без empirical evidence что built-in auto-load + auto-memory + `permissions.deny` **недостаточны** для конкретного класса задач (не «было бы аккуратнее»).
  2. Создавать skill/command типа `warm-context` / `recall` / `prime-session` — **запрещено** без empirical evidence что (а) auto-loaded источники недостаточны и (б) prompt «дай overview» не покрывает потребность. Slash command как тонкий prompt-template — допустим при подтверждённой повторяющейся потребности.
- **Supersedes**: ADR-005 в части implementation («берём три»). Out-of-scope managed-agents API остаётся (ADR-005 был корректен в этой части).
- **Урок процесса**: ADR-005 принят на основании POC mapping'а в `/tmp/memory-poc/` — концепции прогнаны end-to-end и эмпирически валидны как технические решения. Но переход от «работает» к baseline harness'а пропустил вопрос «**нужно ли в свете уже работающих built-in примитивов?**». Через сутки два встречных ADR (013 + 014) сделали implementation редундантной. Урок для будущих расширений: stress-test «что уже покрывает это в стеке?» обязателен **до** фиксации «берём». ADR-15 — пример ретроактивного применения этого правила.

## ADR-016 — Self-описывающие skills как anti-pattern + higher-order orchestration refinement + pilot validation pattern

- **Дата**: 2026-05-10
- **Контекст**: Сессия 2026-05-10 расширяла harness компонентами для multi-agent дисциплины. Среди созданного был `.claude/skills/meta-orchestrator/SKILL.md` — позиционировался как «active environment-configurator» с триггер-словами для auto-discovery. Skill auto-loaded в main thread context и описывал... самого main thread'а («Main thread = meta-orchestrator. Owns задачу end-to-end…»). Пользователь explicitly указал: **«meta-orchestrator — это ты, с кем я общаюсь»** — main thread **является** meta-orchestrator'ом нативно через CLAUDE.md + system prompt + conversation context. Skill дублировал meta-CLAUDE.md о собственной роли модели; это попытка configure self вместо configure environment for inner executors.

  В той же сессии: создан `docs/MULTI-AGENT-BASELINE.md` (legitimate external on-demand reference), 4 правки meta-CLAUDE.md (Foundational principle higher-order refinement + Sub-agent spawn policy + Self-evolution + Reference materials), pilot test на `~/PROJECTS/FastApi-Base` нашёл existing harness bug в `session-context.sh` (`set -euo pipefail` + empty glob = exit 2 на проектах с пустым `devlog/entries/`).

- **Решение**:
  1. **Retire** `.claude/skills/meta-orchestrator/SKILL.md` (создан и удалён в той же сессии). Зафиксировать **self-описывающий skill** как anti-pattern.
  2. **Закрепить higher-order orchestration refinement** в `.claude/CLAUDE.md` Foundational principle: skill / agent / hook как **environment configurator для inner executors** (subagents, Claude Code daemon) — допустимы; как **duplicate-of-built-in capability** или **self-description main thread'а** — anti-pattern.
  3. Сохранить `docs/MULTI-AGENT-BASELINE.md` как on-demand reference (read-by-main-thread по необходимости, не auto-loaded в системный prompt).
  4. **Bugfix** `session-context.sh`: добавить `|| true` после command substitution с pipeline для безопасности под `set -euo pipefail` на empty-glob `ls`.
  5. **Pilot validation pattern** установлен как методологический guard: backup → remove retired components → sync new state → validate static (syntax, scripts) → validate runtime (`claude --print` skill/agent discovery, `claude agents` inventory check, hook smoke tests).

- **Обоснование**:
  1. **Foundational principle direct**: компонент кодировал assumption «модель забудет свою роль без skill-напоминания» — assumption ложна. Opus 4.7 нативно держит role identification из CLAUDE.md + system prompt + conversation context. Skill дублировал meta-CLAUDE.md и был frozen — drift гарантирован.
  2. **Mental model boundary** (новое, эта сессия): main thread = meta-orchestrator (это я, кто общается с пользователем). Skills / agents / hooks конфигурируют **окружение для inner executors**, не для самого main thread'а. **Action-skills** (`devlog` — конкретная операция записи) легитимны; **self-description-skills** (повторяют CLAUDE.md о роли main thread'а) — anti-pattern с тем же статусом, что duplicate-of-built-in (ADR-007).
  3. **Pilot validation value**: migration path обнаружил real bug в `session-context.sh`, не показавшийся бы в harness self-tests (где devlog непустой). Эмпирическое доказательство что harness components, влияющие на runtime, нужно тестировать на pilot deployments с разной project state.

- **Что НЕ делается / Что НЕ меняется**:
  - НЕ retire `docs/MULTI-AGENT-BASELINE.md` — legitimate external reference, читается main thread'ом on-demand, не self-loaded в системный prompt.
  - НЕ retire higher-order orchestration refinement в Foundational principle — это правило про **создание components для inner executors**, не self-description.
  - НЕ retire `Sub-agent spawn policy` (compact form в meta-CLAUDE.md) — kernel-level invariant.

- **Альтернатива (отвергнута)**: оставить skill, repurpose как «pre-delegation checklist» (auto-trigger перед `Agent` tool call). Отвергнута: (а) Opus 4.7 нативно делает pre-delegation thinking когда задача — кандидат на multi-agent (Anthropic «calls tools less often and reasons more», «devises ways to verify own outputs»); (б) checklist дублировал бы `docs/MULTI-AGENT-BASELINE.md` §10; (в) даже как pre-delegation checklist это всё равно self-описание (skill говорит main thread'у как делать main thread thing).

- **Запрет на возврат**:
  1. Воссоздавать `.claude/skills/meta-orchestrator/` или любой self-описывающий skill (повторяющий CLAUDE.md о роли main thread'а) — **запрещено** без empirical evidence что Opus 4.7 регрессировал на role identification (transcript, repro, не «было бы аккуратнее»).
  2. Перед созданием любого нового skill — обязательная проверка boundary: компонент конфигурирует **окружение для inner executors** (action-skill, например `/devlog` → конкретная операция записи) или **описывает main thread сам себе** (self-description, anti-pattern)? Только первое допустимо.
  3. `.claude/hooks/session-context.sh` `|| true` fix не откатывать без замены на эквивалентную защиту от empty-glob exit 2.

- **Эвидентс-точки** (сессия 2026-05-10):
  - `claude --print` в pilot context (FastApi-Base, до удаления skill): `meta-orchestrator` listed первым в available skills response — auto-loaded работал, дубликат подтверждён.
  - `claude agents` в pilot после migration: 6 active agents (2 project: `deliverable-planner`, `meta-creator` + 4 built-in: `Explore`, `Plan`, `general-purpose`, `statusline-setup`); `code-reviewer` correctly absent (ADR-011 retire validated).
  - Hook bugfix smoke test (3/3 cases pass): harness with entries → JSON output, pilot empty → silent exit 0, pilot 1 entry → JSON output.
  - User observation: «meta-orchestrator — это ты, с кем я общаюсь… Сейчас кажется, что ты немного продублировал Skill meta-orchestrator и .claude/CLAUDE.md» — выявил duplication.

- **Урок процесса**: перед любым новым skill/agent — boundary check «environment configurator для inner executors» vs «self-description main thread'а». Pilot test обязателен для любого harness расширения, влияющего на runtime (skills, hooks, settings, CLAUDE.md invariants).

- **Supersedes**: ничего. Дополняет ADR-007 (built-ins-first) и ADR-010 (anti-spam observability hooks) новой категорией anti-pattern boundary.

## ADR-017 — Project documentation contract: bootstrap skill + always-loaded discipline rule

- **Дата**: 2026-05-10

- **Контекст**: До этого ADR harness покрывал meta-уровень (foundational principle, multi-agent baseline, testing invariants, devlog) и не имел операционализированного pattern'а для **проектной документации** в проектах, использующих harness. Каждая новая сессия Claude в новом проекте стартует «холодно»: читает CLAUDE.md, дальше упирается в `find` / `grep` для понимания архитектуры, code layout, domain-терминов, conventions. Это (а) увеличивает token consumption per task, (б) даёт непредсказуемое quality между сессиями, (в) не масштабируется на команды >1 dev'а.

  Anthropic engineering blog («Claude Code: Best practices for agentic coding», «How Anthropic teams use Claude Code»), Anthropic Skills docs (`code.claude.com/docs/en/skills`), ADR pattern (Michael Nygard 2011), DDD ubiquitous language (Eric Evans), и convergent community patterns (12.x curated lists, reference impls shanraisshan/ChrisWiles/FlorianBruniaux, эссе boringbot/ofox.ai/blakecrosley) сходятся на canonical layout: `docs/ARCHITECTURE.md` + `docs/CODE-MAP.md` + `docs/GLOSSARY.md` + `docs/CONVENTIONS.md` + `docs/ADR/` + `docs/RUNBOOKS/`. Layout оптимизирован под cold-start AI-агента — каждая новая сессия Claude должна за <60 секунд понять проект из docs.

  Discipline поддержки docs (doc-with-code rule, append-only history, owner-of-record, glossary first-use) — recurring pattern в Anthropic internal practices и commonly cited best practices.

- **Решение**:
  1. **Add skill** `.claude/skills/project-docs-bootstrap/` — action-skill для bootstrap canonical layout. Содержит `SKILL.md` (workflow: audit → scope → generate → lock-in → verify) и `CONTRACT.md` (per-doc charter + skeletons).
  2. **Add rule** `.claude/rules/docs-discipline.md` — always-loaded invariant (6 правил: doc-with-code, CLAUDE.md as indexer, append-only history, owner+last-updated, glossary first-use, ADR for non-trivial).
  3. **Update meta-CLAUDE.md** Reference materials и Self-evolution — добавить ссылки на skill и rule.

- **Обоснование**:
  1. **Foundational principle pass**: компонент НЕ кодирует assumption «модель не умеет писать docs» — Opus 4.7 пишет хорошие docs если попросить. Компонент кодирует **environment configuration**: canonical layout + discipline rules — harness-level pattern, проявляющийся в **каждом** проекте, использующем harness. Это «environment configurator для inner executors» (ADR-016 boundary): inner executors здесь = Claude в будущих сессиях того же проекта + контрибьюторы команды. Это НЕ self-description main thread'а — skill оперирует на проектных файлах, не на role identification.
  2. **Built-ins coverage gap**: `/init` генерирует CLAUDE.md, но не canonical layout документации. `/team-onboarding` — про team handoff, не bootstrap docs/. `/memory` — про refine CLAUDE.md, не про docs/. Skill закрывает реальный gap.
  3. **Recurring pattern, not single incident** (ADR-014 boundary): convergent best practice multi-source-evidenced (Anthropic + DDD + ADR community + 6+ community curators в 12.x). Не «один раз промазали».
  4. **Skill vs slash command**: skill auto-invokes когда description matches (cold-start audit, /init follow-up), плюс остаётся explicit-invocable как `/project-docs-bootstrap`. Inline в CLAUDE.md съел бы context budget (workflow + per-doc charter + skeletons = ~400 строк).
  5. **Rule vs skill split**: bootstrap = одноразовая операция (skill); discipline = invariant ongoing (rule). Зеркалит существующий harness pattern — `skills/devlog` action + `rules/testing.md` invariant.

- **Что НЕ делается**:
  - НЕ форсируется при каждой сессии — skill auto-invoke только когда description matches contextual triggers.
  - НЕ подменяет `/init` — skill дополняет (post-/init bootstrap docs/).
  - НЕ навязывает PR template — proposed как option команде, не enforced.
  - НЕ создаются boilerplate docs без чтения кода — explicitly forbidden в SKILL.md.
  - НЕ автоматизируется Git hooks / CI checks для doc-with-code rule — эта автоматизация = отдельный ADR кандидат, slippery slope в overgrown harness.

- **Альтернатива (отвергнута)**: только rule (без skill), полагаясь на Opus 4.7 «derives layout from rule on the fly». Отвергнута: (а) Opus 4.7 без structured workflow склонен к быстрым shortcut'ам — генерит boilerplate без чтения кода, что самим SKILL.md anti-pattern'ом обозначено; (б) skeletons как опорные структуры — file artifact, неудобно держать только в rule; (в) skill даёт явную trigger surface (description), что улучшает discoverability vs implicit reading rule.

- **Альтернатива (отвергнута, 2)**: ограничиться 3 invariants в rule (doc-with-code, append-only, owner+last-updated), остальное — soft guidance. Отвергнута: 6 invariants выбраны как минимально достаточный набор для cold-start invariance (CLAUDE.md indexer защищает context budget, glossary first-use закрывает domain-language drift, ADR for non-trivial — главный механизм против знание-эрозии). Эмпирический cut от 8 к 6 — цена quality за каждый дополнительный rule (был cut «cold-start test квартально» как ритуал, не invariant; cut «CONVENTIONS as divergence» как self-evident из самого doc charter).

- **Запрет на возврат**:
  1. Удалять `.claude/skills/project-docs-bootstrap/` или `.claude/rules/docs-discipline.md` — запрещено без empirical evidence что (а) Opus 4.7 нативно создаёт canonical layout без skill, (б) discipline соблюдается без always-loaded rule.
  2. Расширять skill автоматизацией PR template, Git hooks, CI checks — запрещено без отдельного ADR.
  3. Раздувать rule сверх 6 правил — каждое новое правило → отдельное обоснование с evidence (single-incident → invariant запрещено per ADR-014).
  4. Держать одновременно SKILL.md + slash command как два entry points для одной операции — запрещено (skill сам invocable как `/project-docs-bootstrap`).

- **Supersedes**: ничего. Дополняет ADR-007 (built-ins-first → skill закрывает реальный gap, не дублирует built-in), ADR-010 (anti-spam → skill auto-invokes только когда description matches), ADR-014 (single incident → этот pattern recurring multi-source evidenced), ADR-016 (environment configurator boundary → skill конфигурирует project environment, не self).

## ADR-018 — Tighter ADR format (≤30 строк) + compact index, prospective

- **Дата**: 2026-05-10

- **Decision**: Future ADRs (018+) follow tight format ≤30 строк с 4 mandatory секциями: **Decision** (1-2 lines, императивно «Use X / Add Y / Retire Z»), **Why** (2-4 bullets), **Counter-evidence to revise** (concrete trigger что заставит пересмотреть), **Supersedes** (ADR refs или «ничего»). Optional: **Alternatives considered** (только когда non-obvious). Add compact index at top HARNESS-DECISIONS.md (1 line per ADR). Existing ADRs (002-017) остаются untouched per append-only history (`docs-discipline.md` rule 3).

- **Why**:
  - Existing format averages 50-100 строк/ADR; user pain explicit: «HARNESS-DECISIONS.md выглядит как наиболее мешающийся артефакт, раздут контекстом».
  - Conventional sections («Эвидентс-точки», «Урок процесса») часто filler без insight; cut в ADR-017 показал key info умещается в 4 секциях.
  - Compact index решает scan-cost без переписывания истории — index производный, может быть autogenerated при росте лога.
  - Prospective scope респектит append-only history rule, не создаёт прецедент edit existing ADRs.

- **Counter-evidence to revise**: ADR в tight формате 3+ раз окажется недостаточным для capture nuance ключевых решений (эмпирически — будущий контрибьютор / Claude в новой сессии не сможет понять «почему так» из ADR + git context) → расширить format mandatory sections либо вернуть Эвидентс-точки.

- **Alternatives considered**:
  - Mass-rewrite existing ADRs в tight format. Rejected: violates append-only history, теряет contextual nuance, high cost vs marginal gain.
  - Skip format change. Rejected: лог продолжит расти без bound, user pain не решается.
  - Auto-generate index script. Deferred: ручной index OK при 14 ADR'ах; автоматизировать когда ≥25 либо когда manual update пропущен 2+ раза.

- **Supersedes**: ничего. Дополняет ADR-014 (process discipline) prospectively — устанавливает format invariant для future ADRs.

## ADR-019 — Tiered harness benchmark methodology

- **Дата**: 2026-05-10

- **Decision**: Harness changes (skills, agents, hooks, rules, CLAUDE.md) валидируются перед commit через 3-tier benchmark. **Tier 0** = static checks (size budgets, frontmatter integrity, skill discovery, agent inventory, hook smoke, retired components guard). **Tier 1** = pilot project task suite на fixture (`~/PROJECTS/FastApi-Base` или dedicated). **Tier 2** = per-component evals (skill-creator description triggering для skills, prompt corpus для agents). Methodology, checks list, threshold, reporting format — `docs/HARNESS-BENCHMARK.md`. Tier 3 (blind compare) — ad-hoc, не required.

- **Why**:
  - Без benchmark harness changes валидируются только «выглядит правильно» — нарушает foundational principle при scaling.
  - Existing ad-hoc validation (ADR-016 pilot test FastApi-Base) сработала — поймала `session-context.sh` empty-glob bug — но не systematized; следующий harness change может пропустить аналогичный bug.
  - Tiered подход cheap-first: Tier 0 на каждый change (<10 sec), Tier 1 только для behavior-changing ADRs, Tier 2 при изменении component. Не all-or-nothing.
  - Quantitative metrics (tokens, turns, success rate) дают basis для empirical evidence в counter-evidence statements ADR'ов — закрывает loop «когда пересмотреть decision».

- **Counter-evidence to revise**: Tier 0 false-positive rate >20% (блокирует legitimate changes по ложной тревоге) → ослабить static checks либо вынести часть в warning-only. Tier 1 fixture systematically не ловит regressions, реально проявляющиеся в user проектах → пересмотреть task suite или fixture.

- **Alternatives considered**:
  - Полагаться на manual review (status quo). Rejected: doesn't scale, не воспроизводимо, человечески fallible.
  - Полная automation (CI gating). Deferred: harness CLI-only без CI infrastructure; manual run OK на текущем размере harness'а. См. roadmap в `HARNESS-BENCHMARK.md`.

- **Supersedes**: ничего. Systematizes ADR-016 pilot validation pattern (был ad-hoc, теперь tiered).

## ADR-020 — project-docs-bootstrap дополнения после first dogfood

- **Дата**: 2026-05-10

- **Decision**: Применены три fix-in-place после first dogfood `project-docs-bootstrap` на `~/PROJECTS/FastApi-Base` fixture (state на момент: 1 commit после `git init`, no `docs/`, есть `.claude/CLAUDE.md` + non-canonical `fastapi-skills/ARCHITECTURE_DECISION.md`):
  1. **SKILL.md Phase 1 step 1** — CLAUDE.md hierarchy search: root `CLAUDE.md` → `.claude/CLAUDE.md` (project-scoped) → `~/.claude/CLAUDE.md` (user fallback). Раньше предполагался только root.
  2. **SKILL.md Phase 1 step 5** — non-canonical docs detection (`find . -maxdepth 3 -name '*.md'` за пределами `docs/`) с migration plan: incorporate / preserve-with-reference / archive.
  3. **SKILL.md Phase 1 step 4** + **HARNESS-BENCHMARK.md fixture criteria** — bootstrap branch для no-git / 0 commits + relaxed «≥30 commits» к «git repo initialized + ≥10 commits soft»; tarball-style fixtures предлагают `git init` как cheap pre-step.

- **Why**:
  - First dogfood concretely обнаружил все три gap'а на real fixture (transcript-evidence, не speculation) — single empirical case оправдывает fix-in-place per ADR-014 «повторяющийся эмпирический промах» threshold (здесь все три на одном run, но reproducible).
  - Все три — environment configurator changes (расширение audit phase + benchmark criteria), не self-description main thread'а. ADR-016 boundary respected.
  - Fix-in-place vs full ADR — fix дешевле и не создаёт ADR proliferation; ADR-020 фиксирует решение для future-revision context.

- **Counter-evidence to revise**: Second dogfood (на другом fixture типа monorepo / non-Python / mature) обнаружит, что (a) hierarchy search недостаточен (например per-package CLAUDE.md в monorepo), (b) non-canonical migration plan слишком rigid, (c) «≥10 commits soft» всё ещё блокирует legitimate fixtures → расширить.

- **Supersedes**: ничего. Дополняет ADR-017 (skill foundation) и ADR-019 (benchmark methodology — refines fixture criteria через empirical evidence).

---

## Правила обновления этого лога

- **Format spec для ADR-018+** (per ADR-018): tight format ≤30 строк, 4 mandatory секции (Decision / Why / Counter-evidence to revise / Supersedes), optional Alternatives. ADR-002…017 — legacy формат, untouched.
- **Compact index** (top of file) обновляется при добавлении нового ADR — 1 line per ADR. Сейчас ручной; автоматизация — при ≥25 ADR'ах.
- **Append-only history**: ADR не редактируется после фиксации. Если решение пересмотрено — новый ADR с явным `Supersedes ADR-NNN` (legacy ADR'ы) или указанием в Supersedes section (tight ADR'ы).
- **Counter-evidence to revise** (для ADR-018+) или **Запрет на возврат** (для ADR-002…017) — якорь для будущих сессий: что заставит пересмотреть решение.
- `rebuild-index.py` запускается после каждого нового entry в devlog (не ADR-log).
