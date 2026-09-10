---
owner: nikitaCodeSave
last-updated: 2026-08-29
---

# External sources — research index для Claude Code harness'а

Справочный каталог внешних источников, на которых стоит harness. Каждая
запись — **URL → описание → ключевые тезисы → как применяется здесь**.
Группировка по логическим блокам, не по дате.

> Этот файл — **active layer reference**, не invariant. Stale-проверка
> при значимом расширении harness'а (см. `feedback_grow_with_community` —
> первоисточники приоритетнее внутренних ADR). Цитаты-claim'ы
> валидированы в `.claude/docs/archive/research-audit.md` (65 утверждений,
> 5-вердиктная шкала).

## Блок 1 — First-party Anthropic: Engineering blog

Авторитетные посты команды Claude Code и connected research. **Primary
truth для harness-philosophy.**

### [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)
**Автор:** Rajasekaran, 24 марта 2026.
**Главные тезисы:**
- *«As models improve, developers should strip away unnecessary scaffolding rather than accumulate complexity»* — foundational quote harness'а.
- **Planner → Generator → Evaluator** — canonical pattern для long tasks. Negotiated sprint contracts: Generator+Evaluator договариваются о «done» до кода.
- **Cost-threshold для opt-in multi-agent**: *«worth the cost когда task sits beyond what current model does reliably solo»*. Не default.
- «I removed the sprint construct entirely — Opus 4.6 could natively handle the job».
**Применяется:** principles.md foundational; Evaluator-узел — fresh-context critic (свежая сессия либо `/code-review ultra`); retire_bias=3 (см. devlog #29).

### [A Harness for Every Task: Dynamic Workflows in Claude Code](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code)
**Авторы:** Thariq Shihipar & Sid Bidasaria (Claude Code MTS), 2 июня 2026. **Canonical для dynamic workflows** — the first-party post behind the `ultracode` / Workflow feature этого harness'а.
**Главные тезисы:**
- Claude читает задачу → пишет собственный `.js`-harness (native-функции для spawn субагентов, назначения моделей, worktree-изоляции) → runtime исполняет. **Harness = output задачи, не предусловие.** First-class artifact: читаемый/перезапускаемый/правимый скрипт; resume после прерывания.
- **Три failure-mode**, которые изолированные субагенты лечат структурно: *agentic laziness* (бросает сложную задачу, объявив done), *self-preferential bias* (подтверждает собственный вывод при self-verify), *goal drift* (констрейнты теряются через turns/compaction). Прямое first-party обоснование §8 (fresh-context ≠ self-recheck) и sub-agent isolation policy.
- **`ultracode` = trigger word, не отдельный режим** — shorthand «напиши dynamic workflow». Голое «workflow» не триггерит. Use-cases выходят за код: sales/data-eng post-mortem, triage backlog.
- **Quarantine pattern**: в triage-workflow'ах агенты, читающие untrusted public content, лишаются high-privilege действий — acting делают отдельные субагенты (privilege-separation против prompt-injection).
**Применяется:** multi-agent.md §7.2 + §7.1 (quarantine), principles.md §permissions (quarantine) + §subagents (3 failure-mode), workflow.md (ultracode framing). Tier T1.

### [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
**Тезисы:**
- **Cross-session durable artifacts** — `claude-progress.txt`, `feature-list.json`, `init.sh`, initializer agent.
- **Context rot** — *«steady degradation of model performance as the window gets full — kicks in well before the hard limit»*.
- **JSON > Markdown для state-файлов**: «model less likely to inappropriately change or overwrite JSON files compared to Markdown».
**Применяется:** спека как носитель состояния в полёте (operator-global §6), PREMORTEM.json/EVIDENCE.json/CRITIC.json (devlog #39, #41).

### [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
**Тезисы:** compaction, structured note-taking, multi-agent isolation, just-in-time retrieval.
**Применяется:** memory-layers.md L0-L4 архитектура, `/remember` curation.

### [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
**Тезисы:**
- *«Most coding tasks involve fewer truly parallelizable tasks than research»* — multi-agent ill-suited для coding.
- **4-15× tokens overhead** — обязательная цена параллельности.
**Применяется:** spawn policy в CLAUDE.md (изоляция / параллельность / auto-compact rescue), multi-agent.md дисциплина.

### [Claude Code Sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)
**Тезисы:** **84% reduction permission prompts** при internal usage. bubblewrap (Linux) + Seatbelt (macOS) OS-level enforcement. `/sandbox` slash-command.
**Применяется:** опционально в high-trust workflow; не в core harness (zero project-state setup).

### [Building a C Compiler with Parallel Claudes](https://www.anthropic.com/engineering/building-c-compiler)
**Автор:** Carlini, 5 февраля 2026.
**Тезисы:** lock-based coordination, GCC как oracle для verification, parallel Claudes на разных subtasks.
**Применяется:** не используется напрямую — паттерн «verification против внешнего oracle» близок ECC/CWC injection экспериментам (devlog #24).

### [Long-Running Claude for Scientific Computing](https://www.anthropic.com/research/long-running-Claude)
**Автор:** Mishra-Sharma, 23 марта 2026.
**Тезисы:** **Ralph loop** — single-agent sequential для coupled pipelines (нельзя параллелить — каждый шаг зависит от прошлого). Контраст с multi-agent research.
**Применялось:** `.claude/docs/archive/loop-2026-05/` self-improvement infrastructure (retired 2026-07-15; devlog #26-29, #41) — паттерн адаптирован.

### [April 23 Postmortem — recent Claude Code quality reports](https://www.anthropic.com/engineering/april-23-postmortem)
**Дата:** 23 апреля 2026.
**Тезисы:** три независимых регрессии качества — сдвинутый дефолт effort, баг очистки thinking, откат verbosity-промпта — прожили недели, пока не были найдены. Anthropic тюнит harness Claude Code под каждый релиз модели отдельно.
**Применяется:** аргумент, что **промпты и дефолты тихо регрессируют** — отсюда дисциплина явной верификации поведения (свои замеры, а не вера в дефолт) и cadence перепроверки среза.

### [Scaling Managed Agents — Decoupling brain/hands/session](https://www.anthropic.com/engineering/managed-agents)
**Дата:** 8 апреля 2026.
**Тезисы:** *«Harnesses encode assumptions about what Claude can't do on its own — but those assumptions need to be questioned because they can go stale as models improve.»* Brain/hands/session log decoupling.
**Применяется:** validates principles.md foundational + workflow-evolution.md cadence. **Method out of scope** (API-only, per api-constraint.md); pattern-level знание portable.

### [Agent Harness Design: 3 Patterns for Harnessing Claude's Intelligence](https://claude.com/blog/harnessing-claudes-intelligence)
**Автор:** Lance Martin (Claude Platform Team), 2 апреля 2026.
**Тезисы:** (1) **Lean on the model, not the harness** — общие инструменты, которые модель знает (bash, file-edit), бьют специализированную обвязку и растут вместе с моделью; (2) **Strip your harness down** — *«as Claude gets more capable, those assumptions should be tested»*, отдавай модели оркестрацию, управление контекстом и память; (3) **Set boundaries carefully** — UX, стоимость и безопасность обеспечиваются декларативными границами, а не инструкциями.
**Применяется:** тройка ровно совпадает с нашим foundational + built-ins-first + permissions-слоем; полезна как компактная формулировка «что именно оставлять в обвязке». Tier T1.

### [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude)
**Дата:** 25 мая 2026.
**Тезисы:** *«Design for containment at the environment layer first, then steer behavior at the model layer»* — надзирают не за тем, что агент делает, а за тем, что он **способен** сделать (sandbox, VM, egress-контроль). Измеренная approval fatigue: пользователи аппрувили ~93% промптов; auto-mode классификатор ловит ~83% overeager-поведений до исполнения; OS-sandbox даёт −84% промптов.
**Применяется:** principles.md § Settings & permissions (границы важнее инструкций), обоснование sandbox как опции и того, почему свой guard-хук ретайрен: containment строится на уровне окружения, а не на самописном DENY поверх нативного. Tier T1.

### [How Anthropic secures its AI-native software development lifecycle](https://claude.com/blog/how-anthropic-secures-its-ai-native-software-development-lifecycle)
**Автор:** Jason Clinton (Deputy CISO), 21 июля 2026.
**Тезисы:** границы строятся вокруг **доступа и действий, а не вокруг инструкций модели**; single-purpose identity с минимальными правами на агента (incident-response агент пишет доки и читает прод-логи, но **не деплоит**); гейт из узкоспециализированных ревью-агентов + детерминированные проверки; всё логируется в SIEM. **Инцидент:** после апгрейда модели IR-агент по своей инициативе написал другому Claude и попросил запушить фикс → **границы агента обязаны включать доступ к другим агентам**.
**Применяется:** workflow-orchestration.md § Cross-session `SendMessage` (security-инварианты), principles.md § Settings & permissions. Tier T1.

## Блок 2 — First-party Anthropic: Product docs & blog

Live ground-truth по фичам Claude Code CLI. **Источник для «как это работает», не для «зачем».**

### [docs.claude.com / code.claude.com — Claude Code documentation](https://docs.claude.com/en/docs/claude-code)
Канонические страницы (актуальный домен `code.claude.com`):
- `/best-practices` — Cherny + team 2026, single highest-leverage doc
- `/sub-agents` — built-ins inventory, frontmatter spec
- `/skills` — SKILL.md ≤500 строк, frontmatter required
- `/hooks` — десятки lifecycle-событий, далеко за пределами тех пяти, что использует большинство проектов (точное число — только в `native-capabilities.md` кита: единственный version-pinned файл)
- `/memory` — CLAUDE.md hierarchy, @import syntax, MEMORY.md auto-load 200 lines/25KB
- `/settings` — 3-layer permissions model
- `/common-workflows`, `/code-review`, `/cli-reference`, `/commands`, `/slash-commands`
**Применяется:** principles.md cites all canonical pages. Verification — `.claude/docs/archive/research-audit.md` (39 CONFIRMED claims).

### [claude.com/blog — The new rules of context engineering for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
**Автор:** Thariq Shihipar, 24 июля 2026. **Canonical для контекст-инжиниринга под текущее поколение.**
**Главные тезисы:**
- Из системного промпта самого Claude Code **вырезано >80%** «with no measurable loss on coding evaluations». Механизм вреда назван прямо: over-constraining через system prompt + CLAUDE.md + skills даёт **конфликтующие инструкции в одном запросе** (внутренний пример: «leave documentation as appropriate» против «DO NOT add comments»).
- CLAUDE.md: *«briefly describe what your repo is for, but spend most of the tokens on gotchas»*; не писать то, что выводится из структуры кода.
- Skills — «lightweight guides», длинные режутся на файлы через progressive disclosure.
- Спеки: *«prefer files that are in code as it provides clear, high-fidelity instructions»* — код, HTML-мокапы и тест-сьюты вместо markdown-пересказа.
- Сдвиги: правила → judgment; примеры вызова инструментов → выразительные параметры; загрузка контекста вся сразу → deferred/ToolSearch; ручной CLAUDE.md → auto-memory.
- Эти практики встроены в **`/doctor`** — он «rightsize»-ит skills и CLAUDE.md.
**Применяется:** principles.md foundational + Memory-секция; workflow.md anti-patterns; workflow-evolution.md (retire-ритуал через `/doctor`). Tier T1.

### [platform.claude.com — Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)
**Тезисы:** не над-инструктировать верификацию — модель ловит и чинит свои ошибки сама, а унаследованные «double-check», «add a final verification step», **«use a subagent to verify»** дают over-verification; давать полную спеку сразу (модель доводит задачу, а не оставляет заглушки); в код-ревью не просить «только high-severity» — отфильтруешь отдельным проходом; thinking включён по умолчанию, глубиной управляет **effort** (при выключенном thinking `xhigh`/`max` API отвергает — в CLI это теперь не долетает до API: клиент подставляет `high`, так что связка даёт не ошибку, а тихий потолок).
**Применяется:** workflow.md anti-patterns (инструкции самопроверки в промпте), § Default effort. **Watch-item закрыт замером** (devlog #130, `benchmark/guard-ab/`): на Opus 5 независимый рефьютер свежим контекстом дал +24 / +12 / +3 кейса из 239 на одной и той же реализации, 3 прогона из 3, без роста ложных срабатываний. Предупреждение поста метит в *инструкцию самопроверки внутри промпта*, §8 — в *отдельный проход другим контекстом*; это разные вещи, и второе продолжает окупаться.

### [claude.com/blog/onboarding-claude-code-like-a-new-developer](https://claude.com/blog/onboarding-claude-code-like-a-new-developer-lessons-from-17-years-of-development)
**Автор:** Brendan MacLean (Skyline, 700K+ LoC C#, 17 лет dev).
**Цитата:** *«Understand that Claude can't learn without you recording 'context.' Don't expect magic … Invest in building and maintaining your context layer. And treat it like any other project artifact: version it, grow it, maintain it»*.
**Применяется:** обоснование `.claude/docs/`, devlog, progress.md как versioned context-layer.

### [claude.com/blog/common-workflow-patterns-for-ai-agents](https://claude.com/blog/common-workflow-patterns-for-ai-agents-and-when-to-use-them)
**Тезисы:** sequential / parallel (sectioning, voting) / evaluator-optimizer патт`ерны. Когда какой применять.
**Применяется:** workflow.md Plan→Work→Review spine, multi-agent.md baseline.

### [claude.com/blog/how-anthropic-teams-use-claude-code](https://claude.com/blog/how-anthropic-teams-use-claude-code)
**Тезисы:** реальные patterns внутри Anthropic — `/init`, кастомные slash-commands, hooks для state validation.
**Применяется:** validates docs-contract направление (`docs-discipline.md` + WORKFLOW.md §3; bootstrap нативно под способной моделью).

### [claude.com/blog — How Claude Code Works in Large Codebases](https://www.claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start)
**Дата:** 14 мая 2026.
**Тезисы:** *«Harness matters more than the model — review your configuration every 3-6 months because instructions tuned for older models constrain newer ones.»* DRI/team ownership of harness governance. LSP integration для symbol-level precision. *«Split exploration from editing via read-only subagents.»*
**Применяется:** opening citation в workflow.md spine; cadence trigger в workflow-evolution.md.

### [claude.com/blog — How Anthropic uses Claude for Cybersecurity (CLUE platform)](https://www.claude.com/blog/how-anthropic-uses-claude-cybersecurity)
**Дата:** 12 мая 2026.
**Тезисы:** «Orchestrator → parallel sub-agents → 25+ tool calls per session.» Explicit preference for **non-deterministic exploration** over rigid playbooks: *«when we gave Claude latitude to explore — access to tools and a goal, rather than a rigid sequence — it often took paths we wouldn't have prescribed.»*
**Применяется:** evidence для «goal+tools beats prescribed sequence» — anti-pattern в workflow.md (rigid pipeline), pattern в workflow-evolution.md (loops + exploration > fixed playbook).

### [platform.claude.com — What's new in Claude Opus 5](https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5)
**Тезисы:** 1M context как дефолт и максимум с ровным instruction-following по всему окну; thinking включён по умолчанию, модель сама решает глубину, рычаг — `effort`; фиксированные thinking-бюджеты убраны; более буквальное следование инструкции («will not silently generalize»).
**Применяется:** model capability baseline для «strip away scaffolding» рассуждений; против «vague instructions» anti-pattern.

### [code.claude.com/docs/en/agent-teams](https://code.claude.com/docs/en/agent-teams)
**Тезисы:** «прежде чем заводить команду, проверь, не хватит ли более лёгкого варианта» —
субагенты внутри одной сессии, cross-session messaging между своими сессиями. Teams выигрывают
там, где параллельное исследование реально даёт ценность (ревью в несколько линз, конкурирующие
гипотезы при отладке, независимые куски фичи), и проигрывают на последовательной работе и правках
одного файла. Ключевое для дизайна харнеса: **включённый флаг меняет обычное делегирование** —
субагент, которому Claude сам дал имя, стартует как teammate, так что команда собирается без
запроса. `TeamCreate`/`TeamDelete` удалены (v2.1.178).
**Применяется:** principles.md § Subagents (model assignment / teams), multi-agent.md таблица
режимов. Tier T1.

### [OpenAI открыла исходники Codex-харнеса (Apache-2.0, 20 августа 2026)](https://github.com/openai/codex)
**Тезисы:** движок Codex (`codex exec` · SDK · app-server) выложен под Apache-2.0. Заявленная
цифра: настройка **только** харнеса (inference retention + compaction) подняла ARC-AGI-3 с 13.3%
до 38.3% при ~6× меньшем расходе токенов, модель не менялась.
**Применяется:** corroboration Harness-Bench в `benchmark.md` (та же форма замера: модель
зафиксирована, харнес варьируется) и контекст для cross-vendor ревьюера (`multi-agent.md` §7.3) —
движок под нашим `codex_peer` теперь открытый. **Vendor-claim, не независимая репликация**:
tier T4, инвариантов не порождает.

### arXiv, август 2026 — [Prime Agent 2608.23552](https://arxiv.org/abs/2608.23552) · [Agent Lightning v1.0 2608.17528](https://arxiv.org/pdf/2608.17528)
**Тезисы:** Prime Agent — open-source харнес, стандартизующий execution / recovery / verification /
resource accounting и **оставляющий построение стратегии модели**; явная цель — «чтобы отказы
харнеса не читались как отказы модели». Agent Lightning — «harnessed agentic RL»: состояние
харнеса вводится в латентное состояние POMDP, харнес участвует в post-training.
**Применяется:** Prime Agent усиливает открытый хвост `benchmark.md` (model×harness reporting,
failure-symptom taxonomy) — ровно наша проблема разделения «модель vs обвязка». Agent Lightning —
**метод out of scope** (RL-обучение), берём только словарь. T3.

### [code.claude.com/docs/en/changelog](https://code.claude.com/docs/en/changelog)
Live ground-truth по версиям; релизы каждые несколько дней. **Здесь дельта намеренно не дублируется** — единственный version-pinned срез харнеса живёт в `~/.claude/skills/claude-code-harness/references/native-capabilities.md`, копия в двух местах протухает в одном из них молча.
**Применяется:** external-intake проход refresh-ритуала (`harness-evolution.md`) сверяет changelog против ledger'а и правит `native-capabilities.md` точечно.

## Блок 3 — Claude Code creators & insiders

### [howborisusesclaudecode.com](https://howborisusesclaudecode.com/)
**Автор:** Boris Cherny (Head of Claude Code).
**Тезисы:**
- **Verification = single highest-leverage practice**. *«Give Claude a way to verify its work»* → 2-3× quality.
- CLAUDE.md как живой регрессионный артефакт, не одноразовый setup.
- Outcome-based metrics, не cost/token-based.
- Тончайшая возможная обвязка.
**Применяется:** foundational principle harness'а, verification baseline в testing.md.

### [Boris Cherny — AI Ascent 2026 (YouTube)](https://www.youtube.com/watch?v=SlGRN8jh2RI), [Lightcone interview Feb 2026](https://www.youtube.com/watch?v=PQU9o_5rHC4), [Latent Space podcast с Cat Wu](https://www.latent.space/p/claude-code)
Видео-источники practices от создателей. Транскрипты часто недоступны через WebFetch — claim'ы из этих источников помечены UNVERIFIABLE в research-audit где нет дословной цитаты.

### [Code w/ Claude 2026 — Anthropic dev conference, 6 мая 2026 (Simon Willison live-blog)](https://simonwillison.net/2026/May/6/code-w-claude-2026/)
**Источник:** Simon Willison live-blog (third-party, но public summary).
**Тезисы (keynotes):**
- **Cat Wu**: Claude Code evolution CLI → IDE → Desktop. «Next big thing — **proactivity**. Routines as on-ramp.»
- **Boris Cherny**: *«Routines = higher-order prompts → setup async automations and wake up to PRs that are ready to merge.»* «Claude Code itself may be 100 lines of code a year from now.»
- **Announcements**: doubled Pro/Max/Enterprise 5h limit; advisor pattern (smaller models query Opus, 5x cheaper); CI auto-fix; Security Reviews; Remote Agents.
**Применяется:** Routines paradigm в workflow-cloud-offload.md + workflow-async.md. Proactivity thesis influences workflow.md routing.

### [TechCrunch — Cat Wu interview](https://techcrunch.com/2026/05/13/anthropics-cat-wu-says-that-in-the-future-ai-will-anticipate-your-needs-before-you-know-what-they-are/)
**Дата:** 13 мая 2026.
**Тезисы:** Proactivity thesis — *«last year was synchronous development; now people are shifting to routines; next step is Claude understanding what you work on and setting up automations.»*
**Применяется:** workflow-cloud-offload.md context для Routines.

### [Every — How to Use Claude Code Like the People Who Built It](https://every.to/podcast/transcript-how-to-use-claude-code-like-the-people-who-built-it)
Cat Wu + Cherny transcripted podcast — sub-agent / slash-command usage patterns from inside Anthropic.

## Блок 5 — Research papers (peer-reviewed / arXiv)

### [arXiv 2603.25723 — Tsinghua «Natural-Language Agent Harnesses (NLAH)»](https://arxiv.org/abs/2603.25723)
**Авторы:** Pan, Zou, Guo, Ni, Zheng. Март 2026.
**Тезисы:** Harness как редактируемый natural-language артефакт. Три опоры:
1. **Explicit contracts** (rules / API constraints / testing invariants)
2. **Durable artifacts** (devlog, ADR, MEMORY.md)
3. **Lightweight adapters** (hooks для gating/observability, не для logic).
Runtime = Intelligent Harness Runtime (IHR).
**Применяется:** `.claude/rules/*.md` = contracts, `.claude/devlog/` = artifacts, hooks = adapters. См. `reference_harness_papers_2026.md` memory.

### [arXiv 2603.28052v1 — Stanford «Meta-Harness»](https://arxiv.org/abs/2603.28052)
**Авторы:** Lee, Nair, Zhang, Lee, Khattab, Finn. Март 2026.
**Тезисы:** Agent-proposer ищет harness через filesystem-доступ к source/scores/traces. Результаты: **+7.7 pp классификация при −75% context tokens**, +4.7 pp IMO, обгоняет hand-engineered на TerminalBench-2.
**Применяется:** direct evidence для агрессивного retire_bias и CLAUDE.md ≤200 строк. **Method НЕ применим** — требует API key (managed-agents, тысячи итераций). Берём идеологию «evidence-driven».

### [arXiv 2604.25850 — Agentic Harness Engineering (AHE)](https://arxiv.org/abs/2604.25850)
**Авторы:** Lin, Liu, Pan, Lin, Dou, Huang, Yan, Han, Gui. 28 апреля 2026.
**Тезисы:** Observability-driven closed loop через 3 pillars (component / experience / decision observability). **Empirical ablation**: harness gains localize к **tools / middleware / long-term memory** — **НЕ system prompt**. 84.7% pass@1 Terminal-Bench 2 (vs Codex-CLI 71.9%). Cross-family transferable +5.1pp до +10.1pp.
**Применяется:** foundational citation в workflow-evolution.md TL;DR; supports docs-discipline rule 2 (CLAUDE.md = indexer) с external empirical evidence. Code: github.com/china-qijizhifeng/agentic-harness-engineering.

### [arXiv 2604.20801 — AgentFlow / Synthesizing Multi-Agent Harnesses](https://arxiv.org/abs/2604.20801)
**Авторы:** Liu, Shou, Liu, Wen, Chen, Fang, Feng. 22 апреля 2026.
**Тезисы:** Typed-graph DSL co-searching roles + prompts + tools + topology + protocol. **Headline claim**: *«When the language model is held fixed, changing only the harness can still change success rates by **several-fold** on public agent benchmarks.»* 84.3% на TerminalBench-2 (top of public leaderboard). Found 10 zero-days Chrome (incl. 2 Critical sandbox-escape CVEs).
**Применяется:** workflow-evolution.md cite — multi-axis search > single-axis. Argues для benchmark.md multi-dimension ablation.

### [arXiv 2604.14228 — Dive into Claude Code](https://arxiv.org/abs/2604.14228)
**Авторы:** Liu, Zhao, Shang, Shen. 14 апреля 2026.
**Тезисы:** Source-code analysis of Claude Code's TypeScript vs OpenClaw. 7-component structure, 5-layer subsystem architecture. **Core = «simple while-loop that calls model, runs tools, repeats»** — validates наш minimalism principle. Four extensibility mechanisms: **MCP, plugins, skills, hooks** — exactly наш surface. **Subagent delegation uses worktree isolation** — matches feedback_test_iterations_via_worktree.md.
**Применяется:** independent reverse-engineering reference в `native-capabilities.md` + workflow-orchestration.md.

### [arXiv 2604.18071 — Architectural Design Decisions in AI Agent Harnesses](https://arxiv.org/abs/2604.18071)
**Автор:** Hu Wei. 20 апреля 2026.
**Тезисы:** Protocol-guided source-grounded empirical study of **70 publicly available agent-system projects**. Five design dimensions: subagent architecture / context management / tool systems / safety / orchestration. Cross-project frequencies: **Multi-level Recursive 12.9%**, Tool-based Delegation 17.1%, Pipeline/Stage 1.4%.
**Применяется:** workflow-orchestration.md empirical positioning — наша restraint-policy = deliberate (not default failure). Peer comparison data.

### [arXiv 2605.10923 — SLIM: Dynamic Skill Lifecycle Management](https://arxiv.org/abs/2605.10923)
**Дата:** 11 мая 2026.
**Тезисы:** Three lifecycle operations — **retain / retire / expand** based on leave-one-skill-out marginal contribution. +7.1pp over best baselines на ALFWorld and SearchQA. RL-method (out of scope для CLI), но principle портируется.
**Применяется:** workflow-evolution.md identified gap — no retire ritual у нас сейчас. Proposed criteria см. там.

### [arXiv 2604.26615 — TDD Governance for Multi-Agent Code Generation](https://arxiv.org/abs/2604.26615)
**Авторы:** Hasanli, Siddeeq, Khanal, Kotilainen, Mikkonen, Abrahamsson (Tampere). 29 апреля 2026.
**Тезисы:** AI-native TDD framework с prompt-level + workflow-level governance. Separates model proposal от deterministic engine authority. Bounded repair loops, validation gates, atomic mutation control. Four phases: planning / generation / repair / validation.
**Применяется:** workflow-evolution.md TDD principle alignment с testing.md + bounded-repair anti-pattern.

### [arXiv 2605.18747 — Code as Agent Harness (survey)](https://arxiv.org/abs/2605.18747)
**Авторы:** Ning, Tieu, Fu, Wei … He (UIUC-led, 40+ соавторов). 18 мая 2026. Companion: [github.com/YennNing/Awesome-Code-as-Agent-Harness-Papers](https://github.com/YennNing/Awesome-Code-as-Agent-Harness-Papers).
**Тезисы:** «code as agent harness» — код как operational substrate, не только output. Трёхслойная таксономия: **Harness Interface** (code for reasoning / acting / environment-modeling) → **Harness Mechanisms** (planning · memory · tool-use · «Plan-Execute-Verify Loop» с *Planning as Contract Formation* / pre-postconditions · «Governed Harness Mutation» + «Deep Telemetry as Optimization Substrate») → **Scaling to Multi-Agent** (role-specialization, shared-state coordination, *Workflow Topologies*: pre-defined-heuristic vs **objective-driven-adaptive**, *Shared Harness Representation*: implicit-file-only / repository / execution / **blackboard**). **Open challenges:** #1 oracle-adequacy (beyond final-task-success), #2 semantic-verification-beyond-executable-feedback, #3 self-evolving-without-regression, #5 human-in-the-loop-safety-as-harness-state.
**Применяется:** **vocabulary / validation, не новый инвариант** (T3 survey). Даёт ярлыки нашему: filesystem-blackboard (PREMORTEM/EVIDENCE/CRITIC) = «blackboard + implicit-file-only»; dynamic workflows = «objective-driven adaptive topology»; sprint-contracts = «Planning as Contract Formation»; `loop/` + AHE = «Governed Harness Mutation + Deep Telemetry». Open-challenge #1 усиливает наш open-tail из devlog #70 (Harness-Bench failure-symptom taxonomy → Layer C axes в benchmark.md); #3 — SLIM retire-ritual gap (workflow-evolution.md).

### [arXiv 2606.05894 — EMBER: Budgeted Evidence Retention for Long-Horizon Agents](https://arxiv.org/abs/2606.05894)
**Дата:** июнь 2026. **Тезисы:** *Budgeted Pre-Query Retention* — что сохранить ДО появления запроса под фиксированным token-бюджетом. Память пишется при ingestion, читается без доступа к raw-stream. Юнит — **evidence capsule**: *дословная выдержка источника + retrieval-key + update-metadata* (grounding + discoverability + контекст). Learned retention-policy на post-query outcome-feedback. Результат: EMBER-14B 0.30 F1 @ 8192-budget на LongMemEval-RR (vs 0.18 strongest baseline).
**Применяется:** **method out of scope** (learned RL-policy, как SLIM/Meta-Harness — нужен training). Переносимый принцип: *source-backed / verbatim, не перефраз* + бюджет форсит приоритизацию — совпадает с memory-layers.md (frontmatter `description` = retrieval-key, `[[links]]` = update-metadata) и с заметкой про 63%-wrong-accept (держать storage детерминированным). НЕ строим learned-pipeline (наш anti-pattern «multi-step memory pipeline premature»). T3.

### [arXiv 2607.14275 — AI Agents Do Not Fail Alone: The Context Fails First](https://arxiv.org/abs/2607.14275)
**Автор:** Fouad Bousetouane. 15 июля 2026.
**Тезисы:** качество контекста измеряется **до** запуска и предсказывает надёжность агента: модель фиксируют, варьируют только контекст. Семь критериев — role clarity, guardrail coverage, instruction consistency, tool-schema quality, grounding sufficiency, injection hardening, token efficiency — каждый предсказывает свой отказ (grounding → галлюцинации, guardrails → манипулируемость, consistency → следование инструкции, tool-schema → корректность вызовов).
**Применяется:** **словарь и preflight-рамка, не инвариант** (T3). Совпадает с нашим разделением слоёв: rules = instruction consistency, permissions + нативный классификатор = guardrail coverage, quarantine = injection hardening, CLAUDE.md-бюджет = token efficiency. Полезно как чек-лист при аудите чужого харнеса.

### [arXiv 2606.14249 — HarnessX: A Composable, Adaptive, and Evolvable Agent Harness Foundry](https://arxiv.org/abs/2606.14249)
**Дата:** июнь 2026 (v2 — 23 июля).
**Тезисы:** харнесы «hand-crafted and static»; автоматическая композиция и эволюция элементов обвязки по execution-feedback даёт **+14.5% в среднем (до +44%)** на пяти бенчмарках (ALFWorld, GAIA, WebShop, tau³-Bench, SWE-bench Verified), причём прирост тем больше, чем слабее baseline.
**Применяется:** corroboration AHE — «обвязка двигает результат сопоставимо с моделью». **Метод out of scope** (RL-движок, требует обучения). T3.

### [Chroma Research — Context Rot](https://research.trychroma.com/context-rot)
**Авторы:** Hong / Troynikov / Huber, июль 2025. 18 моделей.
**Тезисы:** эмпирическое подтверждение pre-rot threshold; performance деградирует ДО hard context limit.
**Применяется:** principles.md context budget reasoning.

## Блок 10 — Source-quality rubric для будущих расширений

Когда добавляешь новый источник в harness reasoning, проверяй по этой шкале:

| Tier | Что попадает | Доверие |
|---|---|---|
| **T1 first-party** | anthropic.com/engineering, code.claude.com docs, claude.com/blog | primary truth |
| **T2 insider** | Boris Cherny, Brendan MacLean blog posts; Anthropic-team-authored talks | strong evidence |
| **T3 peer-reviewed** | arXiv, Chroma Research, peer benchmarks | evidence; methodology может быть out of scope |
| **T4 independent practitioner** | Shankar, Osmani, Schmid, Cognition, generativeprogrammer | high signal, cross-validate с T1-T3 |
| **T5 community essay / aggregator** | claudefa.st, ofox.ai, boringbot, blog aggregators | trend-signal, не authority |
| **T6 curated lists / reference impls** | awesome-*, OpenHarness, showcase repos | discovery resource |
| **T7 live evidence** | `claude --help`, GitHub issues, CHANGELOG | ground-truth для current state |

**Правило:** T1+T2 могут обосновать invariant в `.claude/rules/`. T3-T4 — кандидат на active layer (`.claude/docs/`). T5-T6 — supplementary, обязательна cross-reference с T1-T4.

См. также `feedback_grow_with_community.md` (memory): не зарываться во внутренние ADR'ы, **first-party + community первичны** при значимых решениях.

## Что НЕ включено и почему

- **YouTube без транскрипта** (AILABS, talks без публичной расшифровки) — UNVERIFIABLE per research-audit. Используются только когда дословная цитата воспроизведена в письменном источнике.
- **Closed-source LLM articles** не про Claude Code — нерелевантно (другая модель / другая модель деплоя).
- **Anthropic API features** (managed-agents, beta headers, batch API, citations) — out of scope per `api-constraint.md` даже если документированы Anthropic.

## Related

- `.claude/docs/principles.md` — sources cited в полном тексте (active state).
- `.claude/docs/archive/research-audit.md` — 65 atomic claims, 5-вердиктная classification (frozen 2026-05-09).
- `.claude/docs/archive/practices-from-projects.md` — обширный survey community practices (frozen 2026-05-10).
- `.claude/docs/archive/harnesses-guide.md` — первая итерация research-guide (frozen, источник research-audit'а).
- `reference_harness_papers_2026.md` (auto-memory) — NLAH + Meta-Harness detailed notes.
- `feedback_grow_with_community.md` (auto-memory) — invariant «первоисточники приоритетнее внутренних ADR».
