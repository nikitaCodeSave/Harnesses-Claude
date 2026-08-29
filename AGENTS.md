# Harnesses-Claude — operational notes for coding agents

Read this before changing anything here. It carries what the repository cannot tell you by itself.
Claude Code additionally loads `.claude/CLAUDE.md` (design principles and scope rules); agents from
other vendors get this file.

## What this repository is

A **laboratory for Claude Code harness design**, not an application and not a template. There is no
build, no runtime, no package to ship. The artifacts are markdown, benchmark rigs, and a devlog.

The shippable product lives in a **different repository** — `~/PROJECTS/claude-code-harness`
(public: `github.com/nikitaCodeSave/claude-code-harness`). That is the source of truth for the
plugin; this repo is where its changes are grounded and measured. A change to plugin content
belongs there, not here.

## Commands

```bash
# regenerate the devlog index after adding an entry (required — index.json/tldr.md are derived)
~/PROJECTS/claude-code-harness/plugins/devlog/bin/devlog-reindex

# validate the plugin manifest (run in the kit repo)
claude plugin validate .

# permission-rule health for this repo: pass = prints NOTHING
claude --print "ok" </dev/null 2>&1 >/dev/null | grep -E '^(Permission |Ignoring .*permissions\.allow)'
```

Done = these exit 0 and the reindex reports no ERRORS. There is no test suite to run: the oracle
for a documentation change is the reindex validator plus the drift detector below.

```bash
# drift detector — version pins that leaked into version-free docs
grep -rnE "Opus 4\.[0-9]|Opus [0-9]|Sonnet [0-9]|v?2\.1\.[0-9]{3}" --include="*.md" . \
  | grep -vE "(archive/|devlog/|/audits/|CHANGELOG\.md|native-capabilities\.md)"
```

## Boundaries

- **Always**: put a devlog entry in `.claude/devlog/entries/NNNN-<slug>.md` after a substantive
  change and regenerate the index. The filename slug must equal `slugify(title)` — the reindexer
  rejects a mismatch, and that check is the reason entries stay findable.
- **Ask first**: anything under `.claude/benchmark/` (measurement provenance), and any change to
  the plugin content in the other repository.
- **Never**: edit frozen layers — `.claude/docs/archive/`, `.claude/devlog/entries/archive/`,
  `.claude/audits/`, and existing devlog entries. They are point-in-time records; rewriting them
  falsifies the provenance later work stands on. Never hand-edit `index.json` or `tldr.md` —
  they are generated.

## Conventions that are not obvious from the files

- **Version pins live in exactly one file.** Only
  `~/.claude/skills/claude-code-harness/references/native-capabilities.md` states a Claude Code
  version. Every other live document describes behavior without binding it to a release and points
  there. A pin duplicated in two documents goes stale in one of them silently.
- **Live layer vs archive.** Documents under `.claude/docs/` describe the current state, not the
  history of how it got there — "was → became" narrative belongs in git and the devlog. The
  archive directories are the opposite: frozen, never edited.
- **Single-incident does not become a rule.** A new invariant needs multi-source evidence or
  repeated empirics. This is the repository's central discipline; a change that adds a rule on one
  observation will be rejected on review.
- **The devlog is in Russian, the shipped kit is in English.** That split is deliberate: the kit
  travels to other people, the lab's journal does not.

## Reviewing work here

Prefer refuting to confirming: name the invariant, then look for an input or a state that breaks
it. A finding is worth reporting when it affects correctness or a stated requirement — style
preferences are noise in this repository, which is prose to begin with. Where a claim rests on a
measurement, check whether the oracle is independent of the claim and whether the run varied the
variable the conclusion names; that failure mode has produced real wrong entries here before.
