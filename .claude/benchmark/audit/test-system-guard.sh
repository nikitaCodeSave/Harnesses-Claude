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

# --- Cross-vendor refuter pass (Codex via codex_peer MCP, 2026-07-31) --------
# 16 bypasses, every one reproduced ALLOW against the then-current guard while a
# real shell would destroy the target. Grouped by the parser assumption it breaks.
SQ=\'

# (a) A redirect or a command substitution is not a command boundary: rm's
#     operands continue across both. Emitting a segment break there flushed rm's
#     args before the target arrived.
check "deny: stdin redirect before target"  deny "$(verdict "$R -rf </dev/null ~")"
check "deny: empty substitution before tgt" deny "$(verdict "$R -rf \$(true) ~")"
# (b) A command substitution is CODE even inside double quotes / an unquoted
#     heredoc body — the shell runs it while producing the argument.
check "deny: \$( ) inside double quotes"    deny "$(verdict "echo \"\$($R -rf ~)\"")"
hd_sub="cat <<EOF
\$($R -rf ~)
EOF"
check "deny: \$( ) in unquoted heredoc"     deny "$(verdict "$hd_sub")"
# Nested quotes inside the substitution used to mispair EVENLY, so the broken-
# parse fallback never fired and the rm went unseen.
q_desync=": \"\$(printf ${SQ}\"x\"${SQ}; $R -rf ~)\""
check "deny: balanced quote desync in \$( )" deny "$(verdict "$q_desync")"
# (c) The command name and the target may arrive through a variable assigned in
#     the same line — the shell expands them, so the guard must too.
check "deny: command name via variable"     deny "$(verdict "x=$R; \$x -rf ~")"
check "deny: target via variable"           deny "$(verdict "p=\$HOME; $R -rf \"\$p\"")"
# (d) Pathname expansion in the executable name.
check "deny: glob in executable name"       deny "$(verdict "/bin/${R:0:1}[${R:1:1}] -rf ~")"
# (e) GNU accepts any unambiguous long-option abbreviation.
check "deny: --recursiv (GNU abbrev)"       deny "$(verdict "$R --recursiv ~")"
# (f) A shell with no -c executes its stdin.
check "deny: shell reads code from <<<"     deny "$(verdict "bash <<< ${SQ}$R -rf ~${SQ}")"
hd_shell="bash <<EOF
$R -rf ~
EOF"
check "deny: shell reads code from heredoc" deny "$(verdict "$hd_shell")"
# (g) ~USER is the same directory as ~ when USER is this user — getent turns the
#     old "assumption, not a fact" residual into a fact.
check "deny: tilde-USER form"               deny "$(verdict "$R -rf ~$(id -un)")"
# (h) Quote concatenation splits any raw-string match; the shell sees one word.
check "deny: mkfs via quote concatenation"  deny "$(verdict "mk${SQ}${SQ}fs.ext4 /dev/sdb")"
check "deny: dd via quote concatenation"    deny "$(verdict "d${SQ}${SQ}d if=/dev/zero of=/dev/sda")"
check "deny: dd with quoted device"         deny "$(verdict "dd if=/dev/zero of=\"/dev/sda\"")"
check "deny: redirect onto quoted device"   deny "$(verdict "printf x > /dev/\"sda\"")"
# (i) A fork bomb is a shape, not the single name `:`.
check "deny: fork bomb, renamed function"   deny "$(verdict 'f(){ f|f& };f')"

# --- …and the same pass reported false denials. Text that merely MENTIONS a
# --- catastrophic command is data: a comment, or a fully quoted operand.
check "fp: trailing comment mentions rm"    safe "$(verdict "echo done # $R -rf /")"
check "fp: mkfs as a quoted search pattern" safe "$(verdict "rg ${SQ}mkfs.ext4 /dev/sdb${SQ} README.md")"
check "fp: mkfs inside double quotes"       safe "$(verdict "echo \"mkfs.ext4 /dev/sdb\"")"
# Quoting a WORD does not make it data — the shell just removes the quotes and
# runs it. Only a quoted token holding whitespace is a string being passed
# around. Cost of that line: `printf '%s\n' '--no-preserve-root'` still denies.
check "residual: single quoted flag denies" deny "$(verdict "printf ${SQ}%s\\n${SQ} ${SQ}--no-preserve-root${SQ}")"
# The residual stays deliberate: a BARE unquoted rm word that belongs to another
# command still denies (trust quoting, not position — see is_rm_root).
check "residual: bare rm word still denies" deny "$(verdict "echo $R -rf /")"

