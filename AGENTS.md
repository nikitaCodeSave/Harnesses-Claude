# Harnesses-Claude — operational notes for coding agents

Read this before changing anything here. It carries what the repository cannot tell you by itself.
Claude Code additionally loads `.claude/CLAUDE.md` (design principles and scope rules); agents from
other vendors get this file.

## What this repository is

A **laboratory for Claude Code harness design**, not an application and not a template. There is no
build, no runtime, no package to ship. The artifacts are markdown, benchmark rigs, and decision
records (ADRs).

The shippable product lives in a **different repository** — `~/PROJECTS/claude-code-harness`
(public: `github.com/nikitaCodeSave/claude-code-harness`). That is the source of truth for the
plugin; this repo is where its changes are grounded and measured. A change to plugin content
belongs there, not here.

## Commands

```bash
# validate the plugin manifest (run in the kit repo)
claude plugin validate .

# permission-rule health for this repo: pass = prints NOTHING
claude --print "ok" </dev/null 2>&1 >/dev/null | grep -E '^(Permission |Ignoring .*permissions\.allow)'
```

Done = these exit 0 and the drift detector below reports no hit in a file you touched. There is no
test suite to run: for a documentation change those two are the oracle.

```bash
# drift detector — version pins that leaked into version-free docs
grep -rnE "Opus 4\.[0-9]|Opus [0-9]|Sonnet [0-9]|v?2\.1\.[0-9]{3}" --include="*.md" . \
  | grep -vE "(archive/|devlog/|/audits/|CHANGELOG\.md|native-capabilities\.md|harness-evolution\.md)"
```

## Boundaries

- **Always**: a decision that later work must follow becomes an ADR in
  `.claude/docs/adr/NNNN-<slug>.md` (Context / Decision / Consequences) in the session that made
  it; a measurement goes into its rig's `RESULTS.md`; what changed and why goes into the commit
  message. There is no journal beyond these — `.claude/docs/adr/0001-*` says why.
- **Ask first**: anything under `.claude/benchmark/` (measurement provenance), and any change to
  the plugin content in the other repository.
- **Never**: edit frozen layers — `.claude/docs/archive/`, `.claude/devlog/` (the whole journal,
  closed 2026-10-28; "devlog #NNN" references still point into it), `.claude/audits/`, and an
  accepted ADR (a new ADR supersedes it instead). They are point-in-time records; rewriting them
  falsifies the provenance later work stands on.

## Conventions that are not obvious from the files

- **Version pins live in exactly one file.** Only
  `.claude/docs/native-capabilities.md` states a Claude Code
  version. Every other live document describes behavior without binding it to a release and points
  there. A pin duplicated in two documents goes stale in one of them silently. The refresh ledger in
  `.claude/docs/harness-evolution.md` records which version each grounding pass ran against — dated
  provenance, not a pin, so the detector skips it too.
- **Live layer vs archive.** Documents under `.claude/docs/` describe the current state, not the
  history of how it got there — "was → became" narrative belongs in git and the ADRs. The
  archive directories are the opposite: frozen, never edited.
- **Single-incident does not become a rule.** A new invariant needs multi-source evidence or
  repeated empirics. This is the repository's central discipline; a change that adds a rule on one
  observation will be rejected on review.
- **The lab is written in Russian, the shipped kit in English.** That split is deliberate: the kit
  travels to other people, the lab's docs and ADRs do not.

## TypeSafe (Jev) — rules for writing integrations

TypeSafe is not an LLM. Jev takes a `state` plus typed questions and returns typed answers with
probabilities; it generates no text. Integration sandbox: `integrations/typesafe/` (own uv project
and venv — the repo-root `.venv` is unrelated and must not be pulled under a uv lock). Docs snapshot
of 2026-09-19: `docs/typesafe/` (start at its `README.md`; `llms.txt` lists the cookbooks).

- **Pin the version, never an alias.** `model="jev-1.13.0"`, not `jev-latest`. An alias moves on
  release and drags calibrated thresholds onto a different model. The response's `model` field
  reports which version actually answered — log it.
- **Arithmetic, dates, counting and exact lookups belong in code.** Jev is not a calculator: it
  recognizes the shape of an answer instead of tallying, and reads dates as text rather than as
  ordered quantities. Give it the extraction (a Choice over enumerated parts), keep ordering,
  duration and every comparison in code.
- **Every Choice carries a no-match option** (`other` / `none of the above`). For "is there an
  answer at all", ask a *separate* Noul: Choice probabilities always sum to 1, so a Choice is
  relative — it settles *which* option, never *whether* any applies. A Noul is absolute and may be
  low for all of them.
- **Filter the state before sending it.** Accuracy falls as unrelated detail grows; Jev suffers
  context rot. Retrieve and filter in code, send only the fields the question needs.
- **Question ids never reach the model.** The map key is for your code only. All meaning must live
  inside `instructions` and `criteria`.
- **Do not carry a threshold across primitives.** A cutoff calibrated on a Noul is meaningless on a
  Choice and vice versa. Do not expect `P(x)` and `1 − P(not x)` to agree — measured in the docs at
  0.72 and 0.47 for the same judgment. Choice/Score `confidence` describes distribution
  concentration, not correctness.
- **Set confidence thresholds per action, by the cost of being wrong** — not one number for the
  whole system. A harmless preference tolerates low confidence; an irreversible action does not.
- **Weights and policy stay in code.** Score dimensions once, then let code change weights,
  rankings and filters — changing a weight must not require a new inference.
- **Limits.** 64k tokens per request; 32k for `state` plus the single longest question. A Choice
  accepts at most 255 options. Text input only. Rate limits (250k tok/s, 1200 req/min) adjust
  without notice.
- **Language.** English is the primary training language and where accuracy is best; other
  languages are handled but not equally well. Calibrate and test every threshold on real Russian
  examples before trusting it — the docs make no accuracy claim for Russian specifically.
- **Write against v1, not older examples.** The field is `state` (never `document`), questions are
  a map (not a `prompts` array), answers come back as `answers`/`nouls`/`choices`/`scores` with
  fields `noul` / `choice` / `score` (not `probability` / `chosen` / `expectation`). The package is
  `typesafe-sdk` (import `typesafe_sdk`); the old `typesafe-client` sends `document` and no longer
  works. The console's own docs still show the stale versions — `docs.typesafe.ai` is the truth.

## Reviewing work here

Prefer refuting to confirming: name the invariant, then look for an input or a state that breaks
it. A finding is worth reporting when it affects correctness or a stated requirement — style
preferences are noise in this repository, which is prose to begin with. Where a claim rests on a
measurement, check whether the oracle is independent of the claim and whether the run varied the
variable the conclusion names; that failure mode has produced real wrong entries here before.
