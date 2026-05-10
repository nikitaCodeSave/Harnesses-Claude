# Harness Benchmark Methodology

3-tier подход для валидации harness changes. См. ADR-019. Цель — empirical evidence что обновления harness'а не регрессируют качество, и где возможно improve измеримо.

## Когда запускать

| Trigger | Tier 0 | Tier 1 | Tier 2 |
|---|:---:|:---:|:---:|
| Pre-commit (любой harness change) | ✓ | — | — |
| Новый ADR (behavior-changing) | ✓ | ✓ | — |
| Новый/изменённый skill | ✓ | ✓ | ✓ (per skill) |
| Новый/изменённый agent | ✓ | ✓ | ✓ (per agent) |
| Новый/изменённый hook | ✓ | ✓ (smoke) | — |
| Trim/retire component | ✓ | ✓ | — |

Tier 3 (blind compare) — ad-hoc, when Tier 1 показывает ambiguous deltas.

---

## Tier 0 — Static checks

Cheap, fast (<10 sec), automated. **Blocker** if fail.

### Checks list

| # | Check | Command / criteria | Source of constraint |
|---|---|---|---|
| 1 | `CLAUDE.md` size budget | `wc -l .claude/CLAUDE.md` ≤ 200 | meta-CLAUDE.md anti-pattern «не лить мегарайлзы» + ADR-012 |
| 2 | Each `SKILL.md` size budget | per skill ≤ 500 строк | skill-creator anatomy guideline |
| 3 | Active decisions size budget | `principles.md` ≤ 200 строк + каждая `### D-NNN` секция ≤ 30 | D-021 + tight format |
| 4 | Devlog index integrity | `python3 .claude/devlog/rebuild-index.py` exit 0 | ADR-004 |
| 5 | Skill frontmatter present | every `.claude/skills/*/SKILL.md` has `name` + `description` YAML | Claude Code skill spec |
| 6 | Rules frontmatter (если есть) | `paths:` valid если frontmatter присутствует | docs-discipline rule 4 |
| 7 | Skill discovery runtime | `claude --print` lists all `.claude/skills/*` | ADR-016 pilot pattern |
| 8 | Agent inventory | `claude agents` lists expected (`deliverable-planner`, `meta-creator`, built-ins) | ADR-007 |
| 9 | Hook smoke tests | каждый hook на stdin типичного input → exit 0 | ADR-016 (session-context.sh bugfix lesson) |
| 10 | No retired components | grep `.claude/` against retired list (per ADR-007/010/011/016) | append-only history + retire ADR'ы |
| 11 | Active+archive doc paths | `principles.md` + `.claude/docs/archive/decisions-2026Q2.md` оба существуют | D-021 |

### Implementation

`.claude/benchmark/static-checks.sh` — implemented; запускается из harness root, выводит таблицу check / pass-fail / actual value, exit 1 при любом fail.

### Когда ослабить

Если Tier 0 false-positive rate >20% (блокирует legitimate changes по ложной тревоге) — пересмотреть constraints. Counter-evidence to revise — см. ADR-019.

---

## Tier 1 — Pilot project task suite

Medium cost (manual + scripted). Запуск на ADR'ах меняющих behavior + при изменении skill/agent/hook.

### Fixture project

Default: `~/PROJECTS/FastApi-Base` (использован в ADR-016 pilot validation).

Альтернатива: dedicated `~/PROJECTS/Harness-Bench-Fixture` (свежий проект specifically для benchmark) — создаётся при первом случае когда FastApi-Base недоступен/несовместим.

Fixture должен иметь:
- Git repo initialized (даже 1 commit OK; `git init` дешёвый pre-step если fixture был tarball-style).
- 2+ top-level dirs в `src/` (для CODE-MAP.md trigger).
- Existing tests (для baseline regression).
- `docs/` либо отсутствует, либо минимальный (тестирует docs-bootstrap skill).
- (Soft) ≥10 commits history для mode-detection signal; меньше — bootstrap mode.

### Standard task suite (7 задач, расширяется по необходимости)

| ID | Type | Prompt | Expected signal |
|---|---|---|---|
| T01 | feature | «Add /health endpoint returning {status: ok, uptime: seconds}» | endpoint added, test passing, latency <50ms |
| T02 | bugfix | «POST /users возвращает 500 если email duplicate — должен 409» | reproduce bug, fix, regression test added |
| T03 | refactor | «Раздели monolith handlers на routers по resource» | structure changed, behavior identical (test suite passes) |
| T04 | docs | «Project lacks ARCHITECTURE.md, добавь» | проверяет project-docs-bootstrap skill autotrigger |
| T05 | ops | «Run linter, fix warnings» | lint clean, no behavior change |
| T06 | research | «Какие endpoints возвращают user PII?» | accurate enumeration без modifications |
| T07 | test | «Coverage gap: auth middleware. Добавь tests» | new tests, coverage delta |

### Metrics per task

