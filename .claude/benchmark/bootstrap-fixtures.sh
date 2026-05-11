#!/usr/bin/env bash
# Bootstrap external benchmark fixtures from corpus.yml.
#
# Reads .claude/loop/corpus.yml `fixtures.external[]` entries and ensures each
# fixture is cloned + checked out at the pinned commit. Idempotent: existing
# clones at the correct commit are left alone; mismatched HEADs are re-pinned
# (with --force) or reported (without).
#
# Usage:
#   bootstrap.sh                  # ensure all external fixtures present
#   bootstrap.sh --force          # re-pin existing clones if HEAD diverges
#   bootstrap.sh --check          # verify only; exit 1 if any missing/diverged
#   bootstrap.sh --list           # print parsed entries and exit
#
# Exit codes: 0 = all fixtures at pinned commits; 1 = mismatch/missing (--check)
# or unrecoverable error; 2 = bad args.

set -uo pipefail

FORCE=0; CHECK_ONLY=0; LIST_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        --list)  LIST_ONLY=1; shift ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CORPUS="$HARNESS_ROOT/.claude/loop/corpus.yml"
[[ -f "$CORPUS" ]] || { echo "FAIL: corpus.yml not found at $CORPUS" >&2; exit 1; }

command -v git >/dev/null 2>&1 || { echo "FAIL: 'git' required" >&2; exit 1; }

# Parse fixtures.external[] entries. Format expected:
#   fixtures:
#     external:
#       - name: <id>
#         url: <git-url>
#         path: <relative-or-abs path>
#         commit: <full-sha>
# Emits one TSV line per entry: name\turl\tpath\tcommit
parse_entries() {
    awk '
        /^fixtures:/                    { in_fix=1; next }
        in_fix && /^  external:/        { in_ext=1; next }
        in_fix && /^[a-zA-Z]/           { in_fix=0; in_ext=0 }
        in_ext && /^[a-zA-Z]/           { in_ext=0 }
        in_ext && /^    - name:/ {
            if (name) print name "\t" url "\t" path "\t" commit
            name=$0; sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", name)
            url=""; path=""; commit=""; next
        }
        in_ext && /^      url:/         { v=$0; sub(/^[[:space:]]*url:[[:space:]]*/, "", v); url=v; next }
        in_ext && /^      path:/        { v=$0; sub(/^[[:space:]]*path:[[:space:]]*/, "", v); path=v; next }
        in_ext && /^      commit:/      { v=$0; sub(/^[[:space:]]*commit:[[:space:]]*/, "", v); commit=v; next }
        END { if (name) print name "\t" url "\t" path "\t" commit }
    ' "$CORPUS"
}

ENTRIES=$(parse_entries)
[[ -z "$ENTRIES" ]] && { echo "FAIL: no external fixtures parsed from $CORPUS" >&2; exit 1; }

if [[ $LIST_ONLY -eq 1 ]]; then
    printf "%s\n" "$ENTRIES" | awk -F'\t' '{ printf "%-40s %s @ %s\n", $1, $2, $4 }'
    exit 0
fi

MISMATCH=0
while IFS=$'\t' read -r NAME URL REL_PATH COMMIT; do
    [[ -z "$NAME" ]] && continue
    ABS_PATH="$REL_PATH"
    [[ "$ABS_PATH" != /* ]] && ABS_PATH="$HARNESS_ROOT/$REL_PATH"

    if [[ ! -d "$ABS_PATH/.git" ]]; then
        if [[ $CHECK_ONLY -eq 1 ]]; then
            echo "MISSING  $NAME  (expected $ABS_PATH @ ${COMMIT:0:8})"
            MISMATCH=1
            continue
        fi
        echo "CLONE    $NAME  → $ABS_PATH"
        mkdir -p "$(dirname "$ABS_PATH")"
        git clone --quiet "$URL" "$ABS_PATH" || { echo "FAIL: clone failed for $NAME" >&2; exit 1; }
        git -C "$ABS_PATH" checkout --quiet "$COMMIT" || { echo "FAIL: checkout $COMMIT failed for $NAME" >&2; exit 1; }
        echo "OK       $NAME  @ ${COMMIT:0:8}"
        continue
    fi

    CURRENT=$(git -C "$ABS_PATH" rev-parse HEAD 2>/dev/null || echo "")
    if [[ "$CURRENT" == "$COMMIT" ]]; then
        echo "OK       $NAME  @ ${COMMIT:0:8}"
        continue
    fi

    if [[ $CHECK_ONLY -eq 1 ]]; then
        echo "DIVERGED $NAME  (HEAD ${CURRENT:0:8} != pinned ${COMMIT:0:8})"
        MISMATCH=1
        continue
    fi

    if [[ $FORCE -eq 0 ]]; then
        echo "SKIP     $NAME  (HEAD ${CURRENT:0:8} != pinned ${COMMIT:0:8}; pass --force to re-pin)"
        MISMATCH=1
        continue
    fi

    echo "RE-PIN   $NAME  (${CURRENT:0:8} → ${COMMIT:0:8})"
    git -C "$ABS_PATH" fetch --quiet origin "$COMMIT" 2>/dev/null || git -C "$ABS_PATH" fetch --quiet origin
    git -C "$ABS_PATH" checkout --quiet "$COMMIT" || { echo "FAIL: re-pin $COMMIT failed for $NAME" >&2; exit 1; }
    echo "OK       $NAME  @ ${COMMIT:0:8}"
done <<< "$ENTRIES"

[[ $CHECK_ONLY -eq 1 && $MISMATCH -ne 0 ]] && exit 1
exit 0
