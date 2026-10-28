# Harness evolution — D-cycles and strip revision

The procedure for evolving the **canon** — this plugin's repository
(`nikitaCodeSave/claude-code-harness`) — by empirical signals, not by taste.
(An operator's own behavioral baseline lives in their `~/.claude/CLAUDE.md` and evolves
separately — the kit does not ship or re-distill a copy of it.)
Two operations: the **D-cycle** (folding proven findings inward) and the **strip revision**
(carrying obsolete pieces outward). Both are subordinate to the headline principle: a component
lives only as long as it encodes something the model does not do natively.

## Refresh ledger — the baseline for the delta

The canon ages along three **external** axes: **CC version** (new primitives), **model generation**
(what the model does natively, effort defaults), and **approaches** (first-party essays, arXiv,
community). So the strip revision compares a *delta* rather than "everything from scratch", the
canon carries a provenance stamp per axis — its last grounding point on each. One stamp is the
normal case; they separate when an axis is re-grounded on its own, as the model axis was on
2026-09-22 while the CC-primitives sweep stayed where it was:

<!-- harness-refresh-ledger
last-grounded (model axis, 2026-09-22): CC v2.1.280 · Claude 5 family (Opus 5.5 `claude-opus-5-5` = the default Opus on every paid plan — Pro/Team Standard moved off Sonnet 5 in 2.1.280; Fable 5.1 = the default Fable since 2.1.257; Opus 5 and Fable 5 legacy; Sonnet 5, Haiku 4.5 current)
last-grounded (CC-primitives + approaches axes): still CC v2.1.251 · 2026-08-29 — **the functional 2.1.252→2.1.280 sweep has not been run**; only model / effort-default / fast-mode lines were re-grounded on 2026-09-22, so a non-model built-in claim in `native-capabilities.md` still carries the 2.1.251 stamp
model-axis sources (2026-09-22): changelog delta 2.1.251→2.1.280 filtered to model/effort/fast-mode entries (local cache) · platform.claude.com models overview (lineup, pricing, cache-read rates, reliable cutoffs, per-model default effort) · platform.claude.com/docs/en/models/opus-5-5/migration-guide (four breaking changes; default effort `medium` vs Opus 5's `high`; thinking cannot be disabled at all; forced `tool_choice` 400; narration moves into progress-update thinking blocks) · platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting (per-model thinking table — the scoping oracle: the disabled-thinking traps are Opus 5's alone, Opus 4.8/4.7 default to thinking *off*) · code.claude.com/docs/en/model-config (CC-side effort defaults; **user-settings `effortLevel` does not reach Opus 5.5**, `modelSettings`, `maxEffortLevel`, plan defaults incl. Foundry on Sonnet 4.5) · code.claude.com/docs/en/fast-mode (Opus 5.5 supported and the fast-mode default since 2.1.280, $8/$40) · prompting-claude-opus-5-5 (128k max_tokens finding; the measured cross-model effort comparison lives only here) · live strings-probe with a control needle: `claude-opus-5-5` 15 hits in native 2.1.280 vs **0** in the Desktop-bundled 2.1.275 (needle `claude-opus-5` 24/21) — Desktop sessions cannot select the new default
also folded from the same window, being effort/permission mechanisms the filter caught: `maxEffortLevel` + per-model `modelSettings` (2.1.267) and the auto-mode classifier moving server-side by default for API/Enterprise/third-party providers (2.1.278)
refute-pass 2026-09-22 (one fresh-context same-vendor auditor against first-party): **1 CRITICAL + 5 MAJOR on a diff whose arithmetic was almost entirely right** — every price, cutoff, context size and version pin verified, while the failures were layer attribution and provenance: Opus 5's disabled-thinking traps had been extended to Opus 4.8 (wrong per the per-model table); the inert-on-Opus-5.5 user-settings `effortLevel` was left documented as a working lever, understating an `xhigh`→`medium` two-rung silent drop; Messages-API-only guidance was sold to `--print` runners in a file whose legend promises CLI-usable content; and the headline effort comparison was cited to two pages that do not carry it while its real page sat in the row marked "not yet folded". Lesson for this ledger: on a model refresh the numbers are the easy part — **check which layer each claim belongs to and which page actually says it**
sources-checked (2.1.251 functional sweep, 2026-08-29): changelog delta 2.1.227→2.1.251 (local cache, functional Added/Changed/Removed sweep) · code.claude.com/docs/en/whats-new weeks 32-34 · code.claude.com/docs/en/agent-teams (full re-read — TeamCreate/TeamDelete removed in 2.1.178, named-subagent-becomes-teammate, teammateMode, model precedence) · code.claude.com/docs/en/hooks (31 documented vs 33 in binary) · live binary strings-probe on 2.1.251 (PreModelSwitch/PostModelSwitch, CLAUDE_CODE_RESTRICTED, CLAUDE_CODE_SUBAGENT_MODEL, promptCacheTtl/subagentPromptCacheTtl, modelPicker, ANTHROPIC_DEFAULT_MODEL, teammateMode) · industry (OpenAI open-sourced the Codex harness under Apache-2.0 on 2026-08-20; arXiv 2608.23552 Prime Agent, 2608.17528 Agent Lightning v1.0) · prior grounding at CC v2.1.226 / 2026-08-08
refute-pass 2026-08-29 (v1.23.1–1.23.5, five same-vendor auditors + one cross-vendor): docs pages model-config · sub-agents · tools-reference · code-review · permission-modes · settings-reference · skills · agent-view · claude-directory; live probes: permission-rule warnings on a seeded settings file (`Grep(path)` silent, `MultiEdit` double-warns), `claude agents --json` field names, subagent-transcript forensics on five delegates. **Two of that pass's conclusions were then reverted by the cross-vendor reviewer against the local changelog cache**: `CLAUDE_CODE_SUBAGENT_MODEL` is a default (not an override) per the 2.1.251 note, and background `&` *is* classifier-routed per 2.1.218 — the docs pages had gone stale relative to the changelog, and `claude auto-mode defaults` does not enumerate circuit breakers. Lesson recorded in the D-cycle: when a docs page and the changelog of the running version disagree, the changelog wins
-->

