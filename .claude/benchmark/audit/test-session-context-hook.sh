#!/usr/bin/env bash
# Reproduce-test for the GLOBAL continuity hook ~/.claude/hooks/session-context.sh.
# Behavior-based (asserts observable additionalContext output), not print-probes.
# Each case builds a throwaway project dir and runs the hook with CLAUDE_PROJECT_DIR.
set -uo pipefail

HOOK="${HOOK:-${HOME}/.claude/hooks/session-context.sh}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

run() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK"; }   # echoes hook stdout
check() { # desc, actual, must-contain (or "<EMPTY>")
    local desc="$1" out="$2" want="$3"
    if [ "$want" = "<EMPTY>" ]; then
        if [ -z "$out" ]; then echo "PASS: $desc"; pass=$((pass+1));
        else echo "FAIL: $desc — expected empty, got: $out"; fail=$((fail+1)); fi
    else
        if printf '%s' "$out" | grep -qF "$want"; then echo "PASS: $desc"; pass=$((pass+1));
        else echo "FAIL: $desc — missing '$want' in: $out"; fail=$((fail+1)); fi
    fi
}

# --- Case A: empty project (no .claude) → silent, exit 0 --------------------
A="$tmp/empty"; mkdir -p "$A"
out="$(run "$A")"; rc=$?
check "A: empty project → no output" "$out" "<EMPTY>"
[ "$rc" -eq 0 ] && { echo "PASS: A exit 0"; pass=$((pass+1)); } || { echo "FAIL: A exit $rc"; fail=$((fail+1)); }

# --- Case B: devlog only → surfaces last 3 with titles ----------------------
B="$tmp/devlog"; mkdir -p "$B/.claude/devlog/entries"
for n in 1 2 3 4; do
    printf -- '---\nid: %d\ntitle: "Entry number %d"\n---\nbody\n' "$n" "$n" \
        > "$B/.claude/devlog/entries/000${n}-e${n}.md"
done
out="$(run "$B")"
check "B: shows newest entry #4"        "$out" "#4 Entry number 4"
check "B: shows #2 (within last 3)"     "$out" "#2 Entry number 2"
# invert: oldest #1 must be ABSENT (only last 3 surface)
if printf '%s' "$out" | grep -qF "Entry number 1"; then
    echo "FAIL: B should drop oldest #1"; fail=$((fail+1));
else echo "PASS: B drops oldest #1"; pass=$((pass+1)); fi

# --- Case C: progress only → surfaces active journal + quick state ----------
C="$tmp/prog"; mkdir -p "$C/.claude/progress"
printf '# Progress: my task\n\n**Quick state (2026-05-29):** doing the thing\n' \
    > "$C/.claude/progress/my-task.md"
out="$(run "$C")"
check "C: shows progress filename" "$out" "Active progress: my-task.md"
check "C: shows quick state"       "$out" "doing the thing"

# --- Case D: both present → both sections ------------------------------------
D="$tmp/both"; mkdir -p "$D/.claude/devlog/entries" "$D/.claude/progress"
printf -- '---\nid: 7\ntitle: "Lucky seven"\n---\n' > "$D/.claude/devlog/entries/0007-l.md"
printf '# P\n**Quick state:** wip\n' > "$D/.claude/progress/p.md"
out="$(run "$D")"
check "D: devlog section present"   "$out" "#7 Lucky seven"
check "D: progress section present" "$out" "Active progress: p.md"
check "D: valid JSON additionalContext" "$out" '"additionalContext"'

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
