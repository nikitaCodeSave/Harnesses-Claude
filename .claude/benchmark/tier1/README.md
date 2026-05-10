# Tier 1: Pilot Project Task Suite

Behavioral validation — actual task execution на fixture project. Validates что harness changes не регрессируют real-world quality.

## Fixture

Default: `.claude/benchmark/fixtures/sample-py-app/` (self-contained в repo).
Alternative: external project via `FIXTURE_PATH` env var.

Fixture should have:
- Git repo initialized (≥1 commit; bootstrap mode acceptable)
- 2+ top-level dirs / files в src
- Existing tests (baseline regression check)
- Known issues документированы в fixture README

## Task suite

7 стандартных tasks (T01-T07) расширяемых. Каждая task — YAML в `tasks/`:

```yaml
id: T0X
type: feature | bugfix | refactor | docs | ops | research | test
prompt: "<что Claude должен сделать>"
expected_signal:
  - <criterion 1>
  - <criterion 2>
metrics: [tokens, turns, files, success]
baseline_notes:
  fixture_pre_state: "<что fixture provides>"
  acceptance: "<когда задача считается готовой>"
```

## Comparison protocol

1. Snapshot harness-current (`git stash` или branch).
2. Run all tasks на harness-current → capture metrics.
3. Apply harness change.
4. Run all tasks на harness-proposed → capture metrics.
5. Compute delta per metric per task.
6. Generate report в `.claude/benchmark/reports/`.

## Threshold

| Metric | OK delta | Investigate threshold |
|--------|----------|------------------------|
| Tokens (input+output) | ±20% | >+30% (regression) |
| Turns to completion | ±2 | >+4 (regression) |
| Success rate | 100% maintained | any drop |
| Files touched | ±2 | >+5 (scope creep signal) |

Outside threshold → investigate root cause. Inside → harness change OK.

## Runner

`run-tier1.sh` — validates task definitions, lists discovered tasks, checks fixture readiness. **Actual Claude invocation остаётся manual** (требует interactive Claude session или `claude --print` headless mode на OAuth-подписке; `--bare` требует API-key и out of scope).

Roadmap: full automation через `claude --print --add-dir <fixture>` orchestrator с output capture + metrics extraction.