# --- Regressions the fixes above must not introduce -------------------------
# A redirect operand is the redirect's, not rm's.
check "fp: root path as redirect operand"   safe "$(verdict "$R -rf /tmp/x < /")"
check "fp: dd to a regular file"            safe "$(verdict "dd if=/dev/zero of=/tmp/img bs=1M count=1")"
# Variable expansion must resolve to the real value, not fire on any variable.
check "fp: variable holds a harmless cmd"   safe "$(verdict "x=ls; \$x -rf ~")"
check "fp: variable holds a harmless path"  safe "$(verdict "p=/tmp; $R -rf \"\$p\"")"
# A QUOTED heredoc delimiter suppresses substitution — the body is data again.
hd_q_sub="cat <<${SQ}EOF${SQ}
\$($R -rf ~)
EOF"
check "fp: \$( ) in quoted heredoc"         safe "$(verdict "$hd_q_sub")"
# ~USER resolves through getent: an unknown user, or a subdirectory, is not root.
check "fp: tilde-USER unknown account"      safe "$(verdict "$R -rf ~nosuchuser99")"
check "fp: tilde-USER subdirectory"         safe "$(verdict "$R -rf ~$(id -un)/build")"
# The long-option abbreviation must stay unambiguous: --preserve-root is not it.
check "fp: --preserve-root is not recursive" safe "$(verdict "$R --preserve-root -f /tmp/x")"

# --- A heredoc inside a command substitution is TEXT. `git commit -m "$(cat
# --- <<'EOF' … EOF)"` is the everyday shape, and prose contains unbalanced
# --- parens and apostrophes: they used to end the substitution early, after
# --- which the leftover message was parsed as code (2 false denials in an
# --- 18k-command corpus of this operator's real work).
msg_body="feat: drop the cache (v1.14.0 / v1.0.0)

Today's fix removes the fork; the old note said $R -rf ~ was fine (it wasn't).
Rollback: restore the file."
git_msg="git commit -q -m \"\$(cat <<${SQ}EOF${SQ}
$msg_body
EOF
)\" && git log --oneline -1"
check "fp: heredoc msg inside \$( )"        safe "$(verdict "$git_msg")"
check "fp: same, after a subdir rm"         safe "$(verdict "$R -rf ~/.cache/x
$git_msg")"
# …and a real invocation after that substitution is still gated.
check "deny: real rm after heredoc msg"     deny "$(verdict "$git_msg && $R -rf ~")"

# --- Second cross-vendor refuter pass (Codex, on the rewrite itself) ---------
# The rewrite was reviewed by the same outside reviewer; these are its findings.
# Two were REGRESSIONS the rewrite introduced (quoting a word is not quoting a
# command), the rest are holes and false alarms it inherited or added.

