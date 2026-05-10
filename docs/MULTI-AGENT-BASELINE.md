# Multi-agent baseline (Opus 4.7 + наш harness)

> Baseline для построения multi-agent workflows **в проектах**, использующих этот harness. **Не** про baseline самого harness'а — это `HARNESS-DECISIONS.md`. Evidence-based: цифры и паттерны взяты из canonical Anthropic статей + наших ADR'ов. Дата компиляции: **2026-05-10**.
>
> Источники: PRACTICES-FROM-PROJECTS.md §12.1 (Anthropic official) и §12.7-12.8 (community 2026 essays). Re-evaluate при major-релизе модели или N≥3 промахах в одном classes-of-tasks (см. meta-CLAUDE.md «Re-evaluation triggers»).

## TL;DR

1. **Default to single-agent main thread**. Multi-agent оправдан только при breadth-first parallelism или context isolation. **Высоко-зависимые задачи (most coding) — ill-suited** (Anthropic).
2. **Token overhead**: single-agent = ~4× обычного chat'а; multi-agent = ~15×. **80% variance производительности объясняется token usage** (Anthropic BrowseComp eval).
3. **Lead Opus 4.7 + Sonnet 4.6 subagents** дают **+90.2%** к single-Opus baseline (Anthropic). Haiku 4.5 — для grunt subagents (file scans, log filtering, API pulls).
4. **Brief subagent как нового коллегу**: цель + формат вывода + границы + tool preferences. Короткий brief → spawn-spam, дублирование, gaps.
5. **Effort scaling**: 1 agent для facts → 2-4 для сравнений → 10+ для multi-aspect research.
6. **Built-ins-first** (Explore / Plan / general-purpose) до создания custom `.claude/agents/`.

---

## 1. Mental model (4 layers)

| Layer       | Where                                  | Lifetime               | Use for                          |
| ----------- | -------------------------------------- | ---------------------- | -------------------------------- |
| Harness     | `.claude/` + Claude Code daemon        | persistent             | runtime, hooks, settings         |
| Main agent  | session main thread                    | session                | reasoning, integration, delivery |
| Skills      | `Skill` tool, `.claude/skills/`        | per-call в same window | reusable workflows               |
| Subagents   | `Agent` tool, `.claude/agents/`        | one-way return         | isolated / parallel work         |
| Teams       | `claude --bare --print --add-dir`      | separate processes     | bidirectional cross-agent (CI)   |

**Главный failure mode** (Anthropic 2026): «using the right tool in the wrong layer».
- Behavioural constraint → **hook** (deterministic), не system prompt (interpretive).
- Reusable instruction → **skill**, не copy-paste в каждый turn.
- Isolated search-heavy task → **subagent**, не main thread с verbose dump'ом.

---

## 2. Когда spawn'ить subagent

### 2.1 Legitimate triggers (из meta-CLAUDE.md `Sub-agent spawn policy`)

| Trigger                          | Пример                                  | Wall-clock cut?      | Token cost |
| -------------------------------- | --------------------------------------- | -------------------- | ---------- |
| (а) Изоляция контекста           | broad codebase scan, 50+ files, log dive | нет                  | 4-15×      |
| (б) Параллельность               | N независимых verifications/researches  | да: max(N) vs sum    | 4-15×      |
| (в) Auto-compact rescue          | редко при 1M context Opus 4.7           | n/a                  | 4-15×      |

### 2.2 Bad fit (Anthropic explicit)

- **High-dependency tasks** (most coding) — sequential context loss → telephone-game.
- Tasks где **все agents требуют full context** — изоляция бесполезна.
- **Single dependency chain** (A → B → C) — sequential calls = N× tokens, 0 выигрыша.
- **Trivial task** — main thread с полным контекстом проекта быстрее.

---

## 3. Subagent contract

### 3.1 Brief как нового коллегу (5 обязательных элементов)

1. **Конкретная цель** (не «research semiconductors», а «list top 5 EUV lithography vendors with 2025 revenue»).
2. **Формат вывода** (structured fields / JSON / markdown checklist), желательно с лимитом длины.
3. **Tool / source preferences** — какие tools использовать, какие источники предпочесть.
4. **Boundaries** — что включать / исключать.
5. **Что уже исследовано** — чтобы не дублировать.

**Anthropic evidence**: короткие briefs → subagents дублируют (один исследовал кризис 2021, два других параллельно те же 2025 supply chains без разделения труда).

### 3.2 Effort scaling (Anthropic empirical)

| Complexity                    | Subagents | Tool calls / agent |
| ----------------------------- | --------- | ------------------ |
| Простой факт                  | 1         | 3-10               |
| Прямое сравнение              | 2-4       | 10-15              |
| Multi-aspect research         | 10+       | varies (с разделением) |

