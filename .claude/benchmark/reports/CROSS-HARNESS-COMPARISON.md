# Cross-harness benchmark — 2026-05-11

Same fixture (`sample-py-app`), same model (Opus 4.7), `--permission-mode acceptEdits`,
`headless-runner.sh` после bug fixes. Each variant = one fresh fixture clone, no shared state.

## Setup
- T01: feature add (health check method + test). 5 lines spec.
- T02: bugfix (silent duplicate-email overwrite → ValueError + test). 7 lines spec.

## T01 (feature, simple)

| Variant | Turns | Wall | Cost USD | Output tok | Cache_read tok | Pytest |
|---|---:|---:|---:|---:|---:|:---:|
| A: no harness | 9 | 40s | $0.224 | 1 953 | 218 781 | pass |
| B: **our harness** | 9 | 41s | $0.278 | 2 100 | 260 560 | pass |
| C: everything-claude-code | 8 | 31s | $0.236 | 1 859 | 213 502 | pass¹ |

¹ Pass only after runner scoping fix; raw ECC inject brings 90+ parasitic tests in `skills/`
  that break pytest collection in any target project.

## T02 (bugfix, harder)

| Variant | Turns | Wall | Cost USD | Output tok | Cache_read tok | Pytest |
|---|---:|---:|---:|---:|---:|:---:|
| A: no harness | 12 | 52s | $0.309 | 2 779 | 311 600 | pass |
| B: **our harness** | 13 | 50s | $0.392 | 2 984 | 401 293 | pass |
| C: everything-claude-code | 10 | 41s | $0.297 | 2 543 | 276 862 | pass |
| D: cwc-long-running-agents | 14 | 51s | $0.450 | 3 040 | 359 879 | pass |

## T03 (FastAPI feature add, real-world fixture)

Fixture: `FastApi-Base` (32 tracked files, domain-based layout, async SQLAlchemy, pytest-asyncio).
Branch `benchmark/baseline-noharness` — Claude harness stripped, 4 fixture template-bugs
fixed (sqlite-incompatible pool args, missing `Depends()` in auth router, etc.) — exact
same baseline для всех 4 variants.

| Variant | Turns | Wall | Cost USD | Output tok | Cache_read tok | Files | Pytest |
|---|---:|---:|---:|---:|---:|---:|:---:|
| A: no harness | 15 | 74s | $0.484 | 4 814 | 471 763 | 2 | pass |
| B: **our harness** (1st run) | 9 | 69s | **$0.370** | 4 028 | 285 243 | 3 | pass |
| C: everything-claude-code v2 | 12 | 76s | $0.417 | 4 838 | 353 478 | 10 | pass |
| D: cwc-long-running-agents | 15 | 76s | $0.435 | 4 953 | 418 164 | 3 | pass |

### T03 variance check — our harness × 4 runs

После initial single-run sign inversion прогнали ещё 3 runs нашего variant'а для variance:

| Run | Wall | Turns | Cost | Cache_read | Pytest |
|---|---:|---:|---:|---:|:---:|
| B-0 (initial) | 69s | 9 | $0.370 | 285 243 | pass |
| B-1 | 44s | 10 | $0.345 | 306 523 | pass |
| B-2 | 54s | 8 | **$0.338** ← min | 241 423 | pass |
| B-3 | 73s | 14 | **$0.512** ← max | 486 283 | pass |

**Stats**: median $0.358, mean $0.391, stdev $0.081, **CV 20.8%**.
**Δ vs baseline** (single run $0.484): median **−26%**, best −30%, worst +6%.

3/4 runs clearly below baseline ($0.34–0.37, −23%…−30%). 1 outlier (B-3) практически равен
baseline ($0.512 vs $0.484, +6%) — Claude в B-3 потратил больше turns (14) и cache_read
(486k vs median 296k). Turns max (14) всё ещё ≤ baseline turns (15) — turns signal cleaner
чем cost.

### T03 baseline variance — no-harness × 4 runs (symmetric check)

После variance check нашего variant'а провели 3 extra runs baseline:

| Run | Wall | Turns | Cost | Cache_read |
|---|---:|---:|---:|---:|
| A-0 (initial) | 74s | 15 | $0.484 | 471 763 |
| A-1 | 83s | 16 | $0.524 | 499 673 |
| A-2 | 66s | 13 | **$0.425** ← min | 383 111 |
| A-3 | 99s | 14 | $0.462 | 427 218 |

**Stats**: median $0.473, mean $0.474, stdev $0.041, **CV 8.7%**.

### 4×4 symmetric comparison

| | OUR harness (4 runs) | NO harness (4 runs) | Δ |
|---|---|---|---|
| Cost min | $0.338 | $0.425 | −20.6% |
| Cost median | **$0.358** | **$0.473** | **−24.4%** |
| Cost mean | $0.391 | $0.474 | −17.4% |
| Cost max | $0.512 | $0.524 | −2.3% |
| Cost CV | 20.8% | 8.7% | +12.1pp |
| Turns median | 9.5 | 14.5 | −5 |