# (a) A compound redirect is still a redirect: 2>&1 / &> must not sever the
#     command from its operands.
check "deny: 2>&1 before the target"        deny "$(verdict "$R -rf 2>&1 /")"
check "deny: &>/dev/null before the target" deny "$(verdict "$R -rf &>/dev/null /")"
# (b) Quotes around a WORD do not turn it into data — the shell removes them and
#     runs it. Only a quoted token carrying whitespace is a string being passed.
check "deny: quoted dd operand"             deny "$(verdict "dd ${SQ}of=/dev/sda${SQ}")"
check "deny: quoted --no-preserve-root"     deny "$(verdict "chmod -R 000 / ${SQ}--no-preserve-root${SQ}")"
check "deny: quoted mkfs command name"      deny "$(verdict "\"mkfs.ext4\" /dev/sdb")"
# (c) An assignment must reach the code that runs inside $( … ) and sh -c.
check "deny: var command inside \$( )"      deny "$(verdict "SG_CMD=$R; echo \"\$(\$SG_CMD -rf /)\"")"
var_subst='SG_PATH=/; echo "$('"$R"' -rf "$SG_PATH")"'
check "deny: var target inside \$( )"       deny "$(verdict "$var_subst")"
check "deny: var code passed to bash -c"    deny "$(verdict "SG_CODE=${SQ}$R -rf /${SQ}; bash -c \"\$SG_CODE\"")"
# (d) …but NAME=value is an assignment only in a segment's prefix position, and
#     `NAME=v cmd` scopes it to that one command.
check "fp: NAME=value as an argument"       safe "$(verdict "printf \"%s\\n\" SG_X=$R; \$SG_X -rf /")"
check "fp: assignment scoped to one cmd"    safe "$(verdict "SG_Y=$R true; \$SG_Y -rf /")"
# (e) An escaped \$ in a heredoc body is not a substitution.
hd_esc="cat <<EOF
\\\$($R -rf /)
EOF"
check "fp: escaped \$( ) in heredoc"        safe "$(verdict "$hd_esc")"
# (f) A glob is only a glob unquoted; and a quoted heredoc body is data whatever
#     it spells.
check "fp: quoted glob in command name"     safe "$(verdict "\"/bin/${R:0:1}[${R:1:1}]\" -rf /")"
hd_mkfs="cat <<${SQ}EOF${SQ}
mkfs.ext4 /dev/sdb
EOF"
check "fp: mkfs in quoted heredoc body"     safe "$(verdict "$hd_mkfs")"
# (g) The fork-bomb shape must be read as code, not as text that spells it.
fb='f(){ f|f& };f'
check "fp: fork-bomb text via printf"       safe "$(verdict "printf ${SQ}%s\\n${SQ} ${SQ}$fb${SQ}")"
check "fp: fork-bomb text in a comment"     safe "$(verdict "echo ok # $fb")"
check "fp: fork-bomb text as grep pattern"  safe "$(verdict "git grep ${SQ}$fb${SQ} -- README.md")"
# (h) Line continuation is removed by the shell before the word is read.
check "deny: name split by line continuation" deny "$(verdict "${R:0:1}\\
${R:1:1} -rf /")"
# (i) Deeply nested substitutions must not turn the hook into a hang: a guard
#     that never answers gates nothing. 350 levels, 2.8KB — the recursive
#     quadratic scan went cubic and blew the 5s hook timeout.
deep=true; for _ in $(seq 1 350); do deep="echo \$($deep)"; done
t0=$(date +%s%N); verdict "$deep" >/dev/null; t1=$(date +%s%N)
check "perf: 350 nested substitutions < 3s" ok "$( (( (t1-t0)/1000000 < 3000 )) && echo ok || echo "$(( (t1-t0)/1000000 ))ms" )"

# --- Third refuter pass (Codex, on the fixes to the rewrite) ----------------
# One root cause behind most of it: "this operand is CODE" (sh -c, eval, a shell
# reading stdin, a substitution) was implemented in the rm rule only, so every
# other rule went blind the moment the command was spelled through a shell.
FB=':(){ :|:& };:'
check "deny: mkfs via bash -c"              deny "$(verdict "bash -c ${SQ}mkfs.ext4 /dev/sdb${SQ}")"
check "deny: mkfs via eval"                 deny "$(verdict "eval ${SQ}mkfs.ext4 /dev/sdb${SQ}")"
check "deny: mkfs via shell stdin"          deny "$(verdict "bash <<< ${SQ}mkfs.ext4 /dev/sdb${SQ}")"
check "deny: fork bomb via bash -c"         deny "$(verdict "bash -c ${SQ}$FB${SQ}")"
check "deny: fork bomb inside \$( )"        deny "$(verdict "echo \"\$($FB)\"")"
# `#` only starts a comment at the start of a word: x#y is an ordinary argument.
check "deny: fork bomb after x#y"           deny "$(verdict "echo x#y; $FB")"
# An escaped quote inside double quotes does not close them.
check "deny: fork bomb after escaped quote" deny "$(verdict "echo \"x\\\"\" ; $FB")"
# Legacy `>&word` is the same redirect as `&>word`.
check "deny: >& redirect before target"     deny "$(verdict "$R -rf >& /tmp/log /")"
check "deny: >& onto a device"              deny "$(verdict "printf x >& /dev/sda")"