Над-scaling («50 subagents для простой query») — failure mode, фиксированный Anthropic. Решение: explicit effort-scaling в prompts.

### 3.3 Skill preloading

Subagents **не наследуют parent skills** (Anthropic 2026 change). Если нужен — explicit в frontmatter:

```yaml
---
name: api-developer
description: Implement API endpoints following team conventions
skills:
  - api-conventions
  - error-handling-patterns
---
```

Полный текст skill'а инжектится при startup, не «доступен по требованию».

### 3.4 Return format

Возвращай **structured summary**, не raw transcript. Tool result субагента — не пользовательский. Финальный пользовательский summary пишет main thread.

---

## 4. Built-ins-first

Перед созданием custom subagent — `claude agents` lookup:

| Built-in            | Покрывает                                      | Заменяет custom-агентов |
| ------------------- | ---------------------------------------------- | ----------------------- |
| `Explore`           | read-only research, locating code, references | search-агентов          |
| `Plan`              | implementation strategy, critical files        | architects              |
| `general-purpose`   | open-ended multi-step research                 | catch-all               |
| `statusline-setup`  | niche                                          | —                       |

В **нашем harness'е** custom = 2 (`deliverable-planner`, `meta-creator`). Это minimal достаточный набор после Stage 2 trim'а (см. ADR-007 / ADR-011: 6 skills + 3 agents удалены как duplicate built-ins). Любое расширение — через симметричное правило (N≥3 промахи).

---

## 5. Token economics (Anthropic measurements)

| Mode               | Token cost vs chat | Источник            |
| ------------------ | ------------------ | ------------------- |
| Single agent       | ~4×                | Anthropic eval      |
| Multi-agent        | ~15×               | Anthropic eval      |
| Variance объяснитель #1 | 80% — token usage  | BrowseComp eval     |
| Variance объяснитель #2 | tool call count    | BrowseComp eval     |
| Variance объяснитель #3 | model choice       | BrowseComp eval     |

**Implication**: token throw **не заменяет** model upgrade. «Sonnet 4 upgrade > doubling Sonnet 3.7 budget» (Anthropic). Под Opus 4.7 модель уже на максимуме; subagent-spam без isolation/parallelism gain — чистый overhead.

---

## 6. Cost optimization — model assignment

| Role               | Model       | Зачем                                       |
| ------------------ | ----------- | ------------------------------------------- |
| Main agent (lead)  | Opus 4.7    | Reasoning, planning, integration            |
| Reasoning subagent | Sonnet 4.6  | Quality reasoning at lower cost             |
| Grunt subagent     | Haiku 4.5   | File scans, log filtering, API pulls        |

Override: `Agent({model: "haiku"})`. Empirical: **Opus lead + Sonnet subagents = +90.2%** к single-Opus baseline (Anthropic eval). Haiku для grunt — без quality loss на грубой работе.

---

## 7. Workflow patterns (Anthropic taxonomy)

| Pattern              | Когда                       | Cost          | Tradeoff                |
| -------------------- | --------------------------- | ------------- | ----------------------- |
| Sequential           | dependencies (B uses A)     | 1×            | latency                 |
| Parallel             | independent + latency-bound | N×            | aggregation strategy    |
| Evaluator-Optimizer  | first-draft недостаточно    | iterations × N| iteration time          |

**Default**: sequential. Upgrade когда latency или quality measurably bottleneck'ом.

### 7.1 Конкретные patterns в наших проектах

- ✅ **Parallel research**: N subagents по разным aspects (security / types / perf), main integrate'ит.
- ✅ **Parallel verification**: tests / lint / type-check как 3 subagents после refactor.
- ✅ **Context-heavy isolation**: broad codebase scan через 50+ файлов.
- ✅ **Worktree parallelism**: independent feature branches via `isolation: "worktree"` (требует stable layered architecture).
- ❌ **Workflow-phase split** (Plan→Code→Test→Review) — anti-pattern (см. §8).

---

## 8. Anti-patterns (запрещены ADR'ами нашего harness'а)

