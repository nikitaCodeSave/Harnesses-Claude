#!/usr/bin/env bash
# Behavior test for the GLOBAL ~/.claude/hooks/session-context.sh SessionStart hook.
# Fixtures are built in a temp dir and fed via CLAUDE_PROJECT_DIR; the hook's stdout
# is injected verbatim into the model's context, so the invariant under test is:
# a BOUNDED, few-line digest — never a whole file, whatever the project contains.
#
# Regression-guards the 2026-07-16 refuter findings:
#   - unbounded tldr.md fast path (10 MB file -> 10 MB of context, ~2.5M tokens)
#   - stale tldr.md shadowing the entries/ source of truth
#   - fm() scanning the whole entry when a frontmatter field is absent
#   - *CLOSED* substring hiding an ACTIVE journal ("CLOSED-account migration")
# Run under several shells: SH=dash bash test-session-context.sh
set -uo pipefail

HOOK="${HOOK:-$HOME/.claude/hooks/session-context.sh}"
SH="${SH:-bash}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

run() { CLAUDE_PROJECT_DIR="$1" $SH "$HOOK" 2>&1; }

check() { # desc expected_substring actual
  if printf '%s' "$3" | grep -qF -- "$2"; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — expected to contain [$2], got [$3]"; fail=$((fail+1)); fi
}
check_absent() { # desc unexpected_substring actual
  if printf '%s' "$3" | grep -qF -- "$2"; then echo "FAIL: $1 — should NOT contain [$2], got [$3]"; fail=$((fail+1))
  else echo "PASS: $1"; pass=$((pass+1)); fi
}
check_empty() { # desc actual
  if [ -z "$2" ]; then echo "PASS: $1"; pass=$((pass+1))
  else echo "FAIL: $1 — expected empty, got [$2]"; fail=$((fail+1)); fi
}
check_bounded() { # desc max_bytes actual
  local n; n=$(printf '%s' "$3" | wc -c)
  if [ "$n" -le "$2" ]; then echo "PASS: $1 ($n bytes)"; pass=$((pass+1))
  else echo "FAIL: $1 — $n bytes exceeds cap of $2"; fail=$((fail+1)); fi
}

mkentry() { # dir id date title
  mkdir -p "$1/.claude/devlog/entries"
  printf -- '---\nid: %s\ndate: %s\ntitle: "%s"\nstatus: complete\n---\n\n# Body\ntext\n' \
    "$2" "$3" "$4" > "$1/.claude/devlog/entries/$2-slug.md"
}
BIG=$(head -c 300000 /dev/zero | tr '\0' 'X')

# === Baseline behavior =====================================================
p="$TMP/empty"; mkdir -p "$p"
check_empty "empty project -> silent" "$(run "$p")"

out=$(run "$TMP/nope"); rc=$?
check_empty "missing project dir -> silent" "$out"
[ "$rc" -eq 0 ] && { echo "PASS: missing project dir -> rc=0"; pass=$((pass+1)); } \
                || { echo "FAIL: missing project dir -> rc=$rc"; fail=$((fail+1)); }

p="$TMP/entries"; mkdir -p "$p"
mkentry "$p" 1 2026-01-01 "First entry"
mkentry "$p" 2 2026-01-02 "Second entry"
out=$(run "$p")
check "devlog: header"     "Recent devlog" "$out"
check "devlog: title"      "Second entry"  "$out"
check "devlog: date shown" "2026-01-02"    "$out"

p="$TMP/sort"; mkdir -p "$p"
for i in 8 9 10 11; do mkentry "$p" "$i" "2026-01-01" "Entry number $i"; done
out=$(run "$p")
check        "numeric sort: 11 present" "Entry number 11" "$out"
check        "numeric sort: 10 present" "Entry number 10" "$out"
check_absent "numeric sort: 8 dropped"  "Entry number 8"  "$out"
n=$(printf '%s' "$out" | grep -c '^  #')
[ "$n" -eq 3 ] && { echo "PASS: caps at 3 entries"; pass=$((pass+1)); } \
               || { echo "FAIL: caps at 3 entries — got $n"; fail=$((fail+1)); }

# === REGRESSION: the digest is BOUNDED, always ==============================
# The hook's whole purpose is a few lines of orientation. No project content —
# however malformed or hostile — may push a whole file into the context window.

# R1: huge title in an entry's frontmatter.
p="$TMP/huge-entry"; mkdir -p "$p"
mkentry "$p" 1 2026-01-01 "$BIG"
check_bounded "R1: huge entry title -> bounded" 4096 "$(run "$p")"

# R2: huge heading in tldr.md (the 2026-07-16 CRITICAL — was 10 MB in, 10 MB out).
p="$TMP/huge-tldr"; mkdir -p "$p/.claude/devlog"
printf '## #1 · 2026-01-01 · %s\n' "$BIG" > "$p/.claude/devlog/tldr.md"
check_bounded "R2: huge tldr heading -> bounded" 4096 "$(run "$p")"

# R3: huge body in an entry with NO title field (fm() must not scan the body).
p="$TMP/huge-body"; mkdir -p "$p/.claude/devlog/entries"
{ printf -- '---\nid: 1\ndate: 2026-01-01\n---\n\n'; printf '%s\n' "$BIG"; \
  printf 'title: SMUGGLED FROM BODY\n'; } > "$p/.claude/devlog/entries/1-slug.md"
out=$(run "$p")
check_bounded "R3: huge body, no title -> bounded" 4096 "$out"
check_absent  "R3: body line not smuggled in as title" "SMUGGLED FROM BODY" "$out"