# …and its false alarms: text that merely spells the shape, in quotes or in a
# quoted heredoc body, is data.
check "fp: fork-bomb text in nested quotes" safe "$(verdict "printf \"%s\\n\" \"example: \\\"f(){ f|f& };f\\\"\"")"
hd_fb="cat <<${SQ}EOF${SQ}
f(){ f|f& };f
EOF"
check "fp: fork-bomb text in heredoc"       safe "$(verdict "$hd_fb")"
# A child shell's assignments must not leak back into the parent, and must not
# overwrite the parent's own.
check "fp: assignment stays in the child"   safe "$(verdict "sh -c ${SQ}x=$R${SQ}; \$x -rf /")"
check "deny: child must not shadow parent"  deny "$(verdict "x=$R; sh -c ${SQ}x=ls; echo $R${SQ}; \$x -rf /")"
# A glob runs its FIRST match, not any match that happens to look dangerous.
check "fp: glob whose first match is nm"    safe "$(verdict "/bin/[n${R:1:1}]${R:1:1} -rf /")"

# --- The recursion/scan limits must hold for every rule, not just rm ---------
deep_mkfs="mkfs.ext4 /dev/sdb"; for _ in $(seq 1 350); do deep_mkfs="echo \$($deep_mkfs)"; done
t0=$(date +%s%N); verdict "$deep_mkfs" >/dev/null; t1=$(date +%s%N)
check "perf: 350 nested, device rule < 3s"  ok "$( (( (t1-t0)/1000000 < 3000 )) && echo ok || echo "$(( (t1-t0)/1000000 ))ms" )"
pad50=$(printf 'x%.0s' $(seq 1 50000))
t0=$(date +%s%N); verdict "echo $pad50; $FB" >/dev/null; t1=$(date +%s%N)
check "perf: 50KB + fork bomb < 3s"         ok "$( (( (t1-t0)/1000000 < 3000 )) && echo ok || echo "$(( (t1-t0)/1000000 ))ms" )"

# --- Fourth refuter pass (Codex, on the shared code_frags rewrite) ----------
# The shared list of "operands the shell runs as code" was itself reading raw
# tokens: it saw `bash` and `sh -c` but not the variable or glob that produces
# them, and eval joins ALL its arguments rather than taking the first.
check "deny: shell code held in a variable" deny "$(verdict "SG_CODE=${SQ}mkfs.ext4 /dev/sdb${SQ}; bash -c \"\$SG_CODE\"")"
check "deny: shell name held in a variable" deny "$(verdict "s=bash; \$s -c ${SQ}mkfs.ext4 /dev/sdb${SQ}")"
check "deny: rm via eval"                   deny "$(verdict "eval ${SQ}$R -rf /${SQ}")"
check "deny: eval joins its arguments"      deny "$(verdict "eval ${SQ}:(){${SQ} ${SQ}:|:&${SQ} ${SQ}};:${SQ}")"
# A fork bomb after some other function definition: the matcher must look at
# every definition, not only the first.
check "deny: fork bomb after another func"  deny "$(verdict "g(){ true; }; $FB")"
# …and the pipeline must live INSIDE that function's body: running a finite
# function twice in a pipeline is not a bomb.
check "fp: finite function piped to itself" safe "$(verdict "f(){ true; }; f | f &")"
# Nested child shells: the VARS snapshot has to be a stack, not one global slot.
check "deny: nested child shells"           deny "$(verdict "x=$R ; sh -c ${SQ}x=ls; sh -c \"\\\$z\"${SQ} ; \$x -rf /")"
# An escaped quote inside a substitution does not close it.
esc_sub='echo "$(printf "x\")"; '"$R"' -rf /)"'
check "deny: escaped quote inside \$( )"    deny "$(verdict "$esc_sub")"
esc_sub_fp='echo "$(printf "x\") '"$R"' -rf /")"'
check "fp: escaped quote, only printing"    safe "$(verdict "$esc_sub_fp")"
# \cX in ANSI-C quoting is control-X — here TAB, i.e. an argument separator.
check "deny: \$'…' with \\cI separators"    deny "$(verdict "bash -c \$'${R}\\cI-rf\\cI/'")"

