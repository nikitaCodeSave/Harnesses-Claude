# Benchmark Reports

Storage для tier 1 / tier 2 benchmark output. Каждый behavior-changing harness change — attach report inline в devlog entry или save here если объёмный.

## File naming

```
reports/<tier>-<change-name>-<YYYY-MM-DD>.md
```

Examples:
- `tier1-subagent-isolation-2026-05-10.md`
- `tier2-devlog-skill-trigger-2026-05-15.md`

## Report template

```markdown
# Benchmark Report: <change-name>

**Tier**: 0 / 1 / 2
**Date**: YYYY-MM-DD
**Change**: <что было tested>
**Baseline**: <git ref / harness state before change>

## Setup

- Fixture: <path>
- Tasks: <list>
- Harness state: <commit hash>

## Results

| Task | Tokens delta | Turns delta | Success | Notes |
|------|--------------|-------------|:-------:|-------|
| T01  | -8%          | -1          | ✓       | improvement |
| T02  | +3%          | 0           | ✓       | within threshold |

## Conclusion

[net improvement / regression / no change + explanation]
```

См. `.claude/docs/benchmark.md` для full methodology + threshold reference.
