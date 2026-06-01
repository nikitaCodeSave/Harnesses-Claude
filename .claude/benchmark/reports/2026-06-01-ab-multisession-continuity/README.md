# Multi-session A/B — does the global practice layer's continuity pillar add value?

**Date:** 2026-06-01 · **Driver:** `text2sql-v2/ab/ab_multisession.py` · **Build model:**
claude-sonnet-4-6 · **SQL backend:** ollama `alibayram/Qwen3-30B-A3B-Instruct-2507` ·
**Oracle:** live `client_product_bench` (isolated) · **n = 1 build per arm per condition.**

## Question

Single-shot A/B (devlog #52, #61) systematically nulls the **continuity pillar** (#54):
the whole build lives in one context, so nothing has to survive a session boundary.
This experiment exercises continuity — the build is split into **3 stages, each a separate
`claude --print --no-session-persistence` in the SAME persisted workdir** — and asks whether
the global `~/.claude` practice layer (CLAUDE.md §6 + `session-context.sh` SessionStart hook)
helps Claude build a better NL→SQL analyst across those boundaries.

Toggle (only difference between arms; verified #60): `harness` = default `~/.claude`;
`noharness` = `CLAUDE_CONFIG_DIR` → bare dir with only OAuth creds (hooks 4 vs 0).

Design B: the full domain spec is given only at S1; S2/S3 are thin (name the new question
types, NOT the domain traps). Whether the trap-rules survive depends on continuity.

Two conditions:
- **unprimed** — stage prompts say nothing about leaving a trail (does the layer self-engage?).
- **primed** (`--prime-continuity`) — an identical neutral handoff instruction is appended to
  S1/S2 ("leave a note for the next session; method/location your choice"). Makes the
  continuity *write* happen, so the read-side delta (harness auto-surface vs noharness manual)
  becomes testable.

## Results (gate_pass / 12, full suite scored after each stage)

| Condition | Arm | S1 | S2 | S3 (final) | Regressions (S1-green→final-red) | Trail written? | Used `.claude/{devlog,progress}`? |
|---|---|----|----|----|----|----|----|
| unprimed | harness   | 5 | 5 | **4** | T7 | **No** | No (devlog=0 progress=0) |
| unprimed | noharness | 5 | 5 | **4** | T7 | No | No |
| primed   | harness   | 5 | 3 | **4** | T7, T10 | Yes (`SESSION_NOTES.md`) | **No** (devlog=0 progress=0) |
| primed   | noharness | 5 | 3 | **3** | T7, T10 | Yes (`SESSION_NOTES.md`) | No |

`delta final (harness − noharness)`: unprimed **0**, primed **+1**.
Across both conditions: harness finals {4, 4}, noharness finals {4, 3}.

## Findings

1. **The continuity *machinery* never engaged — in either condition, either arm.**
   `.claude/devlog` and `.claude/progress` (the only dirs `session-context.sh` reads) stayed
   empty at every stage. Unprimed: the layer did **not** self-engage — no trail was written at
   all, despite §6 being confirmed in-context (the agent quoted "Leave a Trail Across Sessions"
   under `claude --print`). Primed: a trail *was* written, but as a free-form `SESSION_NOTES.md`
   — **including the harness arm**, which bypassed its own canonical dirs. So the SessionStart
   hook had nothing to surface in any run. The harness-specific apparatus contributed zero.

2. **When prompted, the model does excellent continuity natively — identically across arms.**
   Both primed `SESSION_NOTES.md` capture the domain traps cleanly (balances→AVG, flows→SUM,
   `TRUNC(MONTH_DT)` for the EOM trap, `COUNT(DISTINCT INN)`, `FETCH FIRST`). This is native
   behavior available to both arms once primed — not a practice-layer effect.

3. **The handoff note did not prevent regression.** Both primed arms regressed 5→3 at S2
   (lost T7 + T10) despite the note documenting the rules — the staged rebuild drifted anyway.
   The `+1` final edge (harness 4 vs noharness 3) is within build-noise (finals {4,4} vs {4,3},
   n=1): no meaningful separation.

4. **Functional score is flat; structural quality differed once (unprimed).** The unprimed
   harness arm produced a more modular, more-tested layout (`nl2sql/` package + `tests/` with
   unit+integration) vs noharness's flat `nl2sql.py`; both scored identically. The oracle judges
   *result* correctness and is blind to structure. (Primed builds converged to similar flat
   layouts in both arms — so the structural delta itself is likely build-noise, not a layer effect.)

## Conclusion

The multi-session A/B does **not** reveal value from the continuity *apparatus* — it confirms
#52/#61 from the continuity angle. The encoded machinery (SessionStart hook + canonical
`.claude/{devlog,progress}`) is **bypassed**: unprimed it never self-triggers, primed the model
writes an ad-hoc `SESSION_NOTES.md` the hook can't read. This is the foundational principle in
action — under a capable model, bespoke apparatus encoding "the model can't carry state across
sessions" is redundant; the model does lightweight handoff natively when asked. The hook adds
value **only** if the trail lands in its canonical dirs, which requires either an explicit
instruction to use `.claude/progress` **or** habit from real iterative human-in-the-loop work —
neither present in an autonomous `--print` build.

**Caveats:** n=1 per arm per condition — directional, not a power result. The agent-under-test
is claude-sonnet-4-6 (build model), not Opus 4.8; a weaker build model may lean on apparatus
more (untested). The oracle is deterministic (5/5/5, #60), so the scoring side carries no noise;
all residual variance is in the stochastic build.

## Artifacts

- `unprimed_raw.json`, `primed_raw.json` — full per-stage per-task vectors + mechanism snapshots.
- `primed-harness-SESSION_NOTES.md`, `primed-noharness-SESSION_NOTES.md` — the trails each arm
  wrote (native continuity, both free-form, neither in the hook's canonical dirs).
- `unprimed-run.log`, `primed-run.log` — driver stdout.