# --- A shared work budget across ALL rules. Per-rule limits were not enough:
# --- one 16KB string re-scanned by three rules at depth still blew the 5s
# --- timeout, and a hook that times out gates nothing.
pad16=$(printf 'x%.0s' $(seq 1 16064))
combo="printf '%s' '$pad16 \$x mkfs'; $FB"
for _ in $(seq 1 7); do combo="echo \$($combo)"; done
t0=$(date +%s%N); verdict "$combo" >/dev/null; t1=$(date +%s%N)
check "perf: 16KB x nesting x 3 rules < 3s" ok "$( (( (t1-t0)/1000000 < 3000 )) && echo ok || echo "$(( (t1-t0)/1000000 ))ms" )"

# --- Fifth refuter pass (Codex) ---------------------------------------------
# eval joins its operands for the rm rule too, code inside a child shell can
# assign its own variables, and a function body does not end at the first `}`.
check "deny: eval joins operands (rm)"      deny "$(verdict "eval ${SQ}$R -rf${SQ} ${SQ}/${SQ}")"
check "deny: assignment inside bash -c"     deny "$(verdict "bash -c ${SQ}x=\"mkfs.ext4 \"; \$x /dev/sdb${SQ}")"
check "deny: assignment inside eval"        deny "$(verdict "eval ${SQ}x=\"mkfs.ext4 \"; \$x /dev/sdb${SQ}")"
check "deny: fork bomb, \${x} in the body"  deny "$(verdict ':(){ echo ${x}; :|:& };:')"
check "deny: fork bomb, nested group"       deny "$(verdict ':(){ { true; }; :|:& };:')"
# `<<` inside $(( … )) is a shift, not a heredoc — at any nesting level.
check "deny: rm after a shift inside \$( )" deny "$(verdict "echo \"\$(echo \$((1 << 2)); $R -rf /)\"")"
# Each substitution is its own subshell: assignments do not cross between them.
check "fp: no var leak between \$( ) \$( )" safe "$(verdict "echo \"\$(x=$R)\" \"\$(\$x -rf /)\"")"
# Defining a function is not running it.
check "fp: fork-bomb shape, never called"   safe "$(verdict 'f(){ f|f& }')"
# \c? is DEL — it stays INSIDE the word, so this is one long command name.
check "fp: \$'…' with \\c? (DEL, not TAB)"  safe "$(verdict "bash -c \$'${R}\\c?-rf\\c?/'")"

# --- Budget and size limits must count BYTES, because the scan does. Measured
# --- in characters they were 4x too generous on this operator's own writing
# --- (Russian, emoji) — the guard ran past the 5s hook timeout and gated nothing.
pademoji=$(printf '😀%.0s' $(seq 1 14000))
combo_u="printf '%s' '$pademoji \$x mkfs'; $FB"
for _ in $(seq 1 7); do combo_u="echo \$($combo_u)"; done
t0=$(date +%s%N); verdict "$combo_u" >/dev/null; t1=$(date +%s%N)
check "perf: 56KB of emoji, 3 rules < 3s"   ok "$( (( (t1-t0)/1000000 < 3000 )) && echo ok || echo "$(( (t1-t0)/1000000 ))ms" )"

