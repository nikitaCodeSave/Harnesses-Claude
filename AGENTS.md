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
claude --print "ok" </dev/null 2>&1 >/dev/null | grep -E -A3 '^(Permission |Ignoring .*permissions\.allow|These settings )'
```

Done = these exit 0 and the drift detector below prints nothing. There is no test suite to run:
for a documentation change those two are the oracle.

```bash
# drift detector — instructions describe the present: no model or CLI versions, dates, journal refs
grep -rnE "(Opus|Sonnet|Haiku|Fable) [0-9]|v?2\.1\.[0-9]{3}|20[0-9]{2}-[0-9]{2}-[0-9]{2}|devlog #[0-9]" \
  AGENTS.md README.md WORKFLOW.md .claude/CLAUDE.md .claude/rules .claude/docs \
  | grep -vE "\.claude/docs/(archive/|adr/|native-capabilities\.md|external-sources\.md)"
```

## Boundaries

- **Always**: a decision that later work must follow becomes an ADR in
  `.claude/docs/adr/NNNN-<slug>.md` (Context / Decision / Consequences) in the session that made
  it; a measurement goes into its rig's `RESULTS.md`; what changed and why goes into the commit
  message. There is no journal beyond these — `.claude/docs/adr/0001-*` says why.
- **Ask first**: anything under `.claude/benchmark/` (measurement provenance), and any change to
  the plugin content in the other repository.
- **Never**: edit frozen layers — `.claude/docs/archive/`, `.claude/devlog/` (a closed journal),
  an existing `.claude/audits/<slug>/` (a new audit writes its own), and an accepted ADR (a new ADR
  supersedes it instead). They are point-in-time records; rewriting them
  falsifies the provenance later work stands on.

## Conventions that are not obvious from the files

- **Instructions describe the present; history lives in records.** `CLAUDE.md`, this file, the
  rules and the docs under `.claude/docs/` say what holds and why — no dates, version numbers,
  journal references or "was → became". Those live in records: git, ADRs, a rig's `RESULTS.md`,
  and `.claude/docs/native-capabilities.md`, the one file that names Claude Code and model
  versions (its refresh ledger records each grounding pass). An instruction links to a record
  instead of retelling it. The archive directories are frozen, never edited.
- **Single-incident does not become a rule.** A new invariant needs multi-source evidence or
  repeated empirics. This is the repository's central discipline; a change that adds a rule on one
  observation will be rejected on review.
- **The lab is written in Russian, the shipped kit in English.** That split is deliberate: the kit
  travels to other people, the lab's docs and ADRs do not.

## TypeSafe (Jev) — rules for writing integrations

TypeSafe is not an LLM. Jev takes a `state` plus typed questions and returns typed answers with
probabilities; it generates no text. Integration sandbox: `integrations/typesafe/` (own uv project
and venv — the repo-root `.venv` is unrelated and must not be pulled under a uv lock). Docs snapshot:
`docs/typesafe/` (its `README.md` says when it was taken; `llms.txt` lists the cookbooks).

- **Pin the version, never an alias.** An exact `model="jev-<x.y.z>"` (the pinned one lives in the
  code), never `jev-latest`: an alias moves on release and drags calibrated thresholds onto a
  different model. The response's `model` field
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
- **Limits** — tokens per request, `state` plus the longest question, options per Choice, rate
  limits — are in the docs snapshot; text input only. Rate limits change without notice — don't
  hard-code them.
- **Language.** English is the primary training language and where accuracy is best; other
  languages are handled but not equally well. Calibrate and test every threshold on real Russian
  examples before trusting it — the docs make no accuracy claim for Russian specifically.
- **The API shape.** The field is `state`, questions are a map, answers come back as
  `answers`/`nouls`/`choices`/`scores` with fields `noul` / `choice` / `score`; the package is
  `typesafe-sdk` (import `typesafe_sdk`). Examples with `document`, a `prompts` array,
  `probability` / `chosen` / `expectation` or the `typesafe-client` package are wrong for this API
  — don't copy them. `docs.typesafe.ai` is the reference; the console's docs can lag.

## Reviewing work here

Prefer refuting to confirming: name the invariant, then look for an input or a state that breaks
it. A finding is worth reporting when it affects correctness or a stated requirement — style
preferences are noise in this repository, which is prose to begin with. Where a claim rests on a
measurement, check whether the oracle is independent of the claim and whether the run varied the
variable the conclusion names; that failure mode produces confident wrong entries.
