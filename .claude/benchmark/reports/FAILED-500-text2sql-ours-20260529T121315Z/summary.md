# Battle-test: text2sql / ours

**Date**: 2026-05-29T12:13:16Z
**Build model**: opus
**Wall**: 13s (0m 13s) build only
**Total OAuth cost**: $0.4590

## Verdict: **failure** (3 / 100)

| Section | Score | Max |
|---|---:|---:|
| F-Questions (auto) | 0 | 30 |
| T/B auto (scriptable) | 3 | 23 |
| T/B LLM-judge | 0 | 47 |
| **Grand total** | **3** | **100** |

Thresholds: ≥70 accepted · 50-69 partial · <50 failure.

## Build phase

- exit_code: 1
- stop_reason: stop_sequence
- turns: 4
- cost: $0.23443049999999999
- tokens: in=3666 out=414 cache_create=30814 cache_read=26326

## Trajectory (Layer C)

```json
{
  "skills_triggered": [],
  "subagent_dispatches": {
    "count": 0,
    "types": []
  },
  "tool_calls_summary": [
    {
      "name": "Bash",
      "count": 2
    },
    {
      "name": "Read",
      "count": 1
    }
  ],
  "invariant_pings": []
}
```

## Result excerpt

```
API Error: 500 Internal server error. This is a server-side issue, usually temporary — try again in a moment. If it persists, check https://status.claude.com.
```

## Deliverable info

```json
{
  "status": "fail",
  "entry_kind": null,
  "entry_module": null,
  "entry_script": null,
  "invocation_cmd": null,
  "venv_path": null,
  "venv_status": null,
  "install_log_tail": "",
  "reason": "no entry point found (looked for pyproject+module/__main__, main.py, cli.py, app.py, run.py, assistant.py)"
}
```

## F-Question scores

```json
{}
```

## T/B auto scores

```json
{
  "status": "ok",
  "items": {
    "T1": {
      "score": 3,
      "max": 6,
      "verdict": "partial",
      "reason": "5 py files, partial structure (pyproject=False, tests=False)"
    },
    "T2": {
      "score": 0,
      "max": 4,
      "verdict": "fail",
      "reason": "no pyproject.toml or requirements.txt"
    },
    "T5": {
      "score": 0,
      "max": 8,
      "verdict": "fail",
      "reason": "pytest exit=5 (collection or env issue)"
    },
    "T6": {
      "score": 0,
      "max": 4,
      "verdict": "fail",
      "reason": "no README"
    },
    "B4": {
      "score": 0,
      "max": 5,
      "verdict": "fail",
      "reason": "no Phase 5 data"
    }
  },
  "total": 3,
  "max": 27
}
```

## LLM-judge scores

```json
{
  "T3": {
    "score": 0,
    "max": 6,
    "justification": "No application code present; deliverable contains only .env and metadata.py (per file tree), with no module wrapping Oracle connect, LLM calls, or SQL exec in try/except. Insufficient evidence."
  },
  "T4": {
    "score": 0,
    "max": 6,
    "justification": "metadata.py is listed in the tree but no file contents were provided in evidence and the cloned cwd is empty, so type hints, docstrings, and naming cannot be verified. Insufficient evidence."
  },
  "T7": {
    "score": 0,
    "max": 6,
    "justification": "No SQL-generation code exists in the deliverable; no parameterization, whitelisting, or Oracle DATE literal handling is present. Insufficient evidence."
  },
  "B1": {
    "score": 0,
    "max": 6,
    "justification": "No NL-answer formatting logic present; the deliverable has no assistant/response code at all. Insufficient evidence."
  },
  "B2": {
    "score": 0,
    "max": 5,
    "justification": "No validation or sanity-check logic exists; no code inspects result ranges, null fields, or result size. Insufficient evidence."
  },
  "B3": {
    "score": 0,
    "max": 6,
    "justification": "No NL-handling or query code exists, so ambiguity defaults, missing-field handling, and loop avoidance cannot be demonstrated. Insufficient evidence."
  },
  "B5": {
    "score": 0,
    "max": 8,
    "justification": "Only a .env file hints at env-based config (and committing creds in .env is itself an anti-pattern); no logging, Dockerfile, CI workflow, connection pool, or retry logic is present. Insufficient evidence."
  },
  "total": 0,
  "cost_usd": 0.22457525,
  "status": "ok"
}
```

## Clone preservation

`/tmp/battle-text2sql-ours-20260529T121315Z` — preserved для forensics

## Methodology

- `.claude/docs/benchmark.md` — 4-layer framework
- `.claude/benchmark/text2sql-judge/README.md` — battle-test specifics
- `.claude/benchmark/text2sql-judge/acceptance.yaml` — 100-pt rubric