# --- Sixth refuter pass (Codex) ---------------------------------------------
# The raw pre-filters undid the very thing the token stream was built for: a
# command name spelled with quote concatenation never reached the tokenizer.
check "deny: rm spelled r''m"               deny "$(verdict "${R:0:1}${SQ}${SQ}${R:1:1} -rf /")"
check "deny: rm spelled r\\m"               deny "$(verdict "${R:0:1}\\${R:1:1} -rf /")"
check "deny: mkfs spelled mk''fs"           deny "$(verdict "mk${SQ}${SQ}fs.ext4 /tmp/image")"
# Nested parameter expansion inside a function body.
check "deny: fork bomb, nested \${x:-\${y}}" deny "$(verdict ':(){ echo ${x:-${y}}; :|:& };:')"
# Nested parens in arithmetic, and a comment, inside a substitution.
check "deny: rm after nested arithmetic"    deny "$(verdict "echo \"\$(echo \$(((1))); $R -rf / )\"")"
check "deny: rm after a comment in \$( )"   deny "$(verdict "echo \"\$(echo ok # )
$R -rf /
)\"")"
# Assignments have a POSITION in the line: a substitution sees the value that
# was current where it stands, not the last one in the line.
check "deny: subst sees the value in place" deny "$(verdict "x=$R; echo \"\$(\$x -rf /)\"; x=ls")"
check "deny: eval assigns in THIS shell"    deny "$(verdict "eval ${SQ}x=$R${SQ}; \$x -rf /")"
check "deny: eval assign, then subst"       deny "$(verdict "eval ${SQ}x=$R${SQ}; echo \"\$(\$x -rf /)\"")"
check "fp: assignment comes after the use"  safe "$(verdict "echo \"\$(\$x -rf /)\"; x=$R")"
check "fp: eval before the assignment"      safe "$(verdict "eval ${SQ}\$x -rf /${SQ}; x=$R")"
# Expansion is not only "the token IS \$NAME": concatenation and word splitting.
check "deny: value splits into words"       deny "$(verdict "x=${SQ}$R -rf /${SQ}; \$x")"
check "deny: flags and target from a var"   deny "$(verdict "x=${SQ}-rf /${SQ}; $R \$x")"
concat_case='p=/; '"$R"' -rf "$p/"'
check "deny: var concatenated with a slash" deny "$(verdict "$concat_case")"
# …but single quotes make \$p a literal, not an expansion.
literal_case='p=/; '"$R"' -rf '"'"'$p'"'"''
check "fp: single-quoted \$p is literal"    safe "$(verdict "$literal_case")"

# --- The budget must cover the variable-table snapshots too: their cost is
# --- variables x fragments, which an 8KB command can drive past the timeout.
many=""; for i in $(seq 1 700); do many+="v$i=$i; "; done
for i in $(seq 1 700); do many+="echo \$(:); "; done
t0=$(date +%s%N); verdict "$many" >/dev/null; t1=$(date +%s%N)
check "perf: 700 vars x 700 frags < 3s"     ok "$( (( (t1-t0)/1000000 < 3000 )) && echo ok || echo "$(( (t1-t0)/1000000 ))ms" )"