# R4: huge progress journal.
p="$TMP/huge-prog"; mkdir -p "$p/.claude/progress"
printf '# %s\n' "$BIG" > "$p/.claude/progress/big.md"
check_bounded "R4: huge progress heading -> bounded" 4096 "$(run "$p")"

# R5: many huge entries + many huge journals at once (worst realistic case).
p="$TMP/huge-all"; mkdir -p "$p/.claude/progress"
for i in 1 2 3 4 5; do mkentry "$p" "$i" 2026-01-01 "$BIG"; \
  printf '# %s\n' "$BIG" > "$p/.claude/progress/t$i.md"; done
check_bounded "R5: everything huge -> still bounded" 4096 "$(run "$p")"

# === REGRESSION: tldr.md must not shadow the entries/ source of truth =======
# A stale tldr.md (rebuild-index.py not re-run after a new entry) previously won
# silently: entries held #12, the digest reported #2.
p="$TMP/stale"; mkdir -p "$p/.claude/devlog"
mkentry "$p" 12 2026-07-16 "FRESH entry twelve"
printf '# TLDR\n\n## #2 · 2026-01-01 · STALE entry two\n' > "$p/.claude/devlog/tldr.md"
out=$(run "$p")
check        "stale tldr: fresh entry surfaces" "FRESH entry twelve" "$out"
check_absent "stale tldr: stale entry dropped"  "STALE entry two"    "$out"

# === REGRESSION: CLOSED must be a status marker, not a substring ============
# An ACTIVE journal about closed accounts must stay visible.
p="$TMP/closed-fp"; mkdir -p "$p/.claude/progress"
printf '# Migrate CLOSED-account archive to S3\n\nin progress, 2 of 5 left\n' \
  > "$p/.claude/progress/migrate.md"
check "CLOSED substring in heading -> still shown" "migrate.md" "$(run "$p")"

p="$TMP/closed-fp2"; mkdir -p "$p/.claude/progress"
printf '# Task\n\n## Quick state — refactoring CLOSED-account handler, in progress\n' \
  > "$p/.claude/progress/refactor.md"
check "CLOSED substring in quick state -> still shown" "refactor.md" "$(run "$p")"

# A genuinely CLOSED journal stays filtered (the marker still works).
p="$TMP/closed-real"; mkdir -p "$p/.claude/progress"
printf '# Task beta\n\n## Quick state — CLOSED, shipped\n' > "$p/.claude/progress/beta.md"
check_empty "real CLOSED marker -> filtered" "$(run "$p")"

p="$TMP/closed-real2"; mkdir -p "$p/.claude/progress"
printf '# Task\n\n## Quick state\nCLOSED\n' > "$p/.claude/progress/g.md"
out=$(run "$p")
check_absent "CLOSED alone on quick-state line -> filtered" "CLOSED" "$out"

# === Progress behavior =====================================================
p="$TMP/prog"; mkdir -p "$p/.claude/progress"
printf '# Task alpha\n\n## Quick state\nhalf done, blocked on X\n' > "$p/.claude/progress/alpha.md"
out=$(run "$p")
check "progress: header"    "Active progress" "$out"
check "progress: file name" "alpha.md"        "$out"

p="$TMP/nostate"; mkdir -p "$p/.claude/progress"
printf '# Refactor the parser\n\nsome prose\n' > "$p/.claude/progress/gamma.md"
check "progress: heading fallback" "Refactor the parser" "$(run "$p")"

p="$TMP/many"; mkdir -p "$p/.claude/progress"
for i in 1 2 3 4 5; do printf '# Task %s\n\n## Quick state\nrunning\n' "$i" > "$p/.claude/progress/t$i.md"; sleep 0.01; done
out=$(run "$p")
n=$(printf '%s' "$out" | grep -c '\.md')
[ "$n" -eq 3 ] && { echo "PASS: progress caps at 3"; pass=$((pass+1)); } \
               || { echo "FAIL: progress caps at 3 — got $n"; fail=$((fail+1)); }

p="$TMP/both"; mkdir -p "$p/.claude/progress"
mkentry "$p" 1 2026-01-01 "Some change"
printf '# Task\n\n## Quick state\nin flight\n' > "$p/.claude/progress/x.md"
out=$(run "$p")
check "both: devlog section"   "Recent devlog"   "$out"
check "both: progress section" "Active progress" "$out"

p="$TMP/emptyprog"; mkdir -p "$p/.claude/progress"
check_empty "empty progress dir -> silent" "$(run "$p")"

# === Hostile / odd filenames ================================================
p="$TMP/odd"; mkdir -p "$p/.claude/devlog/entries" "$p/.claude/progress"
mkentry "$p" 1 2026-01-01 "Normal entry"
printf '# spaced\n\n## Quick state\nok\n' > "$p/.claude/progress/with space.md"
printf '# star\n\n## Quick state\nok\n' > "$p/.claude/progress/star*.md"
printf '# unicode\n\n## Quick state\nok\n' > "$p/.claude/progress/юникод.md"
out=$(run "$p"); rc=$?
[ "$rc" -eq 0 ] && { echo "PASS: odd filenames -> rc=0"; pass=$((pass+1)); } \
                || { echo "FAIL: odd filenames -> rc=$rc"; fail=$((fail+1)); }
check "odd filenames: normal entry still surfaces" "Normal entry" "$out"

echo "----"
echo "SHELL=$SH HOOK=$HOOK PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
