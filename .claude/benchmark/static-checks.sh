#!/usr/bin/env bash
# Tier 0 static checks for harness — per docs/HARNESS-BENCHMARK.md
# Runs from harness root. Exits 0 if all pass, 1 on any failure.
# Manual checks (claude --print, claude agents) — not automated; run separately.

set -uo pipefail

cd "$(dirname "$0")/../.."

FAIL=0
TOTAL=0
PASS=0

check() {
    local name="$1"
    local actual="$2"
    local status="$3"  # pass / fail
    TOTAL=$((TOTAL + 1))
    if [[ "$status" == "pass" ]]; then
        printf "  \033[32m✓\033[0m %-55s %s\n" "$name" "$actual"
        PASS=$((PASS + 1))
    else
        printf "  \033[31m✗\033[0m %-55s %s\n" "$name" "$actual"
        FAIL=1
    fi
}

echo "=== Harness Tier 0 static checks ==="
echo

# Check 1: CLAUDE.md size budget ≤ 200 строк (ADR-012, anti-pattern «не лить мегарайлзы»)
LINES=$(wc -l < .claude/CLAUDE.md)
if [[ $LINES -le 200 ]]; then
    check "CLAUDE.md ≤ 200 строк" "$LINES" pass
else
    check "CLAUDE.md ≤ 200 строк" "$LINES" fail
fi

# Check 2: Each SKILL.md size budget ≤ 500 строк (skill-creator anatomy)
for skill in .claude/skills/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    lines=$(wc -l < "$skill")
    name="$(basename "$(dirname "$skill")")"
    if [[ $lines -le 500 ]]; then
        check "SKILL.md $name ≤ 500" "$lines" pass
    else
        check "SKILL.md $name ≤ 500" "$lines" fail
    fi
done

# Check 3: ADR-018+ size budget ≤ 30 строк (ADR-018 tight format)
# Extracts each ADR-018+ section from header to next ## or --- separator.
for adr_num in 018 019 020 021 022 023 024 025; do
    if grep -q "^## ADR-$adr_num " docs/HARNESS-DECISIONS.md; then
        lines=$(awk "/^## ADR-$adr_num /{flag=1; next} flag && /^## ADR-/{exit} flag && /^---$/{exit} flag" docs/HARNESS-DECISIONS.md | wc -l)
        # +1 for the header line itself
        lines=$((lines + 1))
        if [[ $lines -le 30 ]]; then
            check "ADR-$adr_num ≤ 30 строк (tight format)" "$lines" pass
        else
            check "ADR-$adr_num ≤ 30 строк (tight format)" "$lines" fail
        fi
    fi
done

# Check 4: Devlog index integrity (ADR-004)
if python3 .claude/devlog/rebuild-index.py >/dev/null 2>&1; then
    entries=$(python3 -c "import json; print(len(json.load(open('.claude/devlog/index.json'))['entries']))" 2>/dev/null || echo "?")
    check "Devlog index integrity" "$entries entries, valid" pass
else
    check "Devlog index integrity" "rebuild-index.py exit != 0" fail
fi

# Check 5: Skill frontmatter present (name + description required per Claude Code spec)
for skill in .claude/skills/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    name="$(basename "$(dirname "$skill")")"
    if head -10 "$skill" | grep -q "^name:" && head -10 "$skill" | grep -q "^description:"; then
        check "SKILL frontmatter ($name)" "name + description present" pass
    else
        check "SKILL frontmatter ($name)" "missing name or description" fail
    fi
done

# Check 6: No retired components reintroduced (ADR-007/010/011/016 retire decisions)
RETIRED_OK=1
for retired in onboard review debug-loop refactor create-skill spawn-agent meta-orchestrator; do
    if [[ -d ".claude/skills/$retired" ]]; then
        check "Retired skill not reintroduced" ".claude/skills/$retired exists!" fail
        RETIRED_OK=0
    fi
done
for retired in code-reviewer onboarding-agent debug-loop; do
    if [[ -f ".claude/agents/$retired.md" ]]; then
        check "Retired agent not reintroduced" ".claude/agents/$retired.md exists!" fail
        RETIRED_OK=0
    fi
done
if [[ $RETIRED_OK -eq 1 ]]; then
    check "Retired components guard" "all clean (8 skills + 3 agents checked)" pass
fi

# Check 7: Compact index synchronized with ADR headers (ADR-018)
ADR_HEADERS=$(grep -c "^## ADR-" docs/HARNESS-DECISIONS.md)
INDEX_ROWS=$(grep -cE '^\| 0?[0-9]+ ' docs/HARNESS-DECISIONS.md)
if [[ $ADR_HEADERS -eq $INDEX_ROWS ]]; then
    check "Compact index sync с ADR headers" "$ADR_HEADERS = $INDEX_ROWS" pass
else
    check "Compact index sync с ADR headers" "$ADR_HEADERS ADRs vs $INDEX_ROWS index rows" fail
fi

# Check 8: Hooks exist + executable (basic smoke; full input-test = manual)
HOOKS_OK=1
for hook in .claude/hooks/*.sh; do
    [[ -f "$hook" ]] || continue
    name="$(basename "$hook")"
    if [[ -x "$hook" ]]; then
        : # OK
    else
        check "Hook executable ($name)" "not chmod +x" fail
        HOOKS_OK=0
    fi
done
HOOK_COUNT=$(ls .claude/hooks/*.sh 2>/dev/null | wc -l)
if [[ $HOOKS_OK -eq 1 ]]; then
    check "Hooks executable + present" "$HOOK_COUNT hooks, all chmod +x" pass
fi

# Check 9: Rule files have content (no accidentally empty files)
for rule in .claude/rules/*.md; do
    [[ -f "$rule" ]] || continue
    name="$(basename "$rule")"
    lines=$(wc -l < "$rule")
    if [[ $lines -ge 5 ]]; then
        check "Rule file non-empty ($name)" "$lines строк" pass
    else
        check "Rule file non-empty ($name)" "$lines строк (suspicious)" fail
    fi
done

echo
echo "Manual checks (run separately):"
echo "  - claude --print : skill discovery runtime"
echo "  - claude agents  : agent inventory check"
echo "  - hook stdin smoke tests (см. HARNESS-BENCHMARK.md Tier 0 #9)"
echo

if [[ $FAIL -eq 0 ]]; then
    echo "=== ALL AUTOMATED CHECKS PASSED ($PASS/$TOTAL) ==="
    exit 0
else
    echo "=== FAILURES PRESENT ($PASS/$TOTAL passed) ==="
    exit 1
fi
