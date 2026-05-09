# Harness Decisions Log (ADR-style)

Канон архитектурных решений для мета-harness'а. Каждое решение фиксирует **что отвергнуто**, **почему**, **что вместо**.

## Foundational principle (будущий раздел 11.5 research'а v0.2)

> **Под Opus 4.7 минимум обвязки даёт максимум продуктивности.**
> Симптом «трудности в росте harness'а» — почти всегда признак того, что обвязка переросла полезность модели.

Этот принцип проверяется при каждом предложении расширить harness: если добавляемый компонент кодирует assumption «модель не умеет X», и Opus 4.7 уже умеет X нативно — компонент не добавляется. Прямая отсылка к Anthropic engineering: «every component in a harness encodes an assumption about what the model can't do on its own … those assumptions can quickly go stale» (RESEARCH-AUDIT.md, C4/C8).

---

## ADR-001 — v0.1 trimmed agent catalog

- **Дата**: 2026-05-09
- **Контекст**: research v0.1 (`docs/Harnesses_gude.md`) предлагает 8 кастом-субагентов; аудит выявил 3 DUPLICATE с built-ins.
- **Решение**: создан `.claude/agents/` из 5 файлов: deliverable-planner, code-reviewer, debug-loop, onboarding-agent, meta-creator. Не созданы: codebase-explorer (= built-in `Explore`), architect (= built-in `Plan`), orchestrator (= main session thread).
- **Последствия**: harness меньше; built-ins-first invariant зафиксирован в `.claude/CLAUDE.md`.
- **Коммит**: `515c190 feat(harness): materialize v0.1 trimmed agent catalog`.

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

## ADR-005 — Managed Memory/Dreams концепции: что берём, что нет

- **Дата**: 2026-05-09
- **Контекст**: Anthropic в апреле–мае 2026 анонсировал Memory stores и Dreams в составе Managed Agents — это **API-only** капабилити, в нашем CLI-харнессе на подписке нерелевантны (см. инвариант "API constraint" в `.claude/CLAUDE.md`). Однако концептуально (RO/RW scope, audit trail, mounted reference материал) идеи полезны и переносимы на CLI-примитивы. Прогон mapping-проекта на полигоне `/tmp/memory-poc/` с реальным `claude --print` показал: переносимы только три капабилити, конкретные реализации mapping'а к тому же сломаны (env vars `CLAUDE_TOOL_PATH/NAME/AGENT_NAME` не существуют — payload идёт через stdin JSON; settings.json требует обёртку `hooks: [{type:"command", ...}]`; `--print-paths` не существует; `yq` и `git filter-repo` отсутствуют в системе).
- **Решение**: из ~30 капабилити managed Memory/Dreams **берём три**, остальное **не берём**.
- **Берём** (под Phase 1 расширения `.claude/`, отдельным PR; концепции эмпирически прогнаны end-to-end):
  1. `_manifest.yml` per-store с полем `access: read_only|read_write`. Read-only де-факто уже есть — `.claude/rules/`.
  2. `PreToolUse` хук на `Edit|Write|MultiEdit` со stdin JSON parsing — блок `exit 2` на write в RO-store; stderr попадает в model context, модель сама объясняет блок пользователю (проверено).
  3. `SessionStart` хук со stdout JSON `{"additionalContext": "..."}` для списка stores и их scope-меток. Без мутации CLAUDE.md между маркерами.
- **Не берём**:
  - Managed Memory/Dreams API целиком (out of scope по API constraint).
  - Локальный `dreamer` subagent + `dream-batch.sh` + `dream-promote` workflow — конкурирует с уже работающими `remember`, devlog (ADR-004), auto memory `~/.claude/projects/.../memory/`; конфликтует с ADR-002 (multi-step pipeline).
  - Auto-commit на каждый Edit/Write в memory paths — гранулярные коммиты шумят; commit by intent через batch лучше.
  - Optimistic concurrency через SHA256-snapshot — нужна только при параллельных subagent-writes; на однопоточной сессии — лишний хук.
  - `git filter-repo` PII redaction wrapper — реактивно, по incident.
  - Mount injection в CLAUDE.md через `<!-- mounts:auto -->` маркеры — `additionalContext` через JSON output чище.
