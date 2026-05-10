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

## Deltas vs no-harness baseline

| | T01 cost Δ | T02 cost Δ | T01 turns Δ | T02 turns Δ |
|---|---:|---:|---:|---:|
| Our harness | **+24%** | **+27%** | 0 | +1 |
| ECC | +5% | **-4%** | -1 | -2 |
| cwc (Anthropic) | n/a | **+46%** | n/a | +2 |

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

## Implications для нашего harness'а

- **Foundational principle validated empirically**: heavyweight pack (ECC) brings real
  side-effects (pytest pollution); minimum-overhead approach safer for unknown target
  projects.
- **+25% cost is our budget envelope** под Opus 4.7 on simple tasks. Monitor on T03+
  (FastAPI endpoint, polyglot tasks) for stability.
- **cwc evaluator pattern adoption deferred**: cost too high для standard tasks; opt-in
  reference в `workflow.md` для long-running scenarios is correct positioning.
