#!/usr/bin/env bash
# Behavior test for the GLOBAL ~/.claude/hooks/system-guard.sh PreToolUse guard.
# Cases are fed via crafted PreToolUse JSON on stdin (NOT via the real tool call),
# so trigger substrings never touch the operator's own command line.
# Guard is DENY-only (devlog #56): catastrophic/irreversible -> deny, sudo -> log,
# everything else passes through (safe). No ASK tier. Asserts the tier per case.
# Regression-guards the false-positive where a hyphenated word ("system-guard")
# matched the loose recursive-flag regex (-[a-z]*r) anywhere in the command.
# Devlog #55/#56.
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
check "deny: $R -rf ~/ (slash)"   deny "$(verdict "$R -rf ~/")"
check "deny: $R -rf ~/* (glob)"   deny "$(verdict "$R -rf ~/*")"
check "deny: $R -rf \$HOME"       deny "$(verdict "$R -rf \$HOME")"
check "deny: $R -rf \$HOME/"      deny "$(verdict "$R -rf \$HOME/")"
check "deny: $R -rf \$HOME/*"     deny "$(verdict "$R -rf \$HOME/*")"
# Absolute home-root path (was a real gap: literal /home/<user> passed).
check "deny: $R -rf <abs home>"   deny "$(verdict "$R -rf $HOME")"
check "deny: $R -rf <abs home>/"  deny "$(verdict "$R -rf $HOME/")"
check "deny: $R -rf quoted home"  deny "$(verdict "$R -rf \"\$HOME\"")"
check "deny: $R -fr /"            deny "$(verdict "$R -fr /")"
check "deny: $R  -rf  / (2 spc)"  deny "$(verdict "$R  -rf  /")"
# Capital -R is a valid GNU rm recursive flag (was a pre-existing HIGH gap).
check "deny: $R -Rf /"            deny "$(verdict "$R -Rf /")"
check "deny: $R -R /"             deny "$(verdict "$R -R /")"
check "deny: $R -fR ~"            deny "$(verdict "$R -fR ~")"

# --- Home SUBdirectories pass (scope is root/home ROOT; the ~-only subdir deny
# --- gave zero protection while the absolute form passed — narrowed 2026-07-15).
check "passthrough: $R -rf ~/subdir"        safe "$(verdict "$R -rf ~/old-project/node_modules")"
check "passthrough: $R -rf \$HOME/.cache"   safe "$(verdict "$R -rf \$HOME/.cache/pip")"
check "passthrough: $R -rf <abs>/subdir"    safe "$(verdict "$R -rf $HOME/proj/node_modules")"
# Quoted recursive flag (regression introduced by the word-boundary fix).
check "deny: $R '-rf' /"          deny "$(verdict "$R '-rf' /")"
check "deny: $R \"-rf\" ~"        deny "$(verdict "$R \"-rf\" ~")"
check "deny: mkfs.ext4 /dev/sdb"  deny "$(verdict "mkfs.ext4 /dev/sdb")"
check "deny: dd of=/dev/sda"      deny "$(verdict "dd if=/dev/zero of=/dev/sda")"
check "deny: fork bomb"           deny "$(verdict ':(){ :|:& };:')"
check "deny: no-preserve-root"    deny "$(verdict "$R --no-preserve-root -rf /")"

# --- Former ASK tier: now passes through (DENY-only guard) ------------------
check "passthrough: plain $R file"       safe "$(verdict "$R /tmp/foo.txt")"
check "passthrough: $R -rf non-root dir" safe "$(verdict "$R -rf /tmp/mydir")"
check "passthrough: systemctl stop"      safe "$(verdict "sudo systemctl stop nginx")"
check "passthrough: docker rm"           safe "$(verdict "docker rm somebox")"
check "passthrough: reboot"              safe "$(verdict "reboot")"

# --- Non-ASCII. The whole suite was ASCII, so a byte/char indexing mismatch in
# --- the tokenizer truncated the command tail and silently blinded the guard on
# --- 31.9% of this operator's real commands (he writes Russian) — 78 cases green
# --- throughout. Any tokenizer test set that is ASCII-only is not a test set.
check "deny: cyrillic echo, then $R -rf /"  deny "$(verdict "echo \"привет\" && $R -rf /")"
check "deny: emoji echo, then $R -rf ~"     deny "$(verdict "echo \"готово ✅\" && $R -rf ~")"
check "deny: cyrillic on its own line"      deny "$(verdict "echo \"=== чистка кэша ===\"
$R -rf /*")"
check "passthrough: cyrillic + safe $R"     safe "$(verdict "echo \"чистим сборку\" && $R -rf /tmp/build")"
check "passthrough: cyrillic heredoc"       safe "$(verdict "cat > /tmp/n <<EOF
никогда не запускай $R -rf /
EOF")"

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
check "regression: hyphen-word + non-recursive rm -> safe (not deny)" safe "$(verdict "$fp")"
# Same shape, no destructive token at all -> safe.
fp2="cp ~/.claude/hooks/system-guard.sh /tmp/bak # restore-later"
check "regression: hyphen-word, no rm -> safe" safe "$(verdict "$fp2")"

# --- REGRESSION: the guard must judge rm's OWN arguments, not the raw line ----
# Field-reported false positives (4 in one session, all wrong): a root/home token
# living in a NEIGHBOURING segment or inside a quoted string was read as if it
# were rm's target. rm of /tmp is not catastrophic no matter what follows it.
check "fp: rm /tmp + '~/' in later echo"  safe "$(verdict "$R -rf /tmp/x && echo \"backup in ~/\"")"
check "fp: rm /tmp + ls ~/ after"         safe "$(verdict "$R -rf /tmp/scratch && ls ~/")"
check "fp: rm /tmp + cd / before"         safe "$(verdict "cd / && $R -rf /tmp/x")"
check "fp: root token in quoted arg"      safe "$(verdict "$R -rf /tmp/x && echo 'done, / untouched'")"
# A mere MENTION of the catastrophic form is not an invocation of it (this is the
# self-diagnostic probe that got blocked in the field).
check "fp: quoted mention via echo"       safe "$(verdict "echo \"$R -rf /\" > /tmp/note.txt")"
# rm's operand list must END at the segment boundary: a recursive flag and a root
# token in the NEXT segment belong to that command, not to rm. (A mutant that
# dropped the in_rm reset denied the first of these and passed every other case.)
check "fp: rm /tmp, then cp -r to ~"      safe "$(verdict "$R -rf /tmp/build && cp -r dist ~")"
check "fp: rm /tmp, then tar -C ~/"       safe "$(verdict "$R -rf /tmp/x; tar -xzf a.tgz -C ~/")"
check "fp: quoted mention via grep"       safe "$(verdict "grep -rn '$R -rf ~' ~/.claude/hooks/")"
# Recursive flag belonging to a DIFFERENT command in the same line (documented
# residual of the raw-string matcher — the token-level check retires it).
check "fp: -r flag owned by grep, not rm" safe "$(verdict "grep -r foo / && $R /tmp/out")"
check "fp: -R flag owned by cp, not rm"   safe "$(verdict "cp -R ~/ /tmp/bak && $R /tmp/bak/note")"

# --- The recursive half of the conjunction (a mutant that dropped the flag
# --- requirement and denied on the target alone passed all other cases).
# --- Non-recursive rm cannot remove a directory (EISDIR), so it is not gated.
check "passthrough: $R / (no -r)"         safe "$(verdict "$R /")"
check "passthrough: $R -f ~ (no -r)"      safe "$(verdict "$R -f ~")"
check "passthrough: $R --force \$HOME"    safe "$(verdict "$R --force \$HOME")"

# --- The DENY tier must survive the same token-level scrutiny ----------------
check "deny: rm root in 2nd segment"      deny "$(verdict "cd /tmp && $R -rf /")"
check "deny: rm home after a safe rm"     deny "$(verdict "$R -rf /tmp/x; $R -rf ~")"
check "deny: sudo rm -rf /"               deny "$(verdict "sudo $R -rf /")"
check "deny: env-assignment prefix"       deny "$(verdict "FOO=bar $R -rf /")"
check "deny: absolute /bin/rm -rf /"      deny "$(verdict "/bin/$R -rf /")"
check "deny: long flag --recursive ~"     deny "$(verdict "$R --recursive --force ~")"
check "deny: flags after the target"      deny "$(verdict "$R / -rf")"
check "deny: end-of-options -- then /"    deny "$(verdict "$R -rf -- /")"

# --- rm is not always the first word of its segment. An "only look at the
# --- command position" rule silently un-gated every shape below (fresh-context
# --- refuter, 27 old-DENY -> new-ALLOW regressions, while 57 cases stayed green).
# --- Shell keywords: how rm is written in any real script.
check "deny: brace group"                 deny "$(verdict "{ $R -rf ~ ; }")"
check "deny: if/then"                     deny "$(verdict "if [ -d /x ]; then $R -rf \$HOME ; fi")"
check "deny: for/do"                      deny "$(verdict "for d in a b; do $R -rf ~ ; done")"
check "deny: while/do"                    deny "$(verdict "while read f; do $R -rf /home/nikita ; done")"
# Wrappers: an allowlist of these is unbounded, so the rule must not need one.
check "deny: nice wrapper"                deny "$(verdict "nice $R -rf /*")"
check "deny: timeout wrapper"             deny "$(verdict "timeout 5 $R -rf \$HOME")"
check "deny: setsid wrapper"              deny "$(verdict "setsid $R -rf /*")"
check "deny: sudo WITH options"           deny "$(verdict "sudo -u root $R -rf /*")"
check "deny: xargs with literal target"   deny "$(verdict "xargs $R -rf /*")"
# sh -c: the body is CODE, not data — unlike every other quoted operand.
check "deny: bash -c \"…\""               deny "$(verdict "bash -c \"$R -rf /*\"")"
check "deny: sh -c '…'"                   deny "$(verdict "sh -c '$R -rf \$HOME'")"

# --- …and dropping the command-position rule must not re-break the FP set.
# --- A quoted operand stays DATA: only `sh -c` promotes it back to code.
check "fp: quoted body of a non-shell"    safe "$(verdict "echo -c \"$R -rf /\"")"
check "fp: rm as a search pattern"        safe "$(verdict "grep -rn $R /tmp/logs")"
check "fp: --rm flag is not rm"           safe "$(verdict "docker run --rm -v ~/:/data alpine true")"

# --- Heredoc bodies are DATA, like quoted text. Writing a file that merely
# --- mentions a dangerous command is ordinary work — THIS suite does it, and the
# --- guard denied the very command that authored these cases (5th false alarm of
# --- the reported class, reproduced live).
hd="cat > /tmp/note.txt <<EOF
never run $R -rf / or $R -rf ~
EOF"
check "fp: heredoc body mentions rm"      safe "$(verdict "$hd")"
hd_q="cat > /tmp/x.sh <<'SH'
$R -rf \$HOME
SH"
check "fp: quoted-delimiter heredoc"      safe "$(verdict "$hd_q")"
hd_dash="cat > /tmp/x <<-END
	$R -rf /*
	END"
check "fp: <<- heredoc, tab-indented end" safe "$(verdict "$hd_dash")"
# The body skip must STOP at the delimiter — a real rm after it is still gated.
hd_then="cat > /tmp/note.txt <<EOF
harmless text
EOF
$R -rf ~"
check "deny: real rm AFTER heredoc ends"  deny "$(verdict "$hd_then")"
# A here-STRING (<<<) is not a heredoc; its operand is a quoted token = data.
check "fp: here-string mentions rm"       safe "$(verdict "cat <<< \"$R -rf /\"")"
# …but misreading <<< as a heredoc made the "body" skip swallow the REST of the
# command, silently un-gating everything after it.
check "deny: rm on a line after <<<"      deny "$(verdict "grep x <<< foo
$R -rf /")"
check "deny: rm after arithmetic shift"   deny "$(verdict "echo \$((1 << 3))
$R -rf ~")"
# An unterminated heredoc must not eat the rest of the command either: if the
# delimiter never arrives, the body is code again (errs to DENY, not to blind).
check "deny: unterminated heredoc"        deny "$(verdict "cat <<NOPE
$R -rf /")"

# --- sh -c flag clustering: -lc / -xc are the same thing as -c.
check "deny: bash -lc"                    deny "$(verdict "bash -lc \"$R -rf /\"")"
check "deny: sh -xc"                      deny "$(verdict "sh -xc \"$R -rf /\"")"
check "deny: bash -c \$'…' (ANSI-C)"      deny "$(verdict "bash -c \$'$R -rf /'")"
# -c need not be LAST in the cluster, and options may follow it. Both shapes were
# denied by the pre-rewrite matcher, so allowing them would be a regression.
check "deny: bash -cx (c not last)"       deny "$(verdict "bash -cx '$R -rf /'")"
check "deny: bash -c -- 'code'"           deny "$(verdict "bash -c -- '$R -rf /'")"

# --- A redirect does not end a command: its operands continue after it.
# --- Treating > as a separator flushed rm's args before the target arrived.
check "deny: redirect before the target" deny "$(verdict "$R -rf 2>/dev/null /")"
check "deny: rm root, output to log"      deny "$(verdict "$R -rf / > /tmp/log 2>&1")"

# --- Backticks are a shell operator; gluing them to the token hid the rm.
check "deny: backtick substitution"       deny "$(verdict "echo \`$R -rf ~\`")"

# --- Trailing-slash spellings are the SAME directory (verified: ~// -ef \$HOME).
check "deny: $R -rf ~//"                  deny "$(verdict "$R -rf ~//")"
check "deny: $R -rf \$HOME//"             deny "$(verdict "$R -rf \$HOME//")"
check "deny: $R -rf <abs home>//"         deny "$(verdict "$R -rf $HOME//")"
check "deny: $R -rf //"                   deny "$(verdict "$R -rf //")"
check "passthrough: subdir keeps slash"   safe "$(verdict "$R -rf ~/build//")"

# --- Quote pairing is naive: nested quotes inside "$( … '…' )" mispair, and a
# --- mispaired scan can swallow the command's tail — going BLIND, the one
# --- direction a safety floor must never fail in. A quote that runs to EOF
# --- proves the parse is broken, so fall back to the old raw matcher (imprecise,
# --- but errs to DENY). Real shape: 6/14625 commands in the 30d corpus.
check "deny: nested quotes in \$( ), then $R" deny "$(verdict "curl -o x \"\$(curl -s 'u' | grep -o '\"href\":\"[^\"]*\"')\" && $R -rf /")"
check "deny: unbalanced quote hides $R"       deny "$(verdict "echo 'oops && $R -rf ~")"
# The fallback must NOT fire on ordinary balanced commands (it would resurrect
# every false positive this rewrite removed).
check "fp: balanced nested quotes stay safe"  safe "$(verdict "echo \"\$(echo 'hi')\" && $R -rf /tmp/x")"
check "fp: quoted mention still safe"         safe "$(verdict "echo \"$R -rf /\"")"

# --- The \x01 segment sentinel is forgeable: a literal \x01 in the command
# --- splits the rm invocation and hides its target. Claude Code's Bash tool
# --- rejects control characters before the hook ever runs, but the guard must
# --- not lean on another layer's validation — the sentinel is our own choice.
S1=$'\x01'
check "deny: forged SEP before target"    deny "$(verdict "$R -rf $S1 /")"
check "deny: forged SEP glued to target"  deny "$(verdict "$R -rf $S1/")"
check "deny: forged SEP after rm"         deny "$(verdict "$R $S1 -rf /")"

# --- ${HOME} is the same target as $HOME (the rule listed only the bare form).
check "deny: $R -rf \${HOME}"             deny "$(verdict "$R -rf \${HOME}")"
check "deny: $R -rf \${HOME}/*"           deny "$(verdict "$R -rf \${HOME}/*")"
check "passthrough: \${HOME} subdir"      safe "$(verdict "$R -rf \${HOME}/.cache/pip")"

# --- Edit/Write: DENY-only guard no longer gates protected paths ------------
# (NTFS/Windows-mount writes are still DENY, but require a live mount to test.)
check "edit passthrough: /etc/hosts"    safe "$(verdict_edit /etc/hosts)"
check "edit passthrough: ~/.ssh/config" safe "$(verdict_edit "$HOME/.ssh/config")"
check "edit safe: project file"         safe "$(verdict_edit /home/nikita/x/main.py)"

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
