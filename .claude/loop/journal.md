---
# Loop journal — append-only event log
#
# Format (one per line):
# YYYY-MM-DD HH:MM:SSZ iter-NNNN <STATUS> <H-XXX> <description>
#
# STATUS ∈ {ACCEPTED, REJECTED, PROPOSAL, HOLDOUT, NOOP, ERROR}
---

# Journal

2026-05-11 00:18:00Z iter-0001 ERROR H-001 T03 fixture missing (.claude/benchmark/fixtures/external/full-stack-fastapi-template) — corpus.yml references commit 13652b51 but external/ dir not bootstrapped; T01 ran successfully ($0.21, 24s, pytest pass) revealing secondary issue: fitness.py expects top-level `tokens`/`turns`/`files_touched`/`success` fields but headless-runner emits `claude.tokens.*`/`claude.num_turns`/`verification.files_changed`/`verification.pytest.status` — schema mismatch would force success_rate=0 → false REJECT for any hypothesis regardless of merit.
