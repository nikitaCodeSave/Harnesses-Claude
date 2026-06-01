# Harness-audit regression fixture

Validates that the global `claude-code-harness` skill + `~/.claude/CLAUDE.md` bundle, run by a
**fresh-context agent**, audits a flawed harness correctly — especially the model-agnostic
**triage rule** added in devlog #68 (de-version *behavioral* version-bindings; **keep**
provenance/config/historical refs).

## How to run

Spawn a fresh agent (no priming with the answer key) and tell it to audit
`./.claude/` with the `claude-code-harness` skill in Audit mode, READ-ONLY, emitting a findings
table with a `version-ref class` column (`behavioral` | `provenance/config` | `none`). Then score
against the key below. (Fresh context matters — it is also a §8 judge≠author check.)

## Planted defects (answer key)

| ID | Where | Type | Expected |
|---|---|---|---|
| D1 | `CLAUDE.md` «Под Opus 4.7 модель сама выберет стек / не умеет X» | behavioral version-binding | **de-version** → capable model |
| D2 | `CLAUDE.md` «проверяй что компилируется… прежде чем готово» | native-redundant rule | cut / altitude (debatable — lenient keep acceptable) |
| D3 | `CLAUDE.md` «перед каждым ответом перечитай diff, перепроверь себя» | in-context self-recheck ritual | **cut/replace** → fresh-context review (§8) |
| D4 | `agents/orchestrator.md` | built-in duplication (main thread = orchestrator) | **flag/remove** |
| D5 | `principles.md` «Grounded for Opus 4.8 / 4.7-era не перемерено / effort default high (4.7=xhigh)» | **provenance + config** | **KEEP** (precision test — must NOT de-version/strip) |
| — | `CLAUDE.md` «не трогай prod.tfvars» | legitimate guardrail | NOT a defect (precision) — ideally upgrade to `permissions.deny` |

**Critical discriminator:** de-version D1 but KEEP D5, though both contain "Opus 4.x".

## Run log

### 2026-06-01 — fresh general-purpose agent, global bundle (devlog #69)
- **Recall:** D1 ✅ (de-version, classed `behavioral`), D3 ✅ (cut + cited the §8/#62 "in-context
  premortem = 0 lift" evidence, proposed fresh-context discovery-critic), D4 ✅ (flag/remove + caught
  the spawn-per-subtask over-reach). D2 — defensible lenient KEEP ("sound verification expectation"),
  judgment difference not a clear error.
- **Precision (the triage rule):** D5 split into 3 findings, **all** explicitly `provenance/config` →
  KEEP, with correct reasoning (grounding stamp / un-re-measured finding / config+historical). The
  `prod.tfvars` guardrail kept **and** correctly upgraded to a `permissions.deny` proposal (§7).
  **Zero false-positives** — no provenance stripped, no legitimate guardrail flagged as a defect.
- **Verdict:** PASS. Version triage 4/4 correct (1 behavioral→de-version, 3 provenance→keep). §7 and
  §8 principles propagated into the cold-context audit. n=1 / single fixture — capability check with
  visible correct reasoning, not a power result.
