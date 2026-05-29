# A/B test: global practice layer (with-harness vs without)

Measures whether the **global `~/.claude` practice layer** (CLAUDE.md §5 methodology
/ §6 continuity / §7 guardrails + hooks + skills) helps **Claude Code build a better
NL→SQL analyst**. Quality oracle = the v2 benchmark (12 tasks, live Oracle).

Decided design (operator): agent-under-test = `claude --print` building an impl;
toggle = global practice layer on/off.

## Arms
| Arm | Build invocation |
|---|---|
| `harness` | `claude --print` with default `~/.claude` (full practice layer) |
| `noharness` | `CLAUDE_CONFIG_DIR=<bare+creds> claude --print` (no CLAUDE.md/hooks/skills) |

Both get the **identical** `build_prompt.md` and a fresh empty workdir — the only
difference is the global layer, so the delta isolates its value.

### Toggle mechanism (verified mechanically)
`CLAUDE_CONFIG_DIR` relocates the whole config dir but also loses OAuth → the
`noharness` arm uses a bare dir carrying **only** `.credentials.json` (+ empty
`settings.json`). Confirmed via `--include-hook-events` on a trivial prompt:
**harness → SessionStart hooks fire (×4); noharness → 0 hook events.** So the
global CLAUDE.md, hooks and skills are genuinely absent in `noharness`.

## Build contract
`build_prompt.md` requires a root `solve.py` such that
`python3 solve.py "<question>"` prints exactly the Oracle SQL (or `NO_SQL`), no
DB/network. `BuiltImplSolver` wraps it as a v2 `Solver`; the v2 runner executes
the SQL against the isolated `client_product_bench` Oracle table and scores it.

## Necessary measurements (done — A/B readiness)
- **Oracle variance**: 3 independent passes of the reference real-agent (ollama,
  temp 0.1) → **5/5/5**, every task deterministically 3/3 or 0/3. The v2 oracle is
  a stable instrument (the Ollama-nondeterminism that nulled devlog #52 is absent
  here). → n=1 suffices on the scoring side.
- **Live reference**: ReferenceSolver 12/12 gate_pass, 12/12 stable on the real DB.
- **Real-agent baseline**: ollama (thin hint) 5/12 — discriminates easy vs domain
  traps (`../../reports/2026-05-29-text2sql-v2-ollama-baseline/`).
- **A/B pipeline** (`--stub`): both arms orchestrate + score + compare end-to-end
  (12/12 each with ReferenceSolver).

Residual noise for the A/B is the stochastic **claude build**, not the oracle →
use `--builds N>1` per arm for significance.

## Run
```
export AI_ANALYST_ORACLE_USERNAME=… AI_ANALYST_ORACLE_PASSWORD=… AI_ANALYST_ORACLE_DSN=…
python3 ab/ab_runner.py --stub                  # pipeline check, no claude (fast)
python3 ab/ab_runner.py --arms both --builds 3  # full A/B (expensive: 2×3 claude builds)
```
Env knobs: `AB_BUILD_MODEL` (default claude-sonnet-4-6), `AB_BUILD_TIMEOUT` (2400s),
`AB_SOLVE_TIMEOUT` (60s). Report → `--out` (default /tmp/ab_report.json).

## Cost note
The expensive part is the claude build sessions (2 arms × `--builds`). v2 scoring is
cheap (deterministic `solve.py` subprocess + Oracle). Full run ≈ 2×N build sessions.