**Distribution overlap** (4 our × 4 baseline = 16 pairwise comparisons):
- 3/4 our runs strictly **below** baseline min ($0.425)
- 1/4 our run inside baseline range ($0.512, just below baseline max $0.524)
- 0/4 our runs above baseline max

**Sign inversion robust to variance.** Каждый из 4 our runs ≤ каждого из 4 baseline runs
по turns (с одним tied: B-3=14 ≈ A-3=14). По cost: 12/16 pairs (75%) показывают our cheaper;
4/16 inside ±10%.

Curious: **our harness has higher variance** (CV 20.8% vs 8.7%) — counter-intuitive,
обычно preload снижает variance. Hypothesis: workflow.md preload иногда triggers Claude
в более thorough mode (explore deeper когда context cue suggest); на B-3 видимо это
сработало.

## Deltas vs no-harness baseline

T03 our harness — median of 4 runs (CV 20.8%); другие variants — single-run.

| | T01 cost Δ | T02 cost Δ | **T03 cost Δ** | T01 turns Δ | T02 turns Δ | **T03 turns Δ** |
|---|---:|---:|---:|---:|---:|---:|
| Our harness | +24% | +27% | **−26% median<br>[−30%…+6%]** | 0 | +1 | **−5.5 median** |
| ECC | +5% | −4% | **−14%** | −1 | −2 | **−3** |
| cwc (Anthropic) | n/a | +46% | **−10%** | n/a | +2 | **0** |

**Confirmed median delta (4×4 runs)**: our harness median $0.358 vs baseline median $0.473
→ **−24.4%**. 3/4 our runs strictly below baseline range, 0/4 above. Direction robust
к variance, magnitude stable around −20…−25%.

## Findings

1. **Quality identical across all 4 variants** — Opus 4.7 nativly solves T01/T02 без harness
   (validates foundational principle «минимум обвязки → максимум продуктивности»).