| Anti-pattern                                 | ADR / источник                  | Замена                                                    |
| -------------------------------------------- | ------------------------------- | --------------------------------------------------------- |
| TDD-тройка test-writer / impl / refactor     | ADR-002                         | Single context + TaskCreate phases + `rules/testing.md`   |
| PM → Architect → Dev → QA pipeline           | meta-CLAUDE.md                  | Main thread + built-in `Plan` для design                  |
| Generator/Evaluator контракт каждый sprint   | meta-CLAUDE.md                  | Opus 4.7 «devises ways to verify own outputs»             |
| Custom subagent дублирующий built-in         | ADR-007                         | `claude agents` check **до** создания                     |
| code-reviewer как custom agent               | ADR-011                         | Built-in `/review` или main thread + diff                 |
| Multi-agent для sequential dependency chain  | Anthropic [multi-agent-systems] | Single agent + TaskCreate                                 |
| Subagent как wrapper над одним tool call     | принцип                         | Direct tool call в main thread                            |
| Multi-agent для most coding                  | Anthropic explicit              | Main thread + parallel verification только после impl     |

---

## 9. Failure modes (Anthropic empirical) → guard rails

| Failure                                         | Guard                                                  |
| ----------------------------------------------- | ------------------------------------------------------ |
| 50 subagents для простой query                  | Explicit effort scaling в prompts (§3.2)               |
| Infinite web scraping для несуществующих source | Teach «recognize sufficient information»               |
| Subagent overlap, дублирование                  | Clear task boundaries в brief'е (§3.1)                 |
| Verbose search queries, few results             | Strategy: «start wide, progressively narrow»           |
| Wrong tool choice                               | Explicit «examine tools first, match to intent»        |
| Emergent cascade behaviors                      | Lead-prompt edits = test малыми изменениями, валидация |
| Stateful errors compound                        | Durability + checkpoint resumption, не full restart    |
| Non-determinism между runs                      | Eval rubric — single sample недостаточен               |

---

## 10. Verification — checklist перед каждым spawn'ом

5 вопросов main thread'а перед `Agent` tool call:

1. **Trigger** (§2): один из (а), (б), (в)? Если ни один — main thread сделает сам.
2. **Built-in coverage**: `claude agents` checked? Если built-in покрывает — без custom.
3. **Brief completeness**: цель + формат + boundaries + sources + exclusions — все 5 есть?
4. **Effort scaling**: complexity matches количеству subagents (§3.2)?
5. **Result format**: structured? Не raw dump?

«Нет» на любой вопрос → spawn не оправдан, main thread выполняет.

---

## 11. Production evaluation (для проектов, строящих production multi-agent)

Для baseline-разработки в нашем harness'е достаточно §1-10. Если проект разворачивает multi-agent в production — Anthropic empirical rubric:

- **LLM-as-judge**, single call, scores 0.0-1.0 + pass/fail — наиболее consistent.
- **Sample 20 queries** реальных patterns — достаточно для measuring 30%→80% changes.
- **Human eval** обязательна для bias detection (LLM judges склонны к SEO-optimized over authoritative sources).
- **Rubric dimensions**: factual accuracy, citation accuracy, completeness, source quality, tool efficiency.

---

## 12. Re-evaluation triggers

Этот baseline **не invariant** — frozen on date 2026-05-10. Re-evaluate когда:

- **Major-релиз модели** (4.x → 5.x): прогон проектных multi-agent workflows на классах задач, где они критичны.
- **N≥3 эмпирических промаха** одного типа (наблюдаемый telephone-game / token-overhead inefficiency / failure mode не в §9).
- **Breaking change в built-in каталоге** Claude Code (новый built-in agent заменяет custom-паттерн baseline'а).

См. также `docs/HARNESS-DECISIONS.md` ADR-002 (запрет TDD-тройки), ADR-007 (built-ins-first revisited), ADR-011 (retire code-reviewer).

---

## References

- [Anthropic — Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) — canonical: 90.2%, 4×/15× tokens, 80% variance, failure modes
- [Anthropic — Common workflow patterns](https://claude.com/blog/common-workflow-patterns-for-ai-agents-and-when-to-use-them) — sequential / parallel / evaluator-optimizer taxonomy
- [Anthropic — Best practices Opus 4.7](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code) — «spawns fewer subagents by default»
- [Anthropic — Effective harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic — Harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [ofox.ai 2026 guide](https://ofox.ai/blog/claude-code-hooks-subagents-skills-complete-guide-2026/) — 4-layer mental model
- [boringbot.substack — Skills, Subagents, Hooks, Plugins, and Harnesses](https://boringbot.substack.com/p/claude-code-skills-subagents-hooks)
- [blakecrosley.com — Agent Architecture](https://blakecrosley.com/guides/agent-architecture)
- [mcp.directory — Best Practices 2026](https://mcp.directory/blog/claude-code-best-practices)
- [developersdigest 2026 playbook](https://www.developersdigest.tech/blog/claude-code-agent-teams-subagents-2026)
- Полный список — `PRACTICES-FROM-PROJECTS.md` §12.1, §12.7-12.8
