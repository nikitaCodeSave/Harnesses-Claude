# Harness evolution — D-cycles and strip revision

The procedure for evolving the **canon** — the plugin's repository
(`nikitaCodeSave/claude-code-harness`) — by empirical signals, not by taste.
(An operator's own `~/.claude/CLAUDE.md`, if they keep one, evolves separately — the kit does
not ship or re-distill a copy of it. This lab's operator keeps none.)
Two operations: the **D-cycle** (folding proven findings inward) and the **strip revision**
(carrying obsolete pieces outward). Both are subordinate to the headline principle: a component
lives only as long as it encodes something the model does not do natively.

## Refresh ledger — the baseline for the delta

The canon ages along three **external** axes: **CC version** (new primitives), **model generation**
(what the model does natively, effort defaults), and **approaches** (first-party essays, arXiv,
community). So the strip revision compares a *delta* rather than "everything from scratch", the
canon carries a provenance stamp per axis — its last grounding point on each — in the refresh
ledger at the top of `native-capabilities.md`, the one file that names versions.

A stamp is updated at the end of each strip revision (the external-intake pass below), and a
partial re-grounding updates only the axis it actually covered — **it must say so, because the
cost of a silent over-claim is the next session skipping a delta it thinks was swept.** The
current CC version to compare against is `claude --version`; the built-ins snapshot lives in
`native-capabilities.md`, and its version line after a refresh **must match** the stamp of the
axis it describes (when the axes diverge, that file says which of its claims carry which stamp).
A delta of `claude --version` against the ledger is a standalone revision trigger (visible at the
start of a session, with no extra machinery).

## Signal sources

- Observations from the projects that run the kit — where it fell short or got in the way.
- The verdicts of external audits (a fresh session told to refute, `/code-review ultra`).
- The operator's corrections along the way (the recurring ones especially).
- **External drift** (CC version / model / approaches) — compared during the strip revision, the
  external-intake pass; the baseline is the refresh ledger in `native-capabilities.md`.

## D-cycle (≈1 session)

Trigger: a milestone closed, or the verdict of a fresh-context audit. There is no
observation-count trigger: no journal accumulates observations, so a "wait for 5" threshold would
never fire.

1. **Collect** the project observations + audit verdicts + operator corrections for the period.
2. **Classify** each: `kit-gap` (the canon didn't cover a recurring need) ·
   `project-specific` (stays in the project CLAUDE.md/rules) · `single-incident`
   (keep watching) · `noise`.
3. **Gate**: only a `kit-gap` with multi-source evidence or repeated empirics passes into the
   canon. **A single-incident does not become an invariant** — it stays out of the canon, and
   the watch is for a recurrence.
4. **Fold** — a surgical edit of a specific reference (checklist / discipline /
   native-capabilities), not a new file and not a new layer. The wording is model-agnostic and
   keeps the number that carries the decision (n, the measured delta); its provenance — dates,
   runs, sources — goes into the record of step 5, not into the canon. Empirics: harness gains
   localize in tools/middleware/memory, NOT in prose (AHE ablation, arXiv 2604.25850) — prefer a
   fold into a mechanical carrier (a checklist step, a permission rule, a schema) over a new
   paragraph of prose.
5. **Record it**: a commit to the plugin repo whose message lists
   "finding → where it went → evidence"; a decision later work must follow → an ADR. A
   significant change to the kit's composition → a release via `scripts/release.sh <version>`
   (bump `version` in `plugin.json` — the single source of truth — + tag + push) with a
   `CHANGELOG.md` entry. (Maintainer's step: commit/ADR — in the plugin repo;
   the empirics of experiments — in the lab repo. On a consumer machine this step does not
   exist — there the canon is updated with `/plugin update`.)

D-cycle anti-pattern: "since the session is open anyway, I'll tidy up the neighboring sections
too". Edits only from the cycle's findings; everything else is a separate decision.

## Strip revision (every 3–6 months, on a major model release, or on a CC-version delta)

The cadence trigger is the calendar (3–6 months), a major model release, **or** a delta of
`claude --version` against the refresh ledger. The revision runs in two passes: first
**external-intake** (what changed outside — updates the canon to the new reality), then
**re-test** (what in the canon has become obsolete relative to the changed model/environment).

### Pass 1 — external-intake (what shifted outside)

Compare the delta *from the refresh ledger*, not "everything from scratch". Sources are CLI-native
(WebFetch / WebSearch, no Anthropic API):

1. **CC changelog** since the ledger version → new hooks / tools / flags / commands. Fold each
   relevant one into `native-capabilities.md` (it must not fall behind live `claude --version`).
   Numbers are the easy part: for each claim, check which layer it belongs to (CLI, API, model,
   plan) and which page actually states it.
2. **First-party docs / blog** (code.claude.com/docs, anthropic.com / claude.com) → shifts in
   defaults (effort, model-config), new canonical patterns. **When a docs page and the changelog
   of the version you are running disagree, the changelog wins** — a page describes a steady state
   and is updated by hand; a release note is written when the behaviour changes. A settings page
   that still carried pre-upgrade semantics, taken as the newer source, has turned two claims the
   wrong way. The changelog cache is local
   (`~/.claude/cache/changelog.md`), so this check costs a grep, not a fetch.
3. **The source catalog `external-sources.md`** → new essays / arXiv per the T1–T7 rubric.
4. Run each finding through the D-cycle gate (`kit-gap` with multi-source · `single-incident` ·
   `noise`). An external signal **is not privileged**: "an article came out / a flag appeared"
   does not become an invariant as a single-incident; the fold is a point-edit of a specific
   reference, not a new layer.

### Pass 2 — re-test (what in the canon is obsolete)

1. List the canon's components with their assumption "the model can't do X"
   (including every "under Opus <version>" in the texts).
2. Re-test each: does the model do X natively now. The quick tool is
   `claude --safe-mode` (start with no CLAUDE.md/skills/hooks/MCP): if it's no worse without the
   component — it's obsolete.
3. Obsolete pieces are **deleted, not archived into the canon** (history stays in git).
4. Whatever the last D-cycle added and that didn't work is the first candidate for removal.
5. **Check the oracle's scope against the claim's scope before writing either down.** A probe
   answers about the moment and the layer where it was taken; a sentence in a reference asserts
   something about a whole lifetime or a whole configuration. A spawn-time binary probe cannot
   settle a property the runtime creates later — an empty field at T0 is what lazy creation looks
   like — and a `--help` listing cannot settle what a subcommand does. Put the oracle where the
   phenomenon lives (act, then observe the artifact), and if the two scopes cannot be made to
   match, write the narrower claim you actually measured.

At the end of the revision — **update the refresh ledger** in `native-capabilities.md` (CC
version / model / date / checked sources per axis) and its version line, and commit with the
findings in the message. A
significant shift in the canon's composition → bump `version` (see D-cycle step 5).

## The procedure's evidence base

Grown on this lab's dogfood track (artifacts not shipped with the kit): 2 D-cycles, 12 findings
folded into the kit, each backed by project-observation or audit empirics. The first-party
grounding is Anthropic's "review your configuration every 3-6 months" (*How Claude Code works in
large codebases*) and "find the simplest solution possible" (*Building effective agents*); the
source catalog is `external-sources.md`.