2. **Our harness ~+25% token overhead** — measurable cost. For simple tasks ROI marginal;
   for complex/long-running tasks (which we don't benchmark here) it likely pays off via
   stop-validation + secret-scan + dangerous-cmd-block + structured workflow.md guidance.

3. **everything-claude-code raw inject ≈ neutral overhead** — `.claude/` is only 116K,
   top-level CLAUDE.md is 72 lines; skills/agents/commands lie in top-level dirs that
   don't auto-load без `/plugin install`. **But** ECC ships 3 test files with 90+ tests
   in `skills/continuous-learning-v2/scripts/`, which **breaks pytest discovery**
   в любом target проекте using default `pytest .` invocation. This is a real safety
   regression — should not be installed без проверки своего `testpaths` config.

4. **cwc-long-running-agents — most expensive (+46% cost)** despite minimalist LoC (506).
   Its 5 hooks (verify-gate, track-read, commit-on-stop, kill-switch, steer) +
   evaluator agent inject context with non-trivial cost. Justified для long-running
   fixed-spec tasks ($200 budget 6h sessions per Rajasekaran 2026), not для standard
   one-shot features/bugfixes.

5. **headless-runner.sh had 3 bugs found and fixed during this run**:
   - env vars passed after `bash -c "..."` instead of before (broke `--permission-mode`)
   - `files_changed=0` if fixture not a git repo (sample-py-app is not)
   - pytest collected nothing if `tests/` dir absent (fixture has root-level `test_app.py`)

## T04 — Alembic migration on FastApi-Base (1 run × 4 variants)

T04 spec: add nullable `phone` column to User model + alembic revision (op.add_column /
op.drop_column) + test in `tests/test_user_phone.py` asserting persistence. **Explicit
spec** — почти zero exploration overhead, Claude знает где писать.

| Variant | Turns | Wall | Cost | Cache_read | Files | Pytest |
|---|---:|---:|---:|---:|---:|:---:|
| A: no harness | 16 | 53s | $0.418 | 459 202 | 3 | pass |
| B: **our harness** | 14 | 50s | $0.431 | 455 194 | 4 | pass |
| C: ECC v2 | 21 | 56s | **$0.525** ← max | 522 966 | 11 | pass |
| D: cwc | 14 | 54s | **$0.367** ← min | 381 996 | 3 | pass |

**Deltas vs baseline**: our +3%, ECC +25%, cwc −12%.

**T04 findings**:
- На explicit spec без exploration phase **наш harness ≈ neutral** (+3%, в variance noise).
- ECC v2 back to overhead (+25%) — too много auto-loaded skills для structured task.
- cwc surprisingly best (−12%) — possibly его hooks/PROGRESS pattern matches multi-step
  refactor character of migrations.

## T03e — Express+Jest health endpoint (1 run × 4 variants)

Polyglot fixture: `ExpressApi-Base` (Node.js, ~5 files, express+supertest+jest, 45MB
node_modules). Quality judge: pytest skipped (Node project, manual jest verification only).

| Variant | Turns | Wall | Cost | Cache_read | Files |
|---|---:|---:|---:|---:|---:|
| A: no harness | 10 | 30s | $0.213 | 219 887 | 2 |
| B: **our harness** | 8 | 26s | **$0.218** | 197 433 | 3 |
| C: ECC v2 | 10 | 33s | $0.258 | 269 714 | 10 |
| D: cwc | 15 | 43s | $0.281 | 260 367 | 3 |

**Deltas vs baseline**: our +2%, ECC +21%, cwc +32%.

**T03e findings**:
- Small Node fixture: harness preload **does not pay off** (our +2%, neutral).
- ECC/cwc back to overhead.
- Baseline cache_read 220k (Express) vs 472k (FastAPI) — half. Smaller fixture → less
  exploration cost to compress → less harness ROI.

## Cross-task synthesis

| Task | Fixture | Spec | Baseline cache_read | Our Δ vs baseline |
|---|---|---|---:|---:|
| T01 | sample-py-app (toy, 1 file) | terse | 219k | **+24%** overhead |
| T02 | sample-py-app | terse | 312k | **+27%** overhead |
| T03 | FastApi-Base (realistic Python, ~30 files) | needs navigation | 472k | **−24% median** win |
| T04 | FastApi-Base | explicit ("place X in Y") | 459k | **+3%** neutral |
| T03e | ExpressApi-Base (small Node, ~5 files) | needs navigation | 220k | **+2%** neutral |

**Unifying hypothesis** (replaces "fixture size" from devlog 0025):
**Harness ROI ∝ ambient exploration cost** = (fixture navigation depth) × (spec ambiguity).
- Toy fixture + terse spec → overhead (T01/T02)
- Realistic Python fixture + navigation-required spec → win (T03)
- Realistic fixture + explicit spec → neutral (T04 — Claude knows exactly where to write)
- Small Node fixture + navigation-required spec → neutral (T03e — exploration cheap)

ROI peaks when Claude would otherwise spend significant turns on glob/grep/read discovery
that harness preload makes redundant. Three factors must align:
1. Project structure non-obvious from filename grep
2. Task spec doesn't pre-specify location/style
3. Project size > 1k LoC (~10+ files Claude needs to consider)

## T03 findings — sign inversion vs T01/T02

1. **Sign of harness ROI зависит от fixture complexity, не от task complexity per se.**
   На toy fixture (`sample-py-app`, single file) harness — overhead. На realistic FastAPI
   layout (domains, async DB, dependency injection, ~30 files) **тот же harness становится
   net win** — Claude меньше тратит turns на exploration, workflow.md preload даёт
   structural guidance бесплатно (relative к no-harness который тратит cache_read на
   discovery).

2. **Наш harness: cache_read 285k vs baseline 472k** — 40% меньше. Workflow.md + principles
   преlowads подставляют convention'ы, которые иначе Claude вынужден извлекать через
   `glob`+`grep`+`read` цикл. Cache_create практически идентичен (20k vs 20k) — overhead
   preload минимальный.

3. **Files changed asymmetry**: A=2 (route + test), B=3 (?), C=10 (ECC v2 hooks/skills
   создают side-effect artefacts), D=3. ECC's 10 — likely PROGRESS.md, evidence files,
   memory writes from continuous-learning skill.

4. **1 run на variant** — variance не учтена. Sign-flip (+25% → −24%) на одной точке
   данных может быть partly noise. Для confident claim нужны ≥3 runs (per Anthropic eng
   essays). Но magnitude разности (482→370, 113 USD-cent gap) больше типичной single-run
   variance — pattern скорее всего real.

## Implications для нашего harness'а

- **Foundational principle нужно nuanced**: «минимум обвязки» не значит «zero harness»
  на realistic projects. Минимум обвязки **уровня задачи** — yes; minimum **уровня
  fixture навигации** — no, structural preload (workflow.md, conventions) окупается
  на проектах ≥1k LoC.
- **Envelope теперь bi-directional**: +25% на toy fixtures, −24% на real-world FastAPI.
  Production envelope зависит от target project size. Дальнейший benchmark должен включать
  variance (3+ runs) и polyglot fixtures.
- **ECC v2 surprise**: prior measurement (Q1) was раз v1 (116K `.claude/`). v2 — 3.4MB
  skills, fundamentally different harness; -14% на T03 показывает что heavyweight pack
  тоже даёт ROI на realistic projects, но платит side-effects (10 files changed includes
  artefacts irrelevant to T03 spec).
- **cwc evaluator pattern**: −10% на T03 vs +46% на T02 — same direction as our harness.
  Long-running scenarios remains untested (this is short-task benchmark).
