---
owner: nikitaCodeSave
last-updated: 2026-10-27
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
**Применяется:** spawn policy в CLAUDE.md (изоляция / параллельность / независимое ревью), multi-agent.md дисциплина.

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

### [Redesigning source control at Anthropic](https://www.anthropic.com/engineering/redesigning-source-control)
**Дата:** 13 октября 2026 (в листинге claude.com — 19-е). Прочитано research-агентом 2026-10-27.
**Тезисы:** узкое место сместилось с написания кода на *«source control, builds, and CI»*: изменений в монорепо за день — от ~2 500 в мае до 30 000+ в сентябре. Классическая merge queue *«doesn't make much sense at agent scale»* — вложились в post-merge и pre-deploy тестирование. Инженер ревьюит *намерение* изменения, его роль часто — *«to tell Claude "no"»*; адверсариальное ревью *«can also be myopic»*.
**Применяется:** workflow.md § Review (ревью намерения против спеки, а не построчное). Tier T1.

## Блок 2 — First-party Anthropic: Product docs & blog

Live ground-truth по фичам Claude Code CLI. **Источник для «как это работает», не для «зачем».**

### [docs.claude.com / code.claude.com — Claude Code documentation](https://docs.claude.com/en/docs/claude-code)
Канонические страницы (актуальный домен `code.claude.com`):
- `/best-practices` — Cherny + team 2026, single highest-leverage doc
- `/sub-agents` — built-ins inventory, frontmatter spec
- `/skills` — SKILL.md ≤500 строк, frontmatter required
- `/hooks` — десятки lifecycle-событий, далеко за пределами тех пяти, что использует большинство проектов (точное число — только в `native-capabilities.md`: единственный version-pinned файл)
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

