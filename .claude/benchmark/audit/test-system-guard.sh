#!/usr/bin/env bash
# Behavior test for the GLOBAL ~/.claude/hooks/system-guard.sh PreToolUse guard.
# Cases are fed via crafted PreToolUse JSON on stdin (NOT via the real tool call),
# so trigger substrings never touch the operator's own command line.
# Asserts the permissionDecision tier (deny / ask / safe) per Nikita's contract.
# Regression-guards the false-positive where a hyphenated word ("system-guard")
# matched the loose recursive-flag regex (-[a-z]*r) anywhere in the command.
# Devlog #55.
set -uo pipefail

GUARD="${GUARD:-${HOME}/.claude/hooks/system-guard.sh}"
pass=0; fail=0

# verdict <command> -> prints deny|ask|safe
verdict() {
    local out
    out=$(jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/home/nikita/x"}' \
          | bash "$GUARD" 2>/dev/null)
    if [ -z "$out" ]; then echo "safe"; return; fi
    printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "safe"' 2>/dev/null || echo "PARSE_ERR"
}

# verdict_edit <file_path> -> deny|ask|safe
verdict_edit() {
    local out
    out=$(jq -n --arg f "$1" '{tool_name:"Edit",tool_input:{file_path:$f}}' | bash "$GUARD" 2>/dev/null)
    [ -z "$out" ] && { echo "safe"; return; }
    printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "safe"'
}

check() { # desc expected actual
    if [ "$2" = "$3" ]; then echo "PASS: $1 [$3]"; pass=$((pass+1));
    else echo "FAIL: $1 — expected $2, got $3"; fail=$((fail+1)); fi
}

R='r''m'   # build the destructive token without writing it literally on any line

# --- DENY tier (catastrophic) must stay DENY --------------------------------
check "deny: $R -rf /"            deny "$(verdict "$R -rf /")"
check "deny: $R -rf /*"           deny "$(verdict "$R -rf /*")"
check "deny: $R -rf ~"            deny "$(verdict "$R -rf ~")"
check "deny: $R -rf \$HOME"       deny "$(verdict "$R -rf \$HOME")"
check "deny: $R -rf ~/Downloads"  deny "$(verdict "$R -rf ~/Downloads")"
check "deny: $R -fr /"            deny "$(verdict "$R -fr /")"
check "deny: $R  -rf  / (2 spc)"  deny "$(verdict "$R  -rf  /")"
# Capital -R is a valid GNU rm recursive flag (was a pre-existing HIGH gap).
check "deny: $R -Rf /"            deny "$(verdict "$R -Rf /")"
check "deny: $R -R /"             deny "$(verdict "$R -R /")"
check "deny: $R -fR ~"            deny "$(verdict "$R -fR ~")"
# Quoted recursive flag (regression introduced by the word-boundary fix).
check "deny: $R '-rf' /"          deny "$(verdict "$R '-rf' /")"
check "deny: $R \"-rf\" ~"        deny "$(verdict "$R \"-rf\" ~")"
check "deny: mkfs.ext4 /dev/sdb"  deny "$(verdict "mkfs.ext4 /dev/sdb")"
check "deny: dd of=/dev/sda"      deny "$(verdict "dd if=/dev/zero of=/dev/sda")"
check "deny: fork bomb"           deny "$(verdict ':(){ :|:& };:')"
check "deny: no-preserve-root"    deny "$(verdict "$R --no-preserve-root -rf /")"

# --- ASK tier (risky/reversible) --------------------------------------------
check "ask: plain $R file"        ask  "$(verdict "$R /tmp/foo.txt")"
check "ask: $R -rf non-root dir"  ask  "$(verdict "$R -rf /tmp/mydir")"
check "ask: systemctl stop"       ask  "$(verdict "sudo systemctl stop nginx")"
check "ask: docker rm"            ask  "$(verdict "docker rm somebox")"
check "ask: reboot"               ask  "$(verdict "reboot")"

# --- SAFE tier --------------------------------------------------------------
check "safe: ls -la"              safe "$(verdict "ls -la")"
check "safe: git status"          safe "$(verdict "git status")"
# grep -r over ~/ with a hyphenated word but NO destructive token -> safe
check "safe: grep -r hyphen-word" safe "$(verdict "grep -r system-guard ~/.claude/")"

# --- REGRESSION: false-positive (hyphenated word matched loose recursive) ---
# Command mentions a hyphenated word containing ...r ("system-guard"), has a
# non-recursive destructive token on /tmp, and a ~/ path. It must be ASK
# (a destructive token is present) — NOT DENY (it is not catastrophic).
fp="cp ~/.claude/hooks/system-guard.sh /tmp/bak && $R /tmp/bak"
check "regression: hyphen-word + non-recursive rm -> ask (not deny)" ask "$(verdict "$fp")"
# Same shape, no destructive token at all -> safe.
fp2="cp ~/.claude/hooks/system-guard.sh /tmp/bak # restore-later"
check "regression: hyphen-word, no rm -> safe" safe "$(verdict "$fp2")"

# --- Edit/Write protected paths ---------------------------------------------
check "edit ask: /etc/hosts"      ask  "$(verdict_edit /etc/hosts)"
check "edit ask: ~/.ssh/config"   ask  "$(verdict_edit "$HOME/.ssh/config")"
check "edit safe: project file"   safe "$(verdict_edit /home/nikita/x/main.py)"

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
