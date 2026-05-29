# Benchmark Reports

Storage для Layer B+C+D output. Per-run JSON + aggregate markdown summary.

## File naming

```
reports/<task>-<fixture>-<harness>-runN.json           # per-run, Layer B+C raw data
reports/<change-name>/summary.md                        # aggregate Layer D, per change
reports/<task>-<harness>-<fixture>-<timestamp>.json    # legacy single-run reports (pre-2026-05-11)
```

Examples:
- `T01-sample-py-app-ourharness-run1.json`
- `T01-sample-py-app-ourharness-run2.json`
- `T01-sample-py-app-ourharness-run3.json`
- `ADR-022-subagent-isolation/summary.md`

## Per-run JSON schema (Layer B+C)

```jsonc
{
  "task": "T01",
  "fixture": "sample-py-app",
  "harness_injected": true,
  "timing": { "start": "...", "end": "...", "wall_seconds": 42 },
  "claude": {
    "exit_code": 0, "stop_reason": "end_turn", "num_turns": 9,
    "cost_usd": 0.278,
    "tokens": { "input": 23, "output": 2100, "cache_creation": 5400, "cache_read": 260560 }
  },
  "verification": {
    "files_changed": 2,
    "pytest": { "status": "pass", "reason": "pytest_clean" }
  },
  "trajectory": {
    "skills_triggered": ["devlog"],
    "subagent_dispatches": { "count": 0, "types": [] },
    "tool_calls_summary": [
      { "name": "Read", "count": 4 },
      { "name": "Edit", "count": 2 }
    ],
    "invariant_pings": [],
    "workflow_markers": { "plan_emitted": false, "review_emitted": true }
  },
  "result_excerpt": "...",
  "stderr_tail": ""
}
```

Trajectory поля могут быть пустыми/null если stream-json parsing не сработал (graceful degradation).

## Aggregate summary template (Layer D)

```markdown
# Benchmark Summary: <change-name>

**Layer A**: pass / N checks failed
**Layer B+C**: <N> cells × <n> runs
**Date**: YYYY-MM-DD
**Change**: <что было tested>
**Baseline**: <harness state ref>

## Bracket table

| Cell | Cost [min,med,max] | Turns [min,med,max] | CV cost | Pytest | Skills hit | Subagents | Invariant pings |
|---|---|---|---:|:---:|---|---:|---:|
| T01-sample-py-app | [0.22, 0.27, 0.31] | [8, 9, 11] | 14% | 3/3 | devlog | 0 | 0 |
| T03-fastapi-domain | [0.34, 0.36, 0.51] | [8, 9, 14] | 21% | 3/3 | docs-bootstrap | 0 | 0 |

## Sign-inversion verdicts

For each delta claim:
- **Cost T03 ours vs baseline**: median Δ −24.4%, ≥2/3 runs below baseline IQR → **confirmed improvement**.
- **Cost T01 ours vs baseline**: median Δ +24%, all runs above baseline IQR → **confirmed overhead** (within ROI hypothesis).

## Trajectory deltas

| Cell | Skill accuracy | Over-delegation flags | Invariant violations |
|---|---|---|---|
| T01 | devlog should-trigger: 3/3 ✓ | 0 | 0 |
| T03 | docs-bootstrap should-trigger: 0/3 ✗ | 1 (general-purpose for trivial search) | 0 |

## Conclusion

[net improvement / regression / within noise + axis explanation]

## Methodology

See `.claude/docs/benchmark.md`.
```

## Что обязательно в aggregate summary

- bracket [min, median, max] per cell — никогда single number
- CV per cell
- sign-inversion verdict для любого numerical claim (median outside baseline IQR + ≥2/3 same side)
- trajectory deltas (skills accuracy, over-delegation flags, invariant pings count)
- ссылка на methodology

## Cross-harness comparisons

Multi-harness reports (e.g., `CROSS-HARNESS-COMPARISON.md`) — на уровне директории `reports/`. Используют тот же bracket format + sign-inversion для each harness × cell.