- **Tokens**: input + output (proxy для cost / context efficiency)
- **Turns**: assistant turns to completion (proxy для thinking depth)
- **Files**: read / edited / created counts
- **Success**: binary, judged по acceptance signal (см. expected signal)
- **Duration**: wall-clock

### Comparison protocol

1. Snapshot harness-current state (git stash или branch).
2. Run each task на harness-current. Capture metrics.
3. Apply harness change. Run each task на harness-proposed. Capture metrics.
4. Compute delta per metric per task.

### Threshold

| Metric | OK delta | Investigate threshold |
|---|---|---|
| Tokens | ±20% | >+30% (regression) |
| Turns | ±2 | >+4 (regression) |
| Success rate | 100% maintained | any drop |
| Files touched | ±2 | >+5 (scope creep signal) |

Outside threshold → investigate root cause. Inside → harness change OK.

---

## Tier 2 — Per-component evals

Per skill: skill-creator workflow.
- Eval set: 8-10 should-trigger queries + 8-10 should-not-trigger (near-misses).
- Run: `python -m scripts.run_loop --eval-set <path> --skill-path <skill> --model claude-opus-4-7 --max-iterations 1`
- Pass criteria: trigger accuracy ≥85% on held-out test split.

Per agent: similar — prompt corpus that should/shouldn't spawn agent. Manual judge для invocation appropriateness.

Per hook: covered в Tier 0 smoke tests; tier 2 — non-applicable.

---

## Tier 3 — Blind compare (optional)

Используется когда Tier 1 показывает ambiguous deltas. Per skill-creator `agents/comparator.md`:
1. Same task на harness-A vs harness-B.
2. Independent agent (general-purpose) judges quality blind.
3. Analyze winner reasoning (per `agents/analyzer.md`).

Cost: 2× Tier 1 + judge agent. Не required; ad-hoc.

---

## Reporting

Каждый behavior-changing ADR — attach benchmark report:

```markdown
## Benchmark report (ADR-NNN)

**Tier 0**: pass (11/11)
**Tier 1**: 5 tasks ran on FastApi-Base
| Task | Tokens delta | Turns delta | Success | Notes |
|---|---|---|---|---|
| T01 | -8% | -1 | ✓ | — |
| T02 | +3% | 0 | ✓ | — |
| T03 | +12% | +1 | ✓ | within threshold |
| T04 | -22% | -2 | ✓ | improvement (docs-bootstrap skill auto-triggered) |
| T05 | +5% | 0 | ✓ | — |

**Conclusion**: net improvement (T04), no regressions.
```

Report storage: либо section в ADR, либо separate `.claude/benchmark/reports/ADR-NNN.md` если объёмный.

---

## Current implementation state

- **Tier 0**: fully automated (`.claude/benchmark/static-checks.sh`, 14 checks, 44ms runtime).
- **Tier 1**: scaffolding ready (`.claude/benchmark/tier1/`) — task definitions validated, fixture present (`.claude/benchmark/fixtures/sample-py-app/`). Actual Claude invocation остаётся manual.
- **Tier 2**: scaffolding ready (`.claude/benchmark/tier2/`) — eval sets для skill trigger accuracy. Manual evaluation.
- **Stop-hook validation**: `.claude/hooks/stop-validation.sh` — independent test re-run на session end (two-gate validation pattern, community evidence false-completion 35%→4%).

## Infrastructure layout

```
.claude/benchmark/
├── README.md              — quick start + overview
├── static-checks.sh       — Tier 0 (automated)
├── run-all.sh             — orchestrate all tiers
├── tier1/
│   ├── README.md
│   ├── run-tier1.sh
│   └── tasks/             — T01-T02 sample tasks (yaml), extend по необходимости
├── tier2/
│   ├── README.md
│   ├── run-tier2.sh
│   └── eval-sets/         — <skill>-should-trigger.txt + <skill>-should-not-trigger.txt
├── fixtures/
│   ├── README.md
│   └── sample-py-app/     — self-contained Python fixture с known bugs T01/T02
└── reports/
    └── README.md          — report template
```

## Roadmap

- **Done**: Tier 0 automation, Tier 1/2 scaffolding, self-contained fixture, Stop-hook validation.
- **Next**: Tier 1 full automation через `claude --print --add-dir <fixture>` orchestrator (OAuth-compatible) с output parsing для tokens/turns/files metrics. `--bare` остаётся out of scope (strictly требует `ANTHROPIC_API_KEY` per `claude --help`).
- **Future**: cross-harness comparison fixtures (clone everything-claude-code / claude-code-harness / Superpowers для quantitative benchmark на same task suite).

---

## Связь с harness

- `.claude/skills/skill-creator:skill-creator` (marketplace plugin) — Tier 2 implementation для skills.
- `.claude/devlog/rebuild-index.py` — Tier 0 check #4.
- `.claude/benchmark/static-checks.sh` — Tier 0 implementation.
- `.claude/hooks/stop-validation.sh` — Stop-hook two-gate validation.