# --- Seventh refuter pass (Codex) -------------------------------------------
# Expansion is a MODEL, and it was still missing pieces the shell has: word
# splitting in the device rule, position for the fork-bomb rule, several
# references in one word, ${p:-default} — and, the other way, quoting that
# forbids expansion entirely.
dd_var='x="dd of=/dev/sda"; $x'
check "deny: dd command from a variable"    deny "$(verdict "$dd_var")"
dd_op='o=of=/dev/sda; dd $o'
check "deny: dd operand from a variable"    deny "$(verdict "$dd_op")"
dd_dev='d=/dev/sda; dd of=$d'
check "deny: device path from a variable"   deny "$(verdict "$dd_dev")"
dd_redir='d=/dev/sda; printf x > "$d"'
check "deny: redirect device from a var"    deny "$(verdict "$dd_redir")"
# The fork-bomb rule must read variables where they stand, like the other two.
fb_eval='x=":(){ :|:& };:"; eval "$x"; x=true'
check "deny: fork bomb via eval of a var"   deny "$(verdict "$fb_eval")"
fb_shell='x=":(){ :|:& };:"; bash -c "$x"; x=true'
check "deny: fork bomb via bash -c of var"  deny "$(verdict "$fb_shell")"
fb_after='bash -c "$x"; x="f(){ f|f& };f"'
check "fp: value assigned after the use"    safe "$(verdict "$fb_after")"
# A full variable table must still allow OVERWRITING a key it already holds.
pad_vars=""; for i in $(seq 1 128); do pad_vars+="v$i=$i; "; done
check "deny: new var after 128 others"      deny "$(verdict "${pad_vars}danger=$R; \$danger -rf /")"
pad127=""; for i in $(seq 1 127); do pad127+="v$i=$i; "; done
check "deny: overwrite in a full table"     deny "$(verdict "x=ls; ${pad127}x=$R; \$x -rf /")"
# Several references in one word, and the default-value operator.
concat2='x=m; r${x} -rf /'
check "deny: reference inside a word"       deny "$(verdict "$concat2")"
concat3='a=r; b=m; ${a}${b} -rf /'
check "deny: two references in one word"    deny "$(verdict "$concat3")"
default_op='p=; '"$R"' -rf "${p:-/}"'
check "deny: \${p:-/} default value"        deny "$(verdict "$default_op")"
# Word splitting happens on newlines too, and a newline inside a VALUE separates
# words, not commands.
nl_cmd="x=\$'${R}\\n-rf\\n/'; \$x"
check "deny: value split on newlines"       deny "$(verdict "$nl_cmd")"
nl_args="x=\$'-rf\\n/'; $R \$x"
check "deny: operands split on newlines"    deny "$(verdict "$nl_args")"
# A comment can follow ')' as well — the ')' inside it must not close anything.
cmt_paren="echo \"\$( (true)# )
$R -rf /
)\""
check "deny: comment after ) inside \$( )"  deny "$(verdict "$cmt_paren")"
# Quoting that FORBIDS expansion: the shell passes the dollar through literally.
esc_dollar='p=/; '"$R"' -rf \$p'
check "fp: escaped \$p is literal"          safe "$(verdict "$esc_dollar")"
quoted_cmd="x=mkfs.ext4; ${SQ}\$x${SQ} /tmp/image"
check "fp: single-quoted \$x is literal"    safe "$(verdict "$quoted_cmd")"
# Naming a tool is not running it: these are everyday diagnostics.
check "fp: command -v mkfs.ext4"            safe "$(verdict "command -v mkfs.ext4")"
check "fp: man mkfs"                        safe "$(verdict "man mkfs")"
check "fp: stat /sbin/mkfs.ext4"            safe "$(verdict "stat /sbin/mkfs.ext4")"
check "fp: printf of a tool name"           safe "$(verdict "printf ${SQ}%s\\n${SQ} mkfs.ext4")"
check "fp: fork-bomb shape, only echoed"    safe "$(verdict 'f(){ f|f& }; echo f')"

# --- getent lookups are work too: thousands of ~user operands ran past the 5s
# --- timeout on a command well under the 16KB cap.
many_tilde="$R -r"; for i in $(seq 1 4000); do many_tilde+=" ~q"; done; many_tilde+=" /"
t0=$(date +%s%N); r_many=$(verdict "$many_tilde"); t1=$(date +%s%N)
check "perf: 4000 ~user operands < 3s"      ok "$( (( (t1-t0)/1000000 < 3000 )) && echo ok || echo "$(( (t1-t0)/1000000 ))ms" )"
check "deny: …and it still gates the root"  deny "$r_many"

# --- Oversized commands: the token scan is O(n²) and the hook has a 5s timeout,
# --- so past 16KB it hands off to the linear raw matcher. A guard that times out
# --- gates NOTHING, and does so silently — the one failure this floor must not have.
pad=$(printf 'x%.0s' $(seq 1 20000))
check "deny: 20KB command, real rm root"  deny "$(verdict "echo $pad && $R -rf /")"
check "fp: 20KB command, rm of /tmp"      safe "$(verdict "echo $pad && $R -rf /tmp/x")"

# --- Edit/Write: DENY-only guard no longer gates protected paths ------------
# (NTFS/Windows-mount writes are still DENY, but require a live mount to test.)
check "edit passthrough: /etc/hosts"    safe "$(verdict_edit /etc/hosts)"
check "edit passthrough: ~/.ssh/config" safe "$(verdict_edit "$HOME/.ssh/config")"
check "edit safe: project file"         safe "$(verdict_edit /home/nikita/x/main.py)"

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
