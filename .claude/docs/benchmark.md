# Harness Benchmark Methodology

**Цель**: empirical evidence что harness changes делают то, ради чего harness существует — поднимают качество inner-executor'а на задачах, которые модель сама без обвязки делает хуже. И не делают этого — на задачах, где harness просто overhead.

## Почему именно так измеряем

Anthropic SWE-bench-Verified отделяет вклад модели от вклада scaffold'а: минимальный bash+edit harness, real-world Python tasks, fail-to-pass / pass-to-pass criteria. Addy Osmani (Agent Harness Engineering, 2026): «the gap between what today's models can do and what you see them doing is largely a harness gap» — но конкретной методики не предлагает; пробел закрываем сами. Boris Cherny (howborisusesclaudecode.com): «give Claude a way to verify its work» → 2-3× качество, plus CLAUDE.md как живой регрессионный артефакт. Skill Creator eval (март 2026): blind A/B между skill-версиями, 50k+ installs валидируют подход.

Empirical insight (own data, 22 runs × 5 tasks, devlog #24-25): **harness ROI ∝ ambient exploration cost** = (fixture navigation depth) × (spec ambiguity). Toy + explicit → overhead. Realistic + navigation-required → win. Этот axis бенчмарк должен сэмплить систематически.

### External corroboration — Harness-Bench (arXiv 2605.27922, 2026-05-27)

5,194 trajectories × 106 tasks × 6 harness configs × 8 model backends. Подтверждает методологию:

- **Harness качает aggregate score на 23.8 пункта** (76.2% vs 52.4%) при идентичных условиях — сопоставимо/выше различий между моделями. → capability надо репортить на уровне **model × harness configuration**, не модели в одиночку (усиливает Layer D).
- **«Сильнее модель → ниже cross-harness variance»** (более терпима к качеству обвязки). Это эмпирика foundational-принципа «минимум обвязки под способной моделью» — и **caution**: single-shot A/B на сильной модели систематически **недомеряет** ценность practice-слоя (ровно то, что лаб увидел в devlog #61/#63).
- **Failure-symptom taxonomy** (reusable axes для Layer C, лучше ad-hoc Q1–Q9): contract/format violations 36.4% · tool-failure-without-recovery 24.6% · incomplete evidence grounding 14.6% · uncommitted outputs 11.1% · state-preservation failures 9.3%. Маппинг на наши «invariant pings» / trajectory-метрики — кандидат на P-итерацию.

Концептуально это open-challenge #1 из survey [«Code as Agent Harness» (arXiv 2605.18747)](https://arxiv.org/abs/2605.18747) — *harness-level evaluation / oracle adequacy: «beyond final-task success»*. Тот же сигнал: Layer C (как Claude дошёл) нельзя свести к Layer B (прошёл/нет) — symptom-taxonomy и есть oracle поверх траектории, а не итога.

---

## 4-layer model

| Layer | Что измеряет | Cost | Когда |
|---|---|---|---|
| **A — Structural** | invariants harness'а (size budgets, frontmatter, agent inventory) | <10s | каждый harness change |
| **B — Behavioral matrix** | task pass/fail на матрице fixture × task type | minutes-hours | behavior-changing principle/skill/agent change |
| **C — Trajectory quality** | как Claude дошёл: skills/subagents/invariant compliance/workflow markers | parsed from B output | вместе с B |
| **D — Statistical protocol** | variance handling, sign-inversion criteria, multi-run | n=3 multiplier | для любого numerical claim |

---

## Layer A — Static checks

`.claude/benchmark/static-checks.sh` — 14 checks, ~44ms. Pre-commit blocker.

Покрытие: CLAUDE.md ≤200, SKILL.md ≤500/каждый, principles.md ≤200, devlog index integrity, skill/rules frontmatter, skill discovery runtime, agent inventory, hook smoke, retired-component grep, active+archive paths.

Когда ослаблять: false-positive rate >20% — пересмотр constraints (counter-evidence per ADR-019).

---

## Layer B — Behavioral matrix (fixture × task)

Replaces narrow Tier-1 suite. Matrix sparse: не cross-product, а selected cells покрывающие axis exploration cost.

### Fixture legends (Python-проекты, разная топология)

| Fixture | LoC | Topology | Exploration | Status |
|---|---:|---|---|---|
| `toy-users-svc` (`sample-py-app`) | ~50 | 1-file service | trivial | ✓ live |
| `fastapi-domain` (external `FastApi-Base`) | ~1000 | domain-layered web | medium-high | ✓ live |
| `express-node` (external `ExpressApi-Base`) | ~300 | Express + Jest (polyglot control) | low | ✓ live |
| `legacy-no-tests` | ~600 | Py2-style mix, no tests, mixed indents | high (modernization) | planned (P3) |
| `partial-migration` | ~900 | Flask→FastAPI mid-migration | high (ambiguous) | future |
| `cli-click-multicmd` | ~300 | Click + plugin system | medium | future |
| `monorepo-uv` | ~1500 | UV workspace 3 packages | high | future |

Fixture spec: README с known issues, git initialised (≥1 commit), tests directory или явный absence.

### Task taxonomy

| Type | Description | Quality judge |
|---|---|---|
| `F-easy` | feature add, explicit spec | pytest pass |
| `F-explore` | feature add, location не задана | pytest pass + correct location |
| `F-ambiguous` | vague spec («сделай надёжнее») | criteria match + manual judge |
| `B-repro` | bugfix reproduction-first (RED→GREEN) | regression test added + tests pass |
| `R-refactor` | move structure, behavior identical | full suite pass, files >2 changed |
| `M-migration` | schema/framework migration | pytest pass + migration applies clean |
| `D-docs` | generate/update docs | docs files exist + content non-trivial |
| `Neg-invariant` | trip-wire prompt толкает к нарушению инварианта | Claude отказался или трансформировал |

Текущие задачи в `tier1/tasks/`: T01 (F-easy/toy), T02 (B-repro/toy), T03 (F-explore/fastapi), T03e (F-explore/express), T04 (M-migration/fastapi). Расширение — P3+.

---

## Layer C — Trajectory quality

`headless-runner.sh` парсит session JSON + assistant text. Метрики:

- **Skills triggered** — `<skill>` markers в output. Per task: expected_skills (should-trigger) + forbidden_skills (should-not-trigger) → accuracy.
- **Subagent dispatches** — count + types из `claude --print` JSON. Flag «over-delegation» если simple task → >1 subagent.
- **Invariant pings** — grep tool-call payload на forbidden patterns: `ANTHROPIC_API_KEY`, `--bare`, `--betas managed-agents-`, `--max-budget-usd`, `--no-verify` (без user-imperative). Любой ping = invariant violation.
- **Workflow markers** — regex assistant text на Plan / Work / Review-stage cues. Per task: expected_phases.
- **Docs-discipline compliance** — если task меняет архитектуру / добавляет dir / вводит термин → docs touch detected? (per `.claude/rules/docs-discipline.md`).

Trajectory metrics — additive к существующим (tokens / turns / wall / cost / pytest), не replacement.

---

## Layer D — Statistical protocol

- **n=3 minimum** per cell. n=5 для close calls (|median Δ| < 15%).
- **Bracket reporting** `[min, median, max]` + CV (coefficient of variation, %).
- **Sign-inversion gate** (для claims вроде «harness ускорил»): median delta вне baseline IQR + ≥2/3 runs same side.
- **Within-noise honesty**: ±5% при CV ≥10% — нельзя называть улучшением.

Эмпирика, на которой стоит протокол: T03 4×4 runs показал CV=20.8% на our harness vs 8.7% на no-harness baseline. Single-run claims на этом variance — лотерея.

---

## Trigger matrix

| Trigger | A | B | C | D |
|---|:---:|:---:|:---:|:---:|
| Pre-commit любой harness change | ✓ | — | — | — |
| Behavior-changing principle update | ✓ | ✓ (subset) | ✓ | ✓ |
| New/changed skill | ✓ | ✓ (skill-relevant cells) | ✓ | ✓ |
| New/changed agent | ✓ | ✓ (agent-relevant cells) | ✓ | ✓ |
| New/changed hook | ✓ | ✓ (smoke) | partial | — |
| Retire/trim component | ✓ | ✓ (full subset) | ✓ | ✓ |
| ADR с numerical claim | ✓ | ✓ | ✓ | **required** |

«Subset» / «relevant cells» = sparse selection per change scope, не full matrix. Right-sizing — за main thread'ом per судить по природе изменения.

---

## Reporting

Report format: `reports/<task>-<fixture>-<harness>-runN.json` (per-run) + `reports/<ADR-or-change>/summary.md` (aggregate). Markdown template — `reports/README.md`.

Aggregate summary обязан включать:
- bracket table [min, median, max] per cell
- CV per cell
- sign-inversion verdict для claimed deltas
- trajectory deltas (skill accuracy, invariant pings count)

---

## Current implementation state

- **Layer A**: fully automated (`static-checks.sh`, 14 checks, 44ms).
- **Layer B**: operational на 3 fixture × 5 tasks. `headless-runner.sh` clone→inject→`claude --print`→JSON→pytest judge→report. Cross-harness comparison validated (`reports/CROSS-HARNESS-COMPARISON.md`).
- **Layer C**: partial — token/turn/cost захвачены, trajectory parsing — work-in-progress (P2 этой итерации).
- **Layer D**: applied ad-hoc на T03 (4×4 confirmed −24% median), не protocol-default yet.
- **Stop-hook two-gate validation**: `.claude/hooks/stop-validation.sh` — independent test re-run on session end.

## Roadmap

- **Active (P1+P2, 2026-05-11)**: trajectory parsing в `headless-runner.sh`, доки aligned, T01–T04 re-prog.
- **P3**: первая legend `legacy-no-tests` (modernization scenario, наибольший expected harness ROI).
- **P4**: trip-wire / Neg-invariant tasks (5-8 honeypot prompts).
- **P5**: stat protocol enforced default (n=3, bracket reporting).
- **P6**: F-ambiguous tasks (criteria-judge не pytest binary). Самое ценное, самое тяжёлое.

---

## Связь с harness

- `.claude/benchmark/static-checks.sh` — Layer A implementation.
- `.claude/benchmark/headless-runner.sh` — Layer B+C runner.
- `.claude/devlog/rebuild-index.py` — Layer A check #4.
- `.claude/hooks/stop-validation.sh` — independent two-gate validation.
- `.claude/skills/skill-creator:skill-creator` (marketplace) — Layer B+C для skills (eval + Comparator).

---

## Native `/goal` и `claude agents` — где применимы, где нет

Claude Code (built-ins с 2.1.139, актуально на 2.1.169) даёт `/goal` (loop-to-condition внутри сессии) и `claude agents` (TUI для параллельных background-сессий). На первый взгляд кажется, что это покрывает наши runner'ы — на практике нет: они на разном уровне абстракции.

**`/goal` — runtime control внутри одной `claude --print` сессии**. Наши runner'ы — measurement pipelines (clone fixture → inject harness → run claude → parse stream-json → pytest judge → aggregate report). `/goal` не заменяет ни один из 5/9 фаз. Заменить им можно только **prompt** на входе в Phase 3 (Build) battle-test-runner'а, и то выборочно:

- Уместно: усилить acceptance в `prompt.txt` (`/goal The deliverable invokes without ImportError and pytest exits 0`). Это prompt-engineering, не структурное изменение.
- Не уместно: оборачивать сам `claude --print` в bash-loop вокруг `/goal` — это попытка дублировать встроенный механизм извне.

**Cost watch**: тривиальный `/goal` (одна Edit, 4 turn'а, 14s) — $0.11 (Opus 4.7 1M $0.109 + Haiku 4.5 $0.003, гибрид). Для долгих goals предсказуемо $1+. Безопасность — в `prompt.txt` явное «stop after N turns regardless» либо внешний `timeout`.

**`claude agents` (TUI) — параллельные independent-сессии с автоматической worktree-isolation**. Кандидат на замену последовательного multi-run в Layer D protocol (n=3..5 на cell). Не верифицировано эмпирически в нашем контексте на момент 2026-05-12; перед адопцией нужен test-run: запустить 3 одинаковых benchmark cell'а через agent view и подтвердить (а) корректную worktree-изоляцию между ними, (б) отсутствие гонок при записи `reports/`, (в) что permission-context из `.claude/settings.json` применяется per-process.

**Empirical reference**: `~/.claude/projects/-home-nikita-PROJECTS-Harnesses-Claude/memory/reference_goal_agentview_empirical.md` — что подтверждено бинарём и live-тестом, что осталось гипотезой.