### [Best practices for Claude Code — редакция конца октября 2026](https://code.claude.com/docs/en/best-practices)
**Дата:** на странице нет; по истории зеркала (`pleaseai/claude-code-docs`) переписана между 23 и 27 октября 2026. Сверено 2026-10-27.
**Главные тезисы:**
- Ось страницы — что *решает* Claude (промпт, CLAUDE.md, skills) против того, что *обеспечивает* harness (хуки, deny-правила, managed settings): *«If something has to happen every time, make it a hook, a deny rule, or a managed setting. CLAUDE.md is for guidelines, and Claude is allowed to decide a guideline doesn't apply.»*
- Нетривиальная задача: *«Interview me until you could write the spec, then write it to SPEC.md»* → свежая сессия строит по `SPEC.md`. Plan mode на странице не упоминается.
- Проверка: *«Give Claude something it can run that comes back pass or fail»*; лестница — промпт → `/goal` → `Stop`-хук → `/code-review` свежим контекстом. Просить доказательство (команда и вывод): *«"All tests pass" on its own tells you very little»*.
- Ревью — сверка диффа со `SPEC.md`, *«report gaps that affect correctness and skip style»*: *«A reviewer that's asked to find problems will always find something»*.
- Таблица «What you can stop doing»: агрессивное управление контекстом; IMPORTANT/CAPS; **субагенты для защиты контекстного окна**; делегирование «ради лучшего ответа» (*«A fresh reviewer does help, because it hasn't seen your reasoning, which is a different thing from delegating»*); «think hard»; «keep going / don't be lazy»; архитектура и раскладка файлов в CLAUDE.md.
- Для скриптов советует `--bare` — это API-ключ, вне scope (`api-constraint.md`).
**Применяется:** `rules/testing.md` (проверка pass/fail + доказательство), workflow.md (интервью → `SPEC.md` → свежая сессия; ревью против спеки), CLAUDE.md и principles.md (снят пункт «auto-compact rescue»). Tier T1.

### [How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/)
**Авторы:** Osmani, Lunt, Wang, 15 октября 2026. Сверено 2026-10-27.
**Главные тезисы:**
- Ревью идёт непрерывно, *«more like spellcheck while you write»*, а не гейтом в конце.
- Уровень риска ставит классификатор по изменению — *«The change sets the tier, not the author»*: low — без человека при зелёных автоматических проверках, medium — один, high — двое; sensitive-пути и CI-workflow всегда требуют человека. *«An agent's approval never counts as a person's»*; человек, направлявший агента, сам считается одним из ревьюеров.
- `REVIEW.md` пишут владельцы кода, отдельно от CLAUDE.md: как выглядит провал именно в этом репо, лимит на мелочи, пути-исключения, file:line как доказательство, сводка начинается со счёта находок.
- Не больше **3 раундов** ревью, дальше — пересмотреть подход (был PR с 50+ раундами за ночь); повторное ревью только по новому диффу; уже опубликованные находки не повторяются.
- Цифры (внутренние, методика не раскрыта): мёржей в репо Claude Code ×2+ и доля откатов −40% (июнь → сентябрь); PR с существенными комментариями 16% → 54%; PR с ≥5 раундами 8.9% → 1.5%.
**Применяется:** workflow.md § Review. Tier T1 (claude.dev — блог разработчиков Anthropic; first-party по атрибуции страницы). Цифры vendor-internal — инвариантов не порождают.

### [When to fold subagents into your main agent loop](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop)
**Автор:** Diane Sarkis, 22 октября 2026. Общая статья Claude Platform, не про Claude Code специально. Прочитано research-агентом.
**Тезисы:** системный промпт Claude Code сокращён более чем на 80% через progressive disclosure. Субагент оправдан только при измеримой деградации от раздутого контекста, параллельных задачах на свежем контексте или конфликте инструментов/инструкций. Ретайрены «Frankenprompt» и кодовый шаг, переписывающий планы по каталогу правил.
**Применяется:** вместе с best-practices — снятие «auto-compact rescue» в CLAUDE.md и principles.md. Tier T1.

### Другие вендоры, июль–октябрь 2026
Первоисточники OpenAI и Sarkis сверены второй проверкой 2026-10-27; Cursor и GitHub — только первой.
- **OpenAI** ([developers.openai.com/blog](https://developers.openai.com/blog)): «Rethinking skills and prompts for GPT-6 Astra» (11 сен, Provencher) — короткие описания skills, корневой skill-файл как *«a minimal router»*, убрать «read architecture.md before every edit» и подталкивания к тестам (модель тестирует сама); «Custom Code Review rules for Codex» (20 июл) — правила ревью скоупом в AGENTS.md, «the invariant and the safe path», *«If removing a rule would not change the review, leave it out»*; «Maintaining software with the GPT-6 family» (14 окт) — A/B-реплей, чтобы проверить одну строку AGENTS.md.
- **Расхождения с Anthropic:** best-practices OpenAI всё ещё называет plan mode *«the easiest and most effective option»*; правила ревью OpenAI держит в AGENTS.md, Anthropic — в отдельном `REVIEW.md`.
- **Codex CLI** удалил `codex mcp-server` (0.154.0, 9 сен); лаба к этому моменту уже вызывает Codex через CLI.
- **Cursor** (Projects, 10 сен; «Bots for the last mile», 23 сен), **GitHub** (Copilot dynamic workflows, 1 окт; ReviewBench, 5 окт): координатор-проекты, оркестрация кодом, пост-мёрж мониторинг; ensemble-ревьюер ReviewBench +8% precision / +13.6% recall.
**Применяется:** конвергенция «узкое место — ревью, CI и мёрж» и «срезать инструкции под старые модели» подкрепляет T1 выше; сама инварианты не обосновывает.

### [platform.claude.com — Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)
**Тезисы:** не над-инструктировать верификацию — модель ловит и чинит свои ошибки сама, а унаследованные «double-check», «add a final verification step», **«use a subagent to verify»** дают over-verification; давать полную спеку сразу (модель доводит задачу, а не оставляет заглушки); в код-ревью не просить «только high-severity» — отфильтруешь отдельным проходом; thinking включён по умолчанию, глубиной управляет **effort** (при выключенном thinking `xhigh`/`max` API отвергает — в CLI это теперь не долетает до API: клиент подставляет `high`, так что связка даёт не ошибку, а тихий потолок).
**Применяется:** workflow.md anti-patterns (инструкции самопроверки в промпте), § Default effort. **Watch-item закрыт замером** (devlog #130, `benchmark/guard-ab/`): на Opus 5 независимый рефьютер свежим контекстом дал +24 / +12 / +3 кейса из 239 на одной и той же реализации, 3 прогона из 3, без роста ложных срабатываний. Предупреждение поста метит в *инструкцию самопроверки внутри промпта*, §8 — в *отдельный проход другим контекстом*; это разные вещи, и второе продолжает окупаться.

### [claude.com/blog/onboarding-claude-code-like-a-new-developer](https://claude.com/blog/onboarding-claude-code-like-a-new-developer-lessons-from-17-years-of-development)
**Автор:** Brendan MacLean (Skyline, 700K+ LoC C#, 17 лет dev).
**Цитата:** *«Understand that Claude can't learn without you recording 'context.' Don't expect magic … Invest in building and maintaining your context layer. And treat it like any other project artifact: version it, grow it, maintain it»*.
**Применяется:** обоснование `.claude/docs/`, ADR и открытой спеки как versioned context-layer.

### [claude.com/blog/common-workflow-patterns-for-ai-agents](https://claude.com/blog/common-workflow-patterns-for-ai-agents-and-when-to-use-them)
**Тезисы:** sequential / parallel (sectioning, voting) / evaluator-optimizer патт`ерны. Когда какой применять.
**Применяется:** workflow.md spine (Spec→Build→Review), multi-agent.md baseline.

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
движок под нашим ревьюером теперь открытый (по коду: репо было под Apache-2.0 с 2025 года, в августе открыта упаковка exec/SDK/app-server; заявка про ARC-AGI-3 держится на серверной компакции и из открытого кода не воспроизводится). **Vendor-claim, не независимая репликация**:
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
Live ground-truth по версиям; релизы каждые несколько дней. **Здесь дельта намеренно не дублируется** — единственный version-pinned срез харнеса живёт в `.claude/docs/native-capabilities.md`, копия в двух местах протухает в одном из них молча.
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

### Boris Cherny — серия тредов о сетапе, январь–июнь 2026 ([2 янв](https://x.com/bcherny/status/2007179832300581177) · [31 янв](https://x.com/bcherny/status/2017742741636321619) · [12 фев](https://x.com/bcherny/status/2021699851499798911) · [30 мар](https://x.com/bcherny/status/2038454336355999749))
**Доступ:** x.com напрямую не читается; тексты сверены по зеркалам (twitter-thread.com, скриншоты в `shanraisshan/claude-code-best-practice`).
**Тезисы:**
- Собственный сетап — *«surprisingly vanilla… Claude Code works great out of the box»*.
- Verification повторяется как «the most important tip» во всех тредах — устойчивое ядро.
- «Если делаешь что-то чаще раза в день — сделай skill или command»: порог action-skill совпадает с нашим.
- Дрейф со временем: ручной `/permissions` → auto mode; thinking-бюджеты → `/effort`; «дописывай CLAUDE.md после каждой ошибки» частично вытеснено авто-памятью. Ранние треды — исторический срез, не current practice.
**Применяется:** подтверждает foundational principle; ранние советы не переносить без сверки с `native-capabilities.md`.

### [Boris Cherny — YC Startup School 2026](https://www.ycombinator.com/library/UN-boris-cherny-building-claude-code) (конец июля 2026; [Daring Fireball](https://daringfireball.net/linked/2026/08/02/cherny-claude-swift))
**Доступ:** по пересказу и фрагментам транскрипта, полный текст не сверен.
**Тезисы:** *«every six months delete your Claude.md. Delete your skills»* — метод абляции: сначала удалить, потом вернуть то, без чего реально хуже. *«Verification is probably the single most important thing that people do not get right»*. Ранее в [Pragmatic Engineer](https://newsletter.pragmaticengineer.com/p/how-claude-code-is-built): *«Every time there's a new model release, we delete a bunch of code»*.
**Применяется:** retirement-дисциплина `harness-evolution.md`; обоснование чистой пересборки вместо наращивания.

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

## Блок 4 — Independent practitioners (T4)

Публичные сетапы сильных практиков. Не обосновывают invariant; служат
cross-validation к T1–T2 и источником кандидатов на пробу.

### Andrej Karpathy — [твит о сбоях coding-агентов, 26 янв 2026](https://x.com/karpathy/status/2015883857489522876) · [`autoresearch/program.md`](https://github.com/karpathy/autoresearch/blob/master/program.md)
**Тезисы (твит, первоисточник):** модели молча принимают неверные допущения, не задают вопросов и не спорят, переусложняют код, правят ортогональный код как побочный эффект. Ключевая строка: *«All of this happens despite a few simple attempts to fix it via instructions in CLAUDE.md»*. Рабочий рецепт оттуда же: *«Don't tell it what to do, give it success criteria and watch it go»*.
**Собственные файлы Karpathy** несут только невыводимое: границы правок (read-only файлы), независимый от агента оракул (`evaluate_bpb` как ground truth), цену компромисса (метрика против строк кода), гигиену контекста (не заливать логи). `llm-council/CLAUDE.md` — факты окружения; `nanochat/.claude/skills/read-arxiv-paper` — action-skill под повторяющуюся операцию. Общего поведенческого CLAUDE.md у него нет.
**Не путать:** [`forrestchang/andrej-karpathy-skills`](https://github.com/multica-ai/andrej-karpathy-skills) (≈217k★) — **сторонний** репо Jiayuan Zhang, создан через ~7 ч после твита, одобрения Karpathy не найдено. Цифра «41%→11% ошибок» из вторичных статей без методики. Наш замер этого блока — архивный devlog 0049 (полный блок ≈ сокращённый).
**Применяется:** подтверждает rule #0 docs-discipline и спеку с исполняемым «Done when»; поведенческие призывы в CLAUDE.md не добавлять.

### Matt Pocock — [`mattpocock/skills`](https://github.com/mattpocock/skills) · [aihero.dev](https://www.aihero.dev/)
**Тезисы (README, `ask-matt` и SKILL.md, первоисточник; апстрим `59db609`, 2026-10-27):** «Skills For Real Engineers», против фреймворков, которые «own the process». Четыре режима отказа → средства: непонимание → `grilling`; многословие → общий глоссарий + ADR; неработающий код → feedback loops (типы, браузер, тесты); «ком грязи» → deep modules. Разделение: user-invoked скиллы оркеструют, model-invoked держат дисциплину.
- Основной поток (`ask-matt`): `/grill-with-docs` (интервью + `GLOSSARY.md`/ADR) → `/to-spec` → `/to-tickets` в одном непрерывном контексте → `/implement` по тикету с `/clear` между ними либо `/implement-spec` (тикеты как граф задач, implementer-субагенты параллельно по готовому фронту, одна integration-ветка, один `/code-review` в конце) → `/retro`. Работа больше одной сессии — `/wayfinder` (карта *решений*, а не срезов). Вспомогательные: `/prototype`, `/research` (фоновый агент, только первоисточники), `/diagnosing-bugs`.
- `grilling`: интервью обходом дерева решений, вопросы нумерованы и с рекомендованным ответом, *«finding facts is your job, never the user's»*.
- `to-spec` → `to-tickets`: вертикальные tracer-bullet срезы, каждый *«sized to fit in a single fresh context window»*, без путей к файлам.
- `tdd`: тест через публичный интерфейс на заранее согласованных швах; ожидаемые значения — из независимого источника.
- `code-review`: две изолированные оси (стандарты репо / соответствие спеке).
- `retro`: улучшает окружение, а не код; механическое нарушение → линтер/CI; CLAUDE.md *«used incredibly sparingly, usually only for navigation pointers»*.
**Применяется:** плечо P в `benchmark/pipeline-ab/` (плагин на зафиксированном коммите). Метод получения спеки и retro как операция «правило → оракул» сходятся с T1 (best-practices: интервью → `SPEC.md`); `tdd` вне курса лабы с 2026-10-27 — см. Böckeler ниже и `rules/testing.md`.

### Birgitta Böckeler — [TDD inside the agent loop – theater or actual value?](https://martinfowler.com/articles/exploring-gen-ai/tdd-in-the-agent-loop.html)
**Дата:** 10 августа 2026. Сверено 2026-10-27.
**Тезисы:** TDD-инструкция против её отсутствия на малой, средней и большой greenfield-задаче: *«no clearly discernable difference»* в качестве (слепое сравнение моделью-судьёй) и в mutation score; токенов ×3–8.5 (с оговоркой про cache reads). Агенты *«sometimes skipped or faked the red step»*, часть тестов тавтологична; TDD-инструкция работает против шага дизайна наперёд. Автор перестала просить test-first; взамен — mutation testing, статанализ, периодические ревью модульности, число файлов и токенов на изменение, Approved Scenarios.
**Ограничения:** по 2 прогона на плечо, генератор — модель Sonnet-тира прошлого поколения, судья — LLM, только greenfield.
**Применяется:** вместе с решением оператора 2026-10-27 — основание снять TDD из `rules/testing.md`; проверяется в `benchmark/pipeline-ab/` (mutation score собственных тестов агента по плечам). T4, измерено на малой выборке.

### Naresh Jain — [Are Harnesses Worth the Cost?](https://martinfowler.com/articles/are-harnesses-worth-the-cost.html)
**Дата:** 13 октября 2026. Полный текст сверен второй проверкой первоисточников 2026-10-27.
**Тезисы:** поведенческая обвязка (спеки, примеры, контрактные тесты) подняла дешёвую модель с 3/10 до 10/10 прогонов и обошлась на 33% дешевле передовой ($0.273 против $0.406); передовая проходит 178 приёмочных тестов 10/10 и без обвязки, а с ней тратит ×10.5 токенов, ×3 времени и ×7 денег. Вывод автора: *«What changes with model capability is when and how often the sensors run, not whether an independent check is needed.»*
**Ограничения:** конфликт интересов (автор — основатель Specmatic, обвязка на нём же), 10 парных прогонов, одна greenfield-задача, контракты писал сам автор. Совет «для передовой модели — только финальный гейт» **не проверялся** — автор сам называет его следующим сравнением.
**Применяется:** workflow.md § Work (строгость проверок по классу модели исполнителя). Сходится с arXiv 2609.20804 (блок 5). T4.

### HumanLayer — QRSPI: [интервью Heavybit с Dex Horthy](https://www.heavybit.com/library/article/whats-missing-to-make-ai-agents-mainstream) (17 мар 2026) и [скиллы RPI в открытом репо](https://github.com/humanlayer/humanlayer) (открыт 23 окт 2026, Apache-2.0)
**Сверено** по интервью и коду скиллов (`apps/riptide-rpi-claude-plugin/skills/`).
**Тезисы:** Questions → Research → Design discussion → Structure outline → Plan → Worktree → Implement; человек читает дизайн и outline структуры. Research **не видит задачу** — запретом в промпте скилла (*«DO NOT read ticket files — research must stay objective about the current codebase»*), тикет при этом лежит в том же каталоге; Horthy: *«if you tell the model what you're building, you get opinions»*. Читает человек **код, а не план**: *«Don't read the plans. Please read the code.»* По коду: каждая стадия — отдельная сессия, артефакты — нумерованные файлы `.humanlayer/tasks/<task>/NN-<type>-*.md`; движок авто-перехода (`check-auto-advance.ts`) намеренно **не** переходит design → outline и outline → implement — это и есть два человеческих гейта, обеспечены кодом, а не промптом. «≤40 инструкций» и «~200 строк дизайна» — формулировки статьи Heavybit, в коде лимитов нет (SKILL.md — 84–299 строк). Behavioral evals для RPI нет.
**Применяется:** кандидат (task-blind research для brownfield), не принят: один источник практики, исходов не мерили.

### Прочие сетапы (T4, кратко)
- [Geoffrey Huntley — ralph](https://github.com/ghuntley/how-to-ralph-wiggum): цикл агента со свежим контекстом и одним промптом; у Pocock развит в [Sandcastle](https://github.com/mattpocock/sandcastle).
- [HumanLayer — ACE-FCA](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents/blob/main/ace-fca.md): research → plan → implement, заполнение контекста 40–60%, человек ревьюит в точках наибольшего рычага.
- [Simon Willison — Agentic Engineering Patterns](https://simonwillison.net/guides/agentic-engineering-patterns/): red/green TDD, «first run the tests».
- [obra/superpowers](https://github.com/obra/superpowers) и [Every — compound engineering](https://github.com/EveryInc/compound-engineering-plugin): обязательные цепочки процессов — у Superpowers через один SessionStart-хук и промпты, у Compound Engineering хуков нет вовсе, маршрутизация промптами. Контрпример к нашему курсу (anti-pattern «процесс владеет агентом»), держим как ориентир того, что не делаем.

### Как устроены открытые обвязки — по коду (2026-10-27)
Код прочитан research-агентом из клонов на указанных коммитах; мной не перепроверен.
- **Порядок стадий почти везде держится промптом.** Кодом он обеспечен в немногих точках: движок переходов HumanLayer (два человеческих гейта), шаги `type: gate` в workflow-движке Spec Kit, один SessionStart-хук Superpowers, Stop-хук `ralph-loop`. Superpowers держит жёсткие места скриптами, которые модель вызывает сама: `task-done` не засчитывает задачу при красных тестах, цикл фиксов ≤5 раундов.
- **Компакция ломает процессные ограничения.** Superpowers v7.0.1: после компакции Claude Code возвращает каждый скилл обрезанным до 20k символов — потерялся лимит в 5 раундов, одна сессия сделала 18; лечат CI-тестом размера скилла (у Compound Engineering — такой же бюджет промпта в тестах). Сходится с arXiv 2610.31778 (блок 5).
- **Тесты везде пишет тот же агент-исполнитель.** Независимого оракула нет ни в одном проекте, кроме сценариев с подложенными дефектами в evals Superpowers и отдельных валидирующих субагентов в официальном `code-review`.
- **Самопроверка:** у Superpowers — набор Quorum (94 сценария, симулированный пользователь гонит настоящие CLI, плечи — зафиксированные коммиты плагина и `superpowers: none`, детерминированные пост-проверки плюс оценка моделью, n=1–2 на ячейку); у Compound Engineering — pre/post по git ref на трёх CLI, отчёты в репо, n=1. Обе меряют в основном соблюдение процесса, а не качество выпущенного кода. У Pocock, HumanLayer, Spec Kit, OpenSpec, официальных плагинов (`feature-dev`, `code-review`, `ralph-loop`) behavioral evals нет.
- **Детали, расходящиеся с описаниями:** Spec Kit `converge` только дописывает задачи в `tasks.md` или пишет «Converged», тестов не гоняет; «живых» спек у Spec Kit нет — их детерминированно сливает OpenSpec (`archive`, блоки ADDED/MODIFIED/REMOVED/RENAMED). `ralph-loop` из официальных плагинов повторяет промпт в той же сессии (не свежий процесс, как у Huntley) и без верификации. Репо Codex под Apache-2.0 с 2025 года; август 2026 — открытие упаковки exec/SDK/app-server, а заявка про ARC-AGI-3 опирается на серверную компакцию и не воспроизводится из открытого кода.
**Применяется:** дизайн `benchmark/pipeline-ab/` (симулированный пользователь, зафиксированные коммиты плеч, плечо без обвязки — тот же приём, что у Quorum, но с независимым скрытым оракулом вместо оценки моделью); `workflow.md` § Check — независимый оракул как то, чего нет ни у кого. T4/T6.
- [Armin Ronacher](https://lucumr.pocoo.org/2025/7/30/things-that-didnt-work/), [Peter Steinberger](https://steipete.me/posts/just-talk-to-it): «dumbest possible thing that works», неиспользуемая автоматизация удаляется.

**Срез июль–октябрь 2026** (по отчёту research-агента 2026-10-27; пункты с пометкой «сверено» прошли вторую проверку по первоисточникам):
- [Superpowers v6.0 → v7.0.1](https://github.com/obra/superpowers/blob/main/RELEASE-NOTES.md) (сверено): v6.0.0 (16 июн) — *«One reviewer per task, two verdicts… a single whole-branch review on the most capable model»*; v6.4.1 (18 сен) — `executing-plans` *«measured the same as running with no plugin at all»*; v6.4.2 (25 сен) — планы фиксируют решения вместо полного кода; v7.0.1 (21 окт) — design doc пропускался в 24 из 24 прогонов, после правки в 3 из 24. Правило контрибьюторов в AGENTS.md: *«Skill Changes Require Evaluation… Show before/after eval results in your PR»*. Остаётся обязательной цепочкой.
- Compound Engineering v3.30: *«dispatch subagents only when they pay off»*.
- Spec-driven: Spec Kit 1.0 (21 авг) → 1.2.4 — цикл implement/converge до «Converged», отдельный поток для багов; OpenSpec 1.15 — спека как дельта к существующей системе, сливается в живую спеку при архивации (brownfield); Kiro CLI v3 — property-based тесты из EARS-требований; BMAD 6.12 масштабирует процесс по размеру изменения; Tessl отказался от «spec as source». Данных об исходах ни у кого нет.
- [Yegge, «The Shape of Things to Come»](https://yegge.ai/essays/the-shape-of-things-to-come/) (август 2026, сверено): Gas Town *«fell apart»* на новой модели, и он отказался от **переиспользуемых** обвязок — *«I have given up on building reusable harnesses»*, обвязка должна быть встроена в приложение. Оркестрацию он **не** свернул: своя Wheelhouse на Beads, *«40+ agents around the clock»*, *«crons watch, models act»*. Это аргумент против готовых фреймворков, а не против многих агентов.
- Uncle Bob (посты в X 11, 14, 18 сен и 16 окт, сверено через зеркало): мультиагентная обвязка стала не нужна — *«A single disciplined agent can now take on big tasks that used to need a swarm-forge harness»*, токенов *«fallen by a huge factor»*; CRAP, mutation testing и юнит-тесты оставил ([`uml-viewer`](https://github.com/unclebob/uml-viewer) красит диаграмму по CRAP и мутациям). Сравнение «один агент быстрее и лучше на одной задаче» — пересказ третьей стороны, у автора не найдено.
- [StrongDM Software Factory](https://factory.strongdm.ai) (6 фев, сверено): сценарии «user story» хранятся *«often… outside the codebase (similar to a 'holdout' set in model training)»* и проверяются моделью; *«return true is a great way to pass narrowly written tests»*.
- [Hammant, «Red-green-refactor moves into the harness»](https://paulhammant.com/2026/10/14/red-green-refactor-moves-into-the-harness/) (14 окт, сверено): каждый новый тест прогоняется против предыдущего коммита и обязан там падать — «был красным до зелёного» проверяет машина, а не ритуал; в паре с mutation testing.
- Ревью по исключению: Laycock (2 сен); Thorsten Ball — [доклад Amp 13 окт](https://ampcode.com/time-capsules/6) и статья 25 окт (сверено): *«I only review load-bearing code»*, *«Give me irrefutable proof that this works now»*, *«Make the whole SDLC legible to the agent»*.
- «Loop engineering» (Steinberger, Osmani, июнь–август) — лозунг без данных об исходах; Osmani «Audit your Agent files» (27 авг) — периодически удалять обвязку и прогонять агента без неё.
- Thoughtworks Radar Vol 34 (**апрель 2026**, вне среза; размещения сверены): coding-agent swarms (примеры — Gas Town, Ruflo) и agent instruction bloat — Caution; Superpowers, Ralph loop, Beads — Assess. Vol 35 выходит 4 ноября.
- **Сходится у 3+ независимых:** меньше обвязки с ростом модели; человек выравнивается на коротком дизайн-артефакте, а не на длинном плане; проверка исполнимыми оракулами, которые исполнитель не пишет и не может подыграть (mutation testing, независимые приёмочные тесты, скрытые сценарии); одно ревью всей ветки вместо ревью на каждую задачу; граф задач вне контекста. **Спорно:** TDD как инструкция; читает ли человек код; мультиагентная оркестрация против одного сильного агента; живые спеки против одноразовых.

## Блок 5 — Research papers (peer-reviewed / arXiv)

### [arXiv 2603.25723 — Tsinghua «Natural-Language Agent Harnesses (NLAH)»](https://arxiv.org/abs/2603.25723)
**Авторы:** Pan, Zou, Guo, Ni, Zheng. Март 2026.
**Тезисы:** Harness как редактируемый natural-language артефакт. Три опоры:
1. **Explicit contracts** (rules / API constraints / testing invariants)
2. **Durable artifacts** (ADR, журналы решений, MEMORY.md)
3. **Lightweight adapters** (hooks для gating/observability, не для logic).
Runtime = Intelligent Harness Runtime (IHR).
**Применяется:** `.claude/rules/*.md` = contracts, `.claude/docs/adr/` + `RESULTS.md` стендов = artifacts, hooks = adapters. См. `reference_harness_papers_2026.md` memory.

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

### Файлы инструкций агента (CLAUDE.md / AGENTS.md) — эмпирика 2025–2026
**Эффект на работу агента (эксперименты):**
- [arXiv 2602.11988 — ETH Zurich «Evaluating AGENTS.md»](https://arxiv.org/abs/2602.11988) (v3, сен 2026; Claude Code/Codex/Qwen): success rate — изменения незначимы (LLM-файл −0.5…−2 п.п., авторский +2.4 п.п.), стоимость **+20–23%** и +2.5…3.9 шага (p<0.001). Конкретные инструкции исполняются (`uv` 1.6 раза на задачу против <0.01). Обзоры репозитория не ускоряют навигацию. Рекомендация — только то, чего нет в кодовой базе. Внимание: цифры v1 были сильнее, вторичные пересказы их тиражируют.
- [arXiv 2607.27250 — Two-Agent Ablation](https://arxiv.org/abs/2607.27250): 288 прогонов, эквивалентность в пределах ≤10 п.п.; агенты падают на реализации, а не на незнании репо.
- [arXiv 2601.20404 — AGENTS.md и эффективность](https://arxiv.org/abs/2601.20404): малые PR, один агент — −29% времени, −17% выходных токенов; корректность не мерилась.
- [arXiv 2605.10039 — Instruction Adherence](https://arxiv.org/abs/2605.10039): 16k наблюдений, Claude CLI — размер файла 25→500 строк, позиция, число файлов и конфликт **не влияют** на соблюдение (BF 0.05–0.10). Раздутость бьёт по стоимости, а не по соблюдению.
**Что пишут (описательные):** [2511.12884 Agent READMEs](https://arxiv.org/abs/2511.12884) — 2 303 файла, растут добавлениями, удаляют редко; [2606.15828 Configuration Smells](https://arxiv.org/abs/2606.15828) — Lint Leakage 62%, Context Bloat 42%, Conflicting Instructions 28%, Init Fossilization 24% (вред утверждается, не меряется).
**Глобальный (user-level) файл:** исследований нет.
**Применяется:** rule #0 docs-discipline (только невыводимое); строка проверяется прогоном с ней и без неё, а не рассуждением.

### Файлы инструкций у индустрии (T1/T4, прочитаны файлы, 2026-10-05)
- **Anthropic:** [best-practices](https://code.claude.com/docs/en/best-practices) — таблица include/exclude и тест «Would removing this cause Claude to make mistakes?»; [memory](https://code.claude.com/docs/en/memory) — user-level файл для «code styling preferences, personal tooling shortcuts». Собственные корневые файлы 36–58 строк ([claude-code](https://github.com/anthropics/claude-code/blob/main/CLAUDE.md) — только харденинг CI).
- **Проектный скелет**, повторяющийся у большинства (ghostty, uv, ruff, workers-sdk, pydantic-ai, Willison, Ronacher): команды build/test/lint → конвенции, отличные от дефолта → ловушки и генерируемые файлы → PR/коммиты. Тренд — `AGENTS.md` как источник, `CLAUDE.md` = `@AGENTS.md`; процедуры уходят в skills. `openai/codex` удалил корневой AGENTS.md 2026-09-30.
- **Глобальные файлы:** [Steinberger](https://github.com/steipete/agent-scripts/blob/main/AGENTS.MD) (119 строк: общение, маршрутизация на skills, git/секреты, «no attribution trailers»), [obra](https://github.com/obra/dotfiles/blob/main/.claude/CLAUDE.md) (114 строк, персона и КАПС-MUST — контрпример), Boris Cherny — личный файл ~76 токенов (по [InfoQ](https://infoq.com/news/2026/01/claude-code-creator-workflow/), сам файл не опубликован), Pocock — [две строки о краткости планов](https://www.aihero.dev/my-agents-md-file-for-building-plans-you-actually-read). Команд сборки в глобальных нет ни у кого.
**Применяется:** скелет глобального слоя — только личное и межпроектное: общение (если отличается от дефолта), личные инструменты, которые модель не угадает, git/внешние действия. Проектное — в проект.

### Полный цикл с агентами — замеры, март–октябрь 2026
- [arXiv 2607.21656 — Cross-Model LLM Code Review](https://arxiv.org/abs/2607.21656) (Xiang et al., 22 июл; **сверено**): 116 задач LiveCodeBench, ревьюер видит задачу и черновик, код не исполняет. Claude соло 91.4%, self-review ничего не меняет, ревью Codex → 82.8% (−8.6 п.п., p_BH=.046); Codex соло 71.6%, ревью Claude → 89.7% (+18.1, p=.001), self-review → 84.5%. **Ценность ревью зависит от направления**: более слабый ревьюер, чьи находки применяются, ухудшает сильного автора. Ограничения: изолированные функции, одна пара моделей, статический ревьюер.
- [arXiv 2609.20804 — harness-ablation](https://arxiv.org/abs/2609.20804) (17 сен): четыре open-weight модели, SWE-bench Verified + Terminal-Bench 2.1, обвязка фиксирована. Шаг планирования поднимает слабую модель 13.6 → 25.2%, сильным не меняет успех, но режет стоимость на 30–40%. Управление контекстом окупается в основном как защита от переполнения (+14–54 п.п. при окне 32k, +2.7 при 128k). Передовые модели не тестировались.
- [arXiv 2604.05278 — Spec Kit Agents](https://arxiv.org/html/2604.05278v1): spec → plan → tasks 3.51 против 3.46 у прямой реализации (шкала 1–5, LLM-судья), но бюджет 90 против 40 минут — переменная из вывода не изолирована.
- [arXiv 2608.17177](https://arxiv.org/abs/2608.17177) (Google, авг): агент пишет пред- и постусловия до тестов → +9.8 п.п. найденных багов (p=.035), +2.5 п.п. покрытия ветвей.
- [arXiv 2603.17973 — TDAD](https://arxiv.org/abs/2603.17973): доля регрессий 6.08% у агента без инструкций, 9.94% с одной TDD-инструкцией, 1.82% с картой «какие тесты покрывают какой код». Малые выборки, open-weight модели.
- [arXiv 2602.07900](https://arxiv.org/abs/2602.07900): объём тестов, которые пишет агент, не меняет resolution на SWE-bench Verified (скрытые тесты — независимый оракул), меняет процесс и стоимость.
- [arXiv 2606.05670 — Do More Agents Help?](https://arxiv.org/abs/2606.05670) (v2, 9 окт): из шести мультиагентных схем одиночного агента обгоняет одна (+3.05 п.п. в сумме), токенов до ×14. Функциональные задачи, без тестов значимости.
- [arXiv 2609.37985 — Merged, Not Measured](https://arxiv.org/abs/2609.37985) (29 сен): автор мёржит PR своего агента сам в 81–95% случаев; из 30 смёрженных perf-фиксов заявленный прирост дали 18. Доля мёржа — плохой прокси качества.
- Полевые: [METR](https://metr.org/blog/2026-02-24-uplift-update/) (24 фев) — доверительные интервалы включают ноль, дизайн исследования переделывается; Microsoft [2607.01418](https://arxiv.org/abs/2607.01418) — +24% смёрженных PR, метрик качества нет, авторы аффилированы с вендором; CMU [2601.13597](https://arxiv.org/abs/2601.13597) — +18% предупреждений статанализа и +39% когнитивной сложности, стойко во времени.
- **Не измерено никем:** свежий контекст на каждый срез против длинной сессии на реальных репо с передовыми моделями; TDD с передовыми моделями на независимом оракуле; спека, прочитанная человеком, против плана, который агент пишет сам; параллельные исполнители на реальных репо; связь любой практики с продовыми дефектами.
**Происхождение:** всё, кроме 2607.21656, — по отчёту research-агента 2026-10-27 (абстракты/HTML прочитаны им). **Применяется:** multi-agent.md §7.3 (направление ревью), workflow.md, дизайн `benchmark/pipeline-ab/`. T3.

### Полный цикл с агентами — второй проход по пробелам (2026-10-27)
- **Параллельные исполнители.** [arXiv 2610.10263 — When Sub-Agents Work in Parallel](https://arxiv.org/abs/2610.10263) (Li et al., 7 окт; **сверено по полному тексту**): Codex, Claude Code и Kimi Code на высшем effort, параллельные субагенты включены/выключены при прочих равных, 354 задачи, 2 124 прогона. SWE-bench Verified (100 задач): Claude Code на передовой модели Anthropic 59.0% с параллельностью против 83.0% без неё, Kimi 59 против 77, Codex 71 против 71; McNemar–Holm p≈5·10⁻⁷ для Claude Code. Токенов ×1.4–3.3, время не сократилось в 14 из 15 комбинаций; крупнейший класс сбоев — общее состояние и слияние (33.2%). Выигрыш бывает только на длинных задачах; вывод авторов — *«enabled selectively rather than by default»*. В ту же сторону: [CooperBench 2601.13295](https://arxiv.org/abs/2601.13295) — два агента над парой фич дают примерно половину успеха одного, 2/3/4 агента — 68.6 / 46.5 / 30.0%; [CAID 2603.21489](https://arxiv.org/abs/2603.21489) — менеджер + исполнители в worktree дают +6 п.п. при ×2–4 стоимости и без выигрыша по времени, общий рабочий каталог хуже одного агента.
- **Независимые тесты против тестов после кода.** [arXiv 2607.05139](https://arxiv.org/abs/2607.05139) (Konstantinou, Tambon, Papadakis, 6 июл; аннотация сверена): тесты, сгенерированные после ошибочного кода, находят 14% ошибок против 25% у сгенерированных независимо; ошибки кода *«systematically replicated»* в тестах, chain-of-thought разрыв не закрывает. Функциональные задачи, небольшие модели; независимость смешана со свежим контекстом. [TestSuiteBench 2610.13065](https://arxiv.org/abs/2610.13065) (группа Vechev): тест-сьюты передовых агентов дают <60% mutation score, хотя их реализации по той же спеке проходят 82% эталонных тестов.
- **Компакция и ограничения.** [arXiv 2610.31778 — Benchmarks Are Surprisingly Compaction-Friendly](https://arxiv.org/abs/2610.31778) (22 окт): порог и стратегия компакции у моделей с окном 1M почти не влияют на успех, но на 269 реальных ограничениях компакция теряет 6.2% требований к фиче против 35.9% процессных инструкций и 36.8% исключений scope. [2606.11213](https://arxiv.org/abs/2606.11213), [2610.09633](https://arxiv.org/abs/2610.09633): длинная сессия против свежей на независимых задачах и разбиение задачи на три хода — успех в пределах шума, стоимость ×2.
- **Вопросы при недоопределённой задаче.** [Ask or Assume? 2603.26233](https://arxiv.org/abs/2603.26233) (EMNLP): SWE-bench Verified со скрытой частью задачи и симулированным пользователем — полная спека 70.8, без вопросов 54.8, с разрешением спрашивать 61.2–70.4 (простая строка «задача неполна, можно спрашивать» дала 70.4 одной модели и 47.2 другой). [ICAE-Bench 2607.21217](https://arxiv.org/abs/2607.21217): больше вопросов ≠ лучше. [ReqClarifyBench 2610.13022](https://arxiv.org/abs/2610.13022): код по документу после уточнений против исходного намерения — 0.66 против 0.27 и 0.94 против 0.45 (оценка судьями-моделями).
- **Ревью.** [SWE-Review 2607.06065](https://arxiv.org/abs/2607.06065): агентный ревьюер сильной модели на 1 384 PR, скрытые тесты — у более слабых авторов resolve растёт (50.9 → 67.3, 27.5 → 52.6), выигрыш тает, когда автор приближается к ревьюеру; ложных отклонений 105 и ложных одобрений 167 из 1 500. [SWE-PRBench 2603.26130](https://arxiv.org/abs/2603.26130): модели ловят 15–31% замечаний людей и хуже работают с ростом контекста ревью.
- **Абляции обвязки при фиксированной модели.** [2607.10569](https://arxiv.org/abs/2607.10569) (Claude Code и Codex CLI, три набора инструментов) и [The Scaffold Effect 2607.22585](https://arxiv.org/abs/2607.22585): успех статистически равен, двигается стоимость (до ×40 токенов на решённую задачу).
- **Валидность оракулов.** METR (10 мар): мейнтейнеры смёржили бы примерно на 24 п.п. меньше PR, прошедших SWE-bench, чем засчитывает грейдер. Anthropic «infrastructure noise» (5 фев): одна конфигурация ресурсов двигает Terminal-Bench на 6 п.п. — разницу меньше ~3 п.п. считать недоказанной.
- **Остаётся не измерено:** свежий контекст на срез одной фичи; TDD с передовыми моделями на независимом оракуле; спека, прочитанная человеком, против плана агента.
**Происхождение:** 2610.10263 и 2607.05139 сверены мной, остальное — по отчёту research-агента (абстракты/HTML прочитаны им). **Применяется:** workflow.md (§ Spec — ограничения в файле, вопросы; § Check — независимый оракул; § Build — параллельность не по умолчанию), multi-agent.md §2.2. T3.

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
