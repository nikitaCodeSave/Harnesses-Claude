#!/usr/bin/env bash
# Load the seeded fixture into a live Oracle, then run the benchmark.
#
# Oracle creds come ONLY from the environment (never hardcoded, never .env):
#   AI_ANALYST_ORACLE_USER / AI_ANALYST_ORACLE_PWD / AI_ANALYST_ORACLE_DSN
#   (or the standard ORACLE_USER / ORACLE_PASSWORD / ORACLE_DSN)
#
# If python-oracledb or the Oracle env config is missing, this prints what to
# provide and runs the benchmark in DRY-RUN (reference solver, axes 1-4 + 6;
# axis-5 live sub-check skipped). It always exits 0 — a missing stack is a
# degrade, not a failure.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED="$DIR/seed.sql"

USER_VAL="${AI_ANALYST_ORACLE_USER:-${ORACLE_USER:-}}"
PWD_VAL="${AI_ANALYST_ORACLE_PWD:-${ORACLE_PASSWORD:-}}"
DSN_VAL="${AI_ANALYST_ORACLE_DSN:-${ORACLE_DSN:-}}"

have_oracledb() { python3 -c "import oracledb" >/dev/null 2>&1; }

if [[ -z "$USER_VAL" || -z "$PWD_VAL" || -z "$DSN_VAL" ]]; then
  echo "[run-bench] Oracle env not set — DRY-RUN only."
  echo "[run-bench] To enable live execution, export:"
  echo "    AI_ANALYST_ORACLE_USER=<user>   (or ORACLE_USER)"
  echo "    AI_ANALYST_ORACLE_PWD=<password> (or ORACLE_PASSWORD)"
  echo "    AI_ANALYST_ORACLE_DSN=<host:port/service> (or ORACLE_DSN)"
  echo
  PYTHONPATH="$DIR" python3 "$DIR/runner.py"
  exit 0
fi

if ! have_oracledb; then
  echo "[run-bench] python-oracledb not installed (pip install oracledb) — DRY-RUN only."
  echo
  PYTHONPATH="$DIR" python3 "$DIR/runner.py"
  exit 0
fi

# --- Load the fixture seed into Oracle via python-oracledb (thin mode). ---
echo "[run-bench] regenerating seed.sql from fixture.py ..."
python3 "$DIR/fixture.py"

echo "[run-bench] loading seed.sql into Oracle ..."
SEED="$SEED" python3 - <<'PY'
import os
import oracledb

user = os.getenv("AI_ANALYST_ORACLE_USER") or os.getenv("ORACLE_USER")
pwd = os.getenv("AI_ANALYST_ORACLE_PWD") or os.getenv("ORACLE_PASSWORD")
dsn = os.getenv("AI_ANALYST_ORACLE_DSN") or os.getenv("ORACLE_DSN")

sql_text = open(os.environ["SEED"], encoding="utf-8").read()
# Split on ';' terminators; drop comments and empties. COMMIT issued explicitly.
stmts = []
for raw in sql_text.split(";"):
    s = "\n".join(ln for ln in raw.splitlines() if not ln.strip().startswith("--")).strip()
    if s and s.upper() != "COMMIT":
        stmts.append(s)

with oracledb.connect(user=user, password=pwd, dsn=dsn) as conn:
    cur = conn.cursor()
    for s in stmts:
        cur.execute(s)
    conn.commit()
    cur.close()
print(f"[run-bench] loaded {len(stmts)} statements, committed.")
PY

echo "[run-bench] running benchmark (live) ..."
PYTHONPATH="$DIR" python3 "$DIR/runner.py"
