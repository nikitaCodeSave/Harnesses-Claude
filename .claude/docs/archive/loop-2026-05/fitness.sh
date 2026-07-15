#!/usr/bin/env bash
# Deterministic accept/reject scorer for harness self-improvement loop.
# FROZEN — protected by loop-protected-guard.sh.
#
# Usage:
#   fitness.sh --baseline-state <STATE.md> --candidate-reports <glob> --tier0 pass|fail
#
# Output (stdout):
#   ACCEPT
#   REJECT: <reason>
# Exit code: 0 ACCEPT, 1 REJECT
#
# Logic delegated to fitness.py (yaml/json processing is too brittle in pure bash).

set -uo pipefail

LOOP_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-detect python with pyyaml: prefer system /usr/bin/python3 (likely has it),
# fall back to venv / PATH python3. fitness.py uses yaml.safe_load.
PYTHON=""
for cand in "/usr/bin/python3" "${VIRTUAL_ENV:-}/bin/python3" "$(command -v python3 2>/dev/null)"; do
    [[ -z "$cand" || ! -x "$cand" ]] && continue
    if "$cand" -c "import yaml" 2>/dev/null; then
        PYTHON="$cand"; break
    fi
done
if [[ -z "$PYTHON" ]]; then
    echo "REJECT: no python3 with pyyaml available (tried /usr/bin/python3, venv, PATH)"
    exit 1
fi

exec "$PYTHON" "$LOOP_DIR/fitness.py" "$@"