- **Запрет на возврат**: воссоздавать managed Memory/Dreams API локально (хук-фермы, dreamer pipeline, ACL-инфраструктура шире трёх пунктов выше) запрещено без пересмотра этого ADR.
- **Эвидens-точки** (зафиксированы в `~/.claude/projects/-tmp-memory-poc/` транскриптах от 2026-05-09):
  - реальная hook payload schema Claude Code 2.1.136 — stdin JSON: `{session_id, transcript_path, cwd, hook_event_name, tool_name, tool_input.file_path (АБСОЛЮТНЫЙ), tool_response, tool_use_id}`. Env vars `CLAUDE_TOOL_PATH/NAME/AGENT_NAME` НЕ существуют, payload идёт строго через stdin;
  - реальный `claude --print` end-to-end получает stderr от `exit 2` хука и сам сообщает пользователю причину блока («store помечен как read_only») — это и есть рабочий ACL UX, без API.

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

## ADR-006 — Onboarding всегда интервьюирует (SUPERSEDED by ADR-007)

> **Status**: superseded 2026-05-09 by ADR-007 (удаление `/onboard` skill и `onboarding-agent`). Сохранён как исторический контекст процесса.



- **Дата**: 2026-05-09
- **Контекст**: Stage 2 battle-test на pilot'е FastApi-Base показал, что `onboarding-agent` в auto-mode **пропустил интервью** на mature-проекте, сославшись на мета-CLAUDE.md guidance «trust the model, prefer action over questions». Результат: пилотный CLAUDE.md создан без подтверждения language preference (англоязычный вместо желаемого русского), без подтверждённого target deliverable, без согласования verification gate с разработчиком. Качество invariants было высоким (хороший fingerprint + encoded bans), но контракт-смысл потерян: документ описывал repo-state, а не договорённость с человеком.
- **Решение**: `onboarding-agent` **обязан** проводить интервью через `AskUserQuestion` в обоих режимах (NEW и MATURE), независимо от auto-mode и любой общей guidance «prefer action over questions». Минимум — 3 вопроса в одном вызове: язык общения, target deliverable, verification command. Опциональный 4-й — sensitive paths/commands. Никакие write-операции в проектный CLAUDE.md не выполняются до получения ответов.
- **Обоснование**:
  1. Onboarding — единственное место в harness'е, где questions ARE the action. CLAUDE.md создаётся как контракт с разработчиком; без его участия это интерпретация, а не контракт.
  2. Pilot не наследует user-level preferences (например, language) автоматически, если они зафиксированы в session-scope origin-сессии. Спросить — гарантирует корректность.
  3. Auto-mode «prefer action» — guidance общего случая. Onboarding — единственный explicit exception, где это правило не действует.
  4. Минимальное интервью (3 вопроса) занимает <1 минуты пользователя; пропущенный язык / неподтверждённый verification gate стоят дороже на каждой последующей сессии.
- **Альтернатива (отвергнута)**: Inferring preferences from repo-state (что фактически и сделал pilot). Отвергнута: agent не может знать, что «русский» — желаемый язык, если в коде/комментариях смесь EN/RU; и не может знать, какой verification gate считается binding'ом, без подтверждения.
- **Запрет на возврат**: удалять `AskUserQuestion` из `onboarding-agent` или делать interview phase «опциональной по auto-mode» — запрещено без пересмотра этого ADR. Фраза «no interview was conducted» в выводе onboarding-agent'а — bug, не feature.
- **Артефакты**: `.claude/agents/onboarding-agent.md` (mandatory Phase 1), `.claude/skills/onboard/SKILL.md` (отражает требование в frontmatter description).

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

---

## Правила обновления этого лога

- ADR не редактируется после фиксации. Если решение пересмотрено — новый ADR с явным `Supersedes ADR-NNN`.
- Каждое ADR именует, что **запрещено возвращать** без пересмотра — это якорь для будущих сессий.
- `rebuild-index.py` запускается после каждого нового entry в devlog (не ADR-log).