A stamp is updated at the end of each strip revision (the external-intake pass below), and a
partial re-grounding updates only the axis it actually covered — **it must say so, because the
cost of a silent over-claim is the next session skipping a delta it thinks was swept.** The
current CC version to compare against is `claude --version`; the built-ins snapshot lives in
`native-capabilities.md`, and its version line after a refresh **must match** the stamp of the
axis it describes (when the axes diverge, that file says which of its claims carry which stamp).
A delta of `claude --version` against the ledger is a standalone revision trigger (visible at the
start of a session, with no extra machinery).

## Signal sources

- The project's `.claude/harness-journal.md` — 1–3 "kit-fell-short / kit-got-in-the-way"
  observations per session (opt-in; `operator-playbook.md` §2 says when it is worth keeping).
- The verdicts of external audits (a fresh session told to refute, `/code-review ultra`).
- The operator's corrections along the way (the recurring ones especially).
- **External drift** (CC version / model / approaches) — compared during the strip revision, the
  external-intake pass; the baseline is the refresh-ledger above.

## D-cycle (≈1 session)

Trigger: a milestone closed, or ≥5 substantive observations accumulated. For projects **without a
journal** (it is opt-in) there is no journal trigger — there, milestone-close and the verdicts of
fresh-context audits are what work; don't wait for "5 observations" that have nowhere to come from.

1. **Collect** the journal observations + audit verdicts + operator corrections for the period.
2. **Classify** each: `kit-gap` (the canon didn't cover a recurring need) ·
   `project-specific` (stays in the project CLAUDE.md/rules) · `single-incident`
   (keep watching) · `noise`.
3. **Gate**: only a `kit-gap` with multi-source evidence or repeated empirics passes into the
   canon. **A single-incident does not become an invariant** — it stays in the journal marked
   "watch".
4. **Fold** — a surgical edit of a specific reference (checklist / discipline /
   native-capabilities), not a new file and not a new layer. The wording is model-agnostic;
   evidence provenance (dates, n) is acceptable and desirable. Empirics: harness gains localize in
   tools/middleware/memory, NOT in prose (AHE ablation, arXiv 2604.25850) — prefer a fold into a
   mechanical carrier (a checklist step, a permission rule, a schema) over a new paragraph of prose.
5. **Record it**: a commit to the plugin repo + a devlog entry there listing
   "finding → where it went → evidence". A significant change to the kit's composition →
   a release via `scripts/release.sh <version>` (bump `version` in `plugin.json` — the single
   source of truth — + tag + push). (Maintainer's step: commit/devlog — in the plugin repo;
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
2. **First-party docs / blog** (code.claude.com/docs, anthropic.com / claude.com) → shifts in
   defaults (effort, model-config), new canonical patterns. **When a docs page and the changelog
   of the version you are running disagree, the changelog wins** — a page describes a steady state
   and is updated by hand; a release note is written when the behaviour changes. Two claims were
   fixed in the wrong direction on 2026-08-29 because a settings page still carried pre-upgrade
   semantics and was treated as the newer source. The changelog cache is local
   (`~/.claude/cache/changelog.md`), so this check costs a grep, not a fetch.
3. **`evidence-base.md` source catalog** → new essays / arXiv per the T1–T7 rubric.
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
3. Obsolete pieces are **deleted, not archived into the canon** (history stays in git + devlog).
4. Whatever the last D-cycle added and that didn't work is the first candidate for removal.
5. **Check the oracle's scope against the claim's scope before writing either down.** A probe
   answers about the moment and the layer where it was taken; a sentence in a reference asserts
   something about a whole lifetime or a whole configuration. A spawn-time binary probe cannot
   settle a property the runtime creates later — an empty field at T0 is what lazy creation looks
   like — and a `--help` listing cannot settle what a subcommand does. Put the oracle where the
   phenomenon lives (act, then observe the artifact), and if the two scopes cannot be made to
   match, write the narrower claim you actually measured.

At the end of the revision — **update the refresh ledger** (new CC version / model / date /
checked sources), sync the version line of `native-capabilities.md`, and record a devlog entry. A
significant shift in the canon's composition → bump `version` (see D-cycle step 5).

## The procedure's evidence base

Grown on the dogfood track (the maintainer's lab Harnesses-Claude, devlog #78–#82 — artifacts not
shipped with the kit): 2 D-cycles, 12 findings folded into the kit, each with journal or audit
empirics; the first-party grounding is Anthropic's "review your configuration every 3-6 months"
and "find the simplest solution possible" (see `references/evidence-base.md`).
