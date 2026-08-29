#!/usr/bin/env bash
# guard.sh - PreToolUse hook for Claude Code: last line of defense.
#
# Blocks exactly the irreversible, machine-destroying class:
#   1. recursive removal of the filesystem root or of the user's home root
#      (rm -r, find -delete, find -exec rm -r, find | xargs rm -r)
#   2. mkfs* (formatting a block device)
#   3. writing a stream straight to a block device (dd of=, redirect, tee)
#   4. fork bomb
#   5. rm --no-preserve-root
# Everything else passes.
#
# Decisions are made on what the shell would actually execute: the command line
# is lexed the way bash lexes it (quotes, comments, here-docs, command
# substitution, eval / sh -c / su -c / watch), so a merely *mentioned* dangerous
# command - in an argument, a comment, a here-doc body, a search pattern - never
# blocks. When anything is unknown (unexpanded variable, unparsable input,
# missing jq) the hook fails open: no output, exit 0.

set -u
export LC_ALL=C

payload=$(cat)

tool_name=''; cwd=''; cmd=''
{
  IFS= read -r -d '' tool_name || true
  IFS= read -r -d '' cwd       || true
  IFS= read -r -d '' cmd       || true
} < <(printf '%s' "$payload" | jq -j '
        ((.tool_name // "")           | tostring) + "\u0000" +
        ((.cwd       // "")           | tostring) + "\u0000" +
        ((.tool_input.command // "")  | tostring) + "\u0000"' 2>/dev/null)

# Only Bash can execute anything. Edit/Write and everything else: pass.
[ "$tool_name" = "Bash" ] || exit 0
[ -n "$cmd" ] || exit 0

GUARD_HOME="${HOME:-}"
GUARD_CWD="$cwd"
GUARD_USER="${USER:-${LOGNAME:-}}"                 # for ~name resolution
[ -n "$GUARD_USER" ] || GUARD_USER=$(id -un 2>/dev/null || true)
export GUARD_HOME GUARD_CWD GUARD_USER

read -r -d '' AWK_PROG <<'GUARD_AWK'
BEGIN {
  RS   = "\002"                      # read the whole command as one record
  SENT = "\001"                      # marker for an unpredictable expansion
  BRK  = "\\'\"$`|&;()<> \t\n#~"     # characters that end a plain run

  HOME = ENVIRON["GUARD_HOME"]
  sub(/\/+$/, "", HOME)
  if (HOME !~ /^\//) HOME = ""
  HOMEBASE = HOME; sub(/^.*\//, "", HOMEBASE)
  UNAME = ENVIRON["GUARD_USER"]

  EFF0 = ENVIRON["GUARD_CWD"]        # unknown cwd => relative paths stay unknown
  if (EFF0 !~ /^\//) EFF0 = SENT
  else { sub(/\/+$/, "", EFF0); if (EFF0 == "") EFF0 = "/" }

  QN = 0
}

{ SRC = SRC $0 }

END {
  Q[1] = SRC; QN = 1
  for (QI = 1; QI <= QN; QI++) {
    S = Q[QI]
    N = length(S)
    if (N == 0) continue
    EFF = EFF0; DSN = 0; DEPTH = 0; PREVFIND = 0
    SCAN = 1; tokenize(); collectvars(); SCAN = 0
    tokenize()
    if (forkbomb()) block("FORKBOMB")
    walk()
  }
}

function block(r) { print r; exit }

# ---------------------------------------------------------------- lexer ----
# Splits the command into words and operators exactly where bash would:
# quotes are removed, comments and here-doc bodies dropped, command
# substitutions and eval/sh -c payloads queued for their own analysis.

function tokenize(   c, c2, j) {
  TN = 0; HN = 0; PENDHD = 0; W = ""; INW = 0
  delete TW; delete TT; delete HD; delete HDS; delete HDI; delete HDB
  I = 1
  while (I <= N) {
    c = substr(S, I, 1)

    if (c == "\\") {                                   # escaped character
      c2 = substr(S, I+1, 1)
      if (c2 == "\n" || c2 == "") { I += 2; continue }
      W = W c2; INW = 1; I += 2; continue
    }
    if (c == "'") {                                    # single quotes: literal
      j = I + 1
      while (j <= N && substr(S, j, 1) != "'") j++
      W = W substr(S, I+1, j-I-1); INW = 1; I = j + 1; continue
    }
    if (c == "\"") { dquote(); continue }
    if (c == "$")  { dollar(0); W = W RV; INW = 1; I = RI; continue }
    if (c == "`")  { btick();   W = W RV; INW = 1; I = RI; continue }
    if (c == "~" && INW == 0) { tilde(); W = W RV; INW = 1; I = RI; continue }
    if (c == "#" && INW == 0) {                        # comment to end of line
      j = I
      while (j <= N && substr(S, j, 1) != "\n") j++
      I = j; continue
    }
    if (c == " " || c == "\t") { flushw(); I++; continue }
    if (c == "\n") {
      flushw(); emitop("\n"); I++
      if (HN > 0) heredocs()
      continue
    }
    if (index("|&;()<>", c) > 0) { oper(c); continue }

    j = I                                              # plain run of text
    while (j <= N) { c2 = substr(S, j, 1); if (index(BRK, c2) > 0) break; j++ }
    if (j == I) { W = W c; INW = 1; I++ }
    else        { W = W substr(S, I, j - I); INW = 1; I = j }
  }
  flushw()
}

function flushw() {
  if (!INW) return
  if (PENDHD) {                                        # here-doc delimiter
    HN++; HD[HN] = W; HDS[HN] = PENDHDS; HDI[HN] = PENDHDT; PENDHD = 0
  }
  TN++; TT[TN] = "W"; TW[TN] = W
  W = ""; INW = 0
}

function emitop(op) { TN++; TT[TN] = "O"; TW[TN] = op }

function oper(c,   op, c2, c3) {
  # a pure-digit word glued to < or > is a file descriptor, not an argument
  if (INW && (c == "<" || c == ">") && W ~ /^[0-9]+$/) { W = ""; INW = 0 }
  else flushw()

  c2 = substr(S, I+1, 1); c3 = substr(S, I+2, 1)
  op = c
  if      (c == "&" && c2 == ">") op = (c3 == ">") ? "&>>" : "&>"
  else if (c == "&" && c2 == "&") op = "&&"
  else if (c == "|" && c2 == "|") op = "||"
  else if (c == "|" && c2 == "&") op = "|&"
  else if (c == ";" && c2 == ";") op = ";;"
  else if (c == "<" && c2 == "<") op = (c3 == "-") ? "<<-" : ((c3 == "<") ? "<<<" : "<<")
  else if (c == "<" && c2 == "&") op = "<&"
  else if (c == ">" && c2 == ">") op = ">>"
  else if (c == ">" && c2 == "&") op = ">&"
  else if (c == ">" && c2 == "|") op = ">|"
  I += length(op)
  emitop(op)
  if (op == "<<" || op == "<<-") { PENDHD = 1; PENDHDS = (op == "<<-"); PENDHDT = TN }
}

function heredocs(   k, j, line, t, body) {
  for (k = 1; k <= HN; k++) {
    body = ""
    while (I <= N) {
      j = I
      while (j <= N && substr(S, j, 1) != "\n") j++
      line = substr(S, I, j - I)
      I = j + 1
      t = line
      if (HDS[k]) sub(/^\t+/, "", t)
      if (t == HD[k]) break
      body = body line "\n"
    }
    HDB[HDI[k]] = body
  }
  HN = 0
}

function dquote(   c, c2, j) {
  I++
  INW = 1
  while (I <= N) {
    c = substr(S, I, 1)
    if (c == "\"") { I++; return }
    if (c == "\\") {
      c2 = substr(S, I+1, 1)
      if (c2 == "\n") { I += 2; continue }
      if (c2 == "\"" || c2 == "\\" || c2 == "$" || c2 == "`") { W = W c2; I += 2; continue }
      W = W c; I++; continue
    }
    if (c == "$") { dollar(1); W = W RV; I = RI; continue }
    if (c == "`") { btick();   W = W RV; I = RI; continue }
    j = I
    while (j <= N) {
      c2 = substr(S, j, 1)
      if (c2 == "\"" || c2 == "\\" || c2 == "$" || c2 == "`") break
      j++
    }
    W = W substr(S, I, j - I); I = j
  }
}

function dollar(indq,   c2, name, j) {
  c2 = substr(S, I+1, 1)
  if (c2 == "(") {
    if (substr(S, I+2, 1) == "(") {                    # $(( arithmetic ))
      RV = SENT; RI = findarith(I+3); return
    }
    j = findparen(I+2)                                 # $( command )
    enqueue(substr(S, I+2, j - I - 3))
    RV = SENT; RI = j; return
  }
  if (c2 == "{") {                                     # ${NAME} and modifiers
    j = findbrace(I+2)
    RV = braceexp(substr(S, I+2, j - I - 2)); RI = j + 1; return
  }
  if (c2 == "'" && !indq) {                            # $'ansi-c quoting'
    j = I + 2
    while (j <= N && substr(S, j, 1) != "'") {
      if (substr(S, j, 1) == "\\") j++
      j++
    }
    RV = substr(S, I+2, j - I - 2); RI = j + 1; return
  }
  if (c2 == "\"" && !indq) { RV = ""; RI = I + 1; return }
  if (c2 ~ /^[A-Za-z_]$/) {
    j = I + 1
    while (j <= N && substr(S, j, 1) ~ /^[A-Za-z0-9_]$/) j++
    name = substr(S, I+1, j - I - 1)
    RV = varval(name); RI = j; return
  }
  if (c2 ~ /^[0-9@*#?$!-]$/) { RV = SENT; RI = I + 2; return }
  RV = "$"; RI = I + 1
}

function findbrace(p,   d, c) {                        # index of the matching }
  d = 1
  while (p <= N) {
    c = substr(S, p, 1)
    if (c == "\\") { p += 2; continue }
    if (c == "{") d++
    else if (c == "}") { d--; if (d == 0) return p }
    p++
  }
  return N + 1
}

# ${NAME}, ${NAME:-word}, ${NAME%pat}, ... - resolved when the result is
# predictable, SENT otherwise.
function braceexp(b,   i, L, name, rest, v, pat) {
  if (b !~ /^[A-Za-z_]/) return SENT                   # ${#x}, ${!x}, ${1}, ...
  L = length(b); i = 1
  while (i <= L && substr(b, i, 1) ~ /^[A-Za-z0-9_]$/) i++
  name = substr(b, 1, i-1)
  rest = substr(b, i)
  v = varval(name)
  if (rest == "") return v
  if (index(v, SENT) > 0) return SENT
  if (rest ~ /^:?[-=?]/) return (v != "" ? v : SENT)   # :- := :? - = ?
  if (substr(rest, 1, 2) == "%%") pat = substr(rest, 3)
  else if (substr(rest, 1, 1) == "%") pat = substr(rest, 2)
  else if (substr(rest, 1, 2) == "##") { pat = substr(rest, 3); return strip(v, pat, 0) }
  else if (substr(rest, 1, 1) == "#")  { pat = substr(rest, 2); return strip(v, pat, 0) }
  else return SENT
  return strip(v, pat, 1)
}

function strip(v, pat, suffix,   lp) {                 # literal prefix/suffix removal
  if (pat ~ /[*?[]/) return SENT                       # a glob: unpredictable
  lp = length(pat)
  if (lp == 0) return v
  if (suffix) {
    if (substr(v, length(v) - lp + 1) == pat) return substr(v, 1, length(v) - lp)
  } else {
    if (substr(v, 1, lp) == pat) return substr(v, lp + 1)
  }
  return v
}

# A variable resolves to what the shell would put there: an assignment seen in
# this very command line, or the value it really has in the environment.
function varval(name) {
  if (name == "HOME")  return HOME
  if (name == "PWD")   return EFF0
  if (name in VARS)    return VARS[name]
  if (name in ENVIRON) return ENVIRON[name]
  return SENT
}

# first pass: remember plain NAME=value assignments so that a target hidden
# behind a variable ("D=/; rm -rf $D") still resolves to what it really is
function collectvars(   i, w, e, name, val) {
  for (i = 1; i <= TN; i++) {
    if (TT[i] != "W") continue
    w = TW[i]
    if (w !~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
    e = index(w, "=")
    val = substr(w, e+1)
    if (index(val, SENT) > 0) continue
    VARS[substr(w, 1, e-1)] = val
  }
}

function findparen(p,   d, c, c2) {
  d = 1
  while (p <= N) {
    c = substr(S, p, 1)
    if (c == "\\") { p += 2; continue }
    if (c == "'") {
      p++
      while (p <= N && substr(S, p, 1) != "'") p++
      p++; continue
    }
    if (c == "\"") {
      p++
      while (p <= N) {
        c2 = substr(S, p, 1)
        if (c2 == "\\") { p += 2; continue }
        if (c2 == "\"") break
        p++
      }
      p++; continue
    }
    if (c == "(") d++
    else if (c == ")") { d--; if (d == 0) return p + 1 }
    p++
  }
  return N + 1
}

function findarith(p) {
  while (p <= N) {
    if (substr(S, p, 2) == "))") return p + 2
    p++
  }
  return N + 1
}

function btick(   j, inner) {
  j = I + 1
  while (j <= N) {
    if (substr(S, j, 1) == "\\") { j += 2; continue }
    if (substr(S, j, 1) == "`") break
    j++
  }
  inner = substr(S, I+1, j - I - 1)
  gsub(/\\`/, "`", inner)
  enqueue(inner)
  RV = SENT; RI = j + 1
}

# ~ and ~/... are the home; ~name is the home only when name is this user
function tilde(   c2, j, nm) {
  c2 = substr(S, I+1, 1)
  if (c2 == "" || c2 == "/" || index(" \t\n;|&<>)", c2) > 0) { RV = HOME; RI = I + 1; return }
  j = I + 1
  while (j <= N && substr(S, j, 1) ~ /^[A-Za-z0-9_.-]$/) j++
  nm = substr(S, I+1, j - I - 1)
  RI = j
  if (HOME != "" && nm != "" && (nm == UNAME || nm == HOMEBASE)) RV = HOME
  else RV = SENT
}

function enqueue(str) {
  if (SCAN || str == "" || QN >= 64) return
  Q[++QN] = str
}

# ------------------------------------------------------------- analysis ----

function walk(   i, tk, tt) {
  CWN = 0; RTN = 0; CHD = ""; CHS = ""; REDIR = 0
  for (i = 1; i <= TN; i++) {
    tt = TT[i]; tk = TW[i]
    if (tt == "W") {
      if (REDIR == 1) { RTN++; RT[RTN] = tk; REDIR = 0; continue }   # > target
      if (REDIR == 2) { REDIR = 0; continue }                        # < target
      if (REDIR == 3) { CHS = tk; REDIR = 0; continue }              # <<< data
      if (REDIR == 4) {                                              # >& target
        if (tk !~ /^[0-9]*-?$/) { RTN++; RT[RTN] = tk }
        REDIR = 0; continue
      }
      CWN++; CW[CWN] = tk
      continue
    }
    if (tk == ">" || tk == ">>" || tk == ">|" || tk == "&>" || tk == "&>>") { REDIR = 1; continue }
    if (tk == "<<" || tk == "<<-") { if (HDB[i] != "") CHD = HDB[i]; REDIR = 2; continue }
    if (tk == "<"  || tk == "<&")  { REDIR = 2; continue }
    if (tk == "<<<") { REDIR = 3; continue }
    if (tk == ">&")  { REDIR = 4; continue }
    endcmd(tk)
    # a subshell gets its own current directory: cd inside ( ) does not leak out
    if (tk == "(") { DEPTH++; SUB[DEPTH] = EFF }
    else if (tk == ")" && DEPTH > 0) { EFF = SUB[DEPTH]; DEPTH-- }
  }
  endcmd("")
}

function endcmd(sep,   ci, k) {
  if (CWN == 0 && RTN == 0) { CHD = ""; CHS = ""; return }

  for (k = 1; k <= RTN; k++) if (isdev(RT[k])) block("DEV_REDIR")

  FINDWIPE = 0
  ci = realcmd(1, CWN)
  if (ci > 0) dispatch(ci, CWN)
  PREVFIND = ((sep == "|" || sep == "|&") ? FINDWIPE : 0)
  CWN = 0; RTN = 0; CHD = ""; CHS = ""
}

function dispatch(ci, hi,   b, k, s2) {
  b = bn(CW[ci])
  if (b ~ /^mkfs(\.[A-Za-z0-9_+-]+)?$/) block("MKFS")
  if (b == "rm")   check_rm(ci, hi)
  if (b == "dd")   check_dd(ci, hi)
  if (b == "tee")  check_tee(ci, hi)
  if (b == "find") check_find(ci, hi)
  if (b == "cd" || b == "pushd" || b == "popd") do_cd(ci, hi, b)
  if (b == "eval") {
    s2 = ""
    for (k = ci+1; k <= hi; k++) s2 = s2 (k > ci+1 ? " " : "") CW[k]
    enqueue(s2)
  }
  if (b ~ /^(sh|bash|zsh|dash|ksh|ash|mksh|rbash)$/) check_shell(ci, hi)
  if (b ~ /^(su|runuser|script)$/) check_cmdopt(ci, hi)
  if (b == "flock") check_flock(ci, hi)
  if (b == "watch") check_watch(ci, hi)
}

# Skips assignments, shell reserved words and transparent wrappers
# (sudo, env, xargs, timeout, ...) to find the word that is really executed.
function realcmd(i, hi,   t, b) {
  while (i <= hi) {
    t = CW[i]
    if (t == "") { i++; continue }
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
    b = bn(t)
    if (b ~ /^(if|then|elif|else|fi|while|until|for|select|do|done|case|esac|in|function|coproc|\{|\}|\(|\)|!|\[\[)$/) { i++; continue }
    if (b == "sudo" || b == "doas") {
      i++
      while (i <= hi && CW[i] ~ /^-/) {
        if (CW[i] ~ /^-[uUgpCTRDh]$/) i++
        i++
      }
      continue
    }
    if (b == "env") {
      i++
      while (i <= hi && (CW[i] ~ /^-/ || CW[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
      continue
    }
    if (b ~ /^(command|builtin|exec|nohup|time|setsid|stdbuf|nice|ionice|busybox|xargs|unbuffer|proot|chroot|timeout|ssh-agent)$/) {
      i++
      while (i <= hi && (CW[i] ~ /^-/ || CW[i] ~ /^[0-9]+(\.[0-9]+)?[smhd]?$/)) i++
      continue
    }
    return i
  }
  return 0
}

function check_rm(ci, hi,   k, a, rec, nopr, endopt, tn, tg, brace) {
  rec = 0; nopr = 0; endopt = 0; tn = 0; brace = 0
  for (k = ci+1; k <= hi; k++) {
    a = CW[k]
    if (!endopt && a == "--") { endopt = 1; continue }
    if (!endopt && a ~ /^--/) {
      if (a == "--no-preserve-root") nopr = 1
      else if (a ~ /^--recursive/)   rec = 1
      continue
    }
    if (!endopt && a ~ /^-./) {
      if (a ~ /[rR]/) rec = 1
      continue
    }
    tg[++tn] = a
    if (index(a, "{}") > 0) brace = 1
  }
  if (nopr) block("NO_PRESERVE_ROOT")
  if (!rec) return
  for (k = 1; k <= tn; k++) if (isroot(tg[k])) block("RM_ROOT")
  # fed by an unfiltered "find /" through a pipe: the whole tree is the target
  if (PREVFIND && (tn == 0 || brace)) block("FIND_WIPE")
}

function check_dd(ci, hi,   k, a) {
  for (k = ci+1; k <= hi; k++) {
    a = CW[k]
    if (a ~ /^of=/ && isdev(substr(a, 4))) block("DD_DEV")
  }
}

function check_tee(ci, hi,   k, a) {
  for (k = ci+1; k <= hi; k++) {
    a = CW[k]
    if (a ~ /^-./) continue
    if (isdev(a)) block("DEV_WRITE")
  }
}

# find <root> ... -delete / -exec rm -r {} wipes the tree just like rm -rf does.
# A selection predicate (-name, -type, ...) means only some files go: that is
# ordinary work and passes.
function check_find(ci, hi,   k, a, root, del, filt, endi, m) {
  root = 0; del = 0; filt = 0
  k = ci + 1
  while (k <= hi && CW[k] ~ /^-[HLP]$/) k++
  while (k <= hi && CW[k] !~ /^[-(!,]/) {              # path operands
    if (isroot(CW[k])) root = 1
    k++
  }
  for (; k <= hi; k++) {
    a = CW[k]
    if (a == "-delete") { del = 1; continue }
    if (a ~ /^-(exec|execdir|ok|okdir)$/) {
      endi = k + 1
      while (endi <= hi && CW[endi] != ";" && CW[endi] != "+") endi++
      if (execwipes(k+1, endi-1)) del = 1
      k = endi
      continue
    }
    if (a ~ /^-(name|iname|path|ipath|wholename|iwholename|regex|iregex|lname|ilname|type|xtype|size|empty|perm|user|group|uid|gid|nouser|nogroup|newer[a-zA-Z]*|anewer|cnewer|atime|ctime|mtime|amin|cmin|mmin|used|links|inum|samefile|fstype|context|readable|writable|executable)$/) filt = 1
    else if (a == "(" || a == "!" || a == "-not" || a == "-o" || a == "-a" || a == "-or" || a == "-and") filt = 1
  }
  if (root && del && !filt) block("FIND_WIPE")
  FINDWIPE = (root && !filt)                           # ... | xargs rm -rf
}

# analyse the command find would run for every hit; {} is an unknown path
function execwipes(lo, hi,   ci, b, k, rec, brace) {
  if (lo > hi) return 0
  ci = realcmd(lo, hi)
  if (ci == 0) return 0
  dispatch(ci, hi)                                     # blocks on "find . -exec rm -rf / ;"
  if (bn(CW[ci]) != "rm") return 0
  rec = 0; brace = 0
  for (k = ci+1; k <= hi; k++) {
    if (CW[k] ~ /^--recursive/) rec = 1
    else if (CW[k] ~ /^-[^-]/ && CW[k] ~ /[rR]/) rec = 1
    else if (index(CW[k], "{}") > 0) brace = 1
  }
  return (rec && brace)
}

function do_cd(ci, hi, b,   k, a, tmp) {
  a = ""
  for (k = ci+1; k <= hi; k++) {
    if (CW[k] ~ /^-./) continue
    a = CW[k]; break
  }
  if (b == "popd") {                                   # back where pushd came from
    if (DSN > 0) EFF = DS[DSN--]; else EFF = SENT
    return
  }
  if (b == "pushd") {
    if (a == "") {                                     # no argument: swap the top two
      if (DSN > 0) { tmp = DS[DSN]; DS[DSN] = EFF; EFF = tmp } else EFF = SENT
      return
    }
    DS[++DSN] = EFF
  }
  if (a == "")  { EFF = (HOME != "" ? HOME : SENT); return }
  if (a == "-") { EFF = SENT; return }
  if (index(a, SENT) > 0) { EFF = SENT; return }
  EFF = resolve(a)
}

# sh -c '<script>' / here-string / here-doc fed to a shell all get executed.
# The script is the word after the option cluster that contains "c" (-ce, -cx,
# -lc ...), skipping an "--" that bash itself skips.
function check_shell(ci, hi,   k, m) {
  for (k = ci+1; k <= hi; k++) {
    if (CW[k] !~ /^-/) break                           # a script file, not a string
    if (CW[k] == "--") break
    if (CW[k] ~ /^-[A-Za-z]*c[A-Za-z]*$/) {
      m = k + 1
      while (m <= hi && CW[m] == "--") m++
      if (m <= hi) enqueue(CW[m])
      break
    }
    if (CW[k] ~ /^[-+][A-Za-z]*o$/) k++                # -o / -euo: takes a value
  }
  if (CHS != "") enqueue(CHS)
  if (CHD != "") enqueue(CHD)
}

# su / runuser / script: -c ARG is a shell command line, wherever it appears
function check_cmdopt(ci, hi,   k, m) {
  for (k = ci+1; k <= hi; k++) {
    if (CW[k] ~ /^--command=/) { enqueue(substr(CW[k], 11)); return }
    if (CW[k] == "--command" || CW[k] ~ /^-[A-Za-z]*c[A-Za-z]*$/) {
      m = k + 1
      while (m <= hi && CW[m] == "--") m++
      if (m <= hi) enqueue(CW[m])
      return
    }
  }
}

# flock [options] file -c 'cmd'  and  flock [options] file cmd args
function check_flock(ci, hi,   k) {
  k = ci + 1
  while (k <= hi && CW[k] ~ /^-/) {                    # options before the lock file
    if (flockc(k, hi)) return
    if (CW[k] ~ /^(-w|-E|--wait|--timeout|--conflict-exit-code)$/) k++
    k++
  }
  k++                                                  # the lock file or fd
  if (k > hi) return
  if (flockc(k, hi)) return                            # ... file -c 'cmd'
  k = realcmd(k, hi)                                   # ... file cmd args
  if (k > 0) dispatch(k, hi)
}

function flockc(k, hi,   m) {
  if (CW[k] ~ /^--command=/) { enqueue(substr(CW[k], 11)); return 1 }
  if (CW[k] != "--command" && CW[k] !~ /^-[A-Za-z]*c[A-Za-z]*$/) return 0
  m = k + 1
  while (m <= hi && CW[m] == "--") m++
  if (m <= hi) enqueue(CW[m])
  return 1
}

# watch hands its operands to sh -c
function check_watch(ci, hi,   k, s, started) {
  s = ""; started = 0
  for (k = ci+1; k <= hi; k++) {
    if (!started && CW[k] ~ /^-/) {
      if (CW[k] ~ /^(-n|--interval)$/) k++
      continue
    }
    started = 1
    s = s (s == "" ? "" : " ") CW[k]
  }
  enqueue(s)
}

# ------------------------------------------------------------ predicates ---

function bn(p) { sub(/^.*\//, "", p); return p }

function nrm(p,   a, m, k, st, sn, out) {
  m = split(p, a, "/")
  sn = 0
  for (k = 1; k <= m; k++) {
    if (a[k] == "" || a[k] == ".") continue
    if (a[k] == "..") { if (sn > 0) sn--; continue }
    st[++sn] = a[k]
  }
  out = ""
  for (k = 1; k <= sn; k++) out = out "/" st[k]
  if (out == "") out = "/"
  return out
}

function resolve(t) {
  if (t == "") return ""
  if (substr(t, 1, 1) != "/") {
    if (EFF == "" || index(EFF, SENT) > 0) return SENT
    t = EFF "/" t
  }
  return nrm(t)
}

# true only for the filesystem root and the root of the user's home.
# /home stays out of it - it is the parent, not the home root - but a glob that
# does expand to the home root (/home/*, $HOME*) counts.
function isroot(t,   p) {
  if (t == "" || index(t, SENT) > 0) return 0
  p = resolve(t)
  if (index(p, SENT) > 0) return 0
  if (p == "/" || p == "/*") return 1
  if (HOME == "") return 0
  if (p == HOME || p == HOME "/*") return 1
  if ((index(p, "*") > 0 || index(p, "?") > 0) && globmatch(p, HOME)) return 1
  return 0
}

# does this pattern match that exact path? (* and ? never cross a /)
function globmatch(pat, str,   re, i, c) {
  if (index(pat, "[") > 0) return 0                    # ranges: unpredictable
  re = ""
  for (i = 1; i <= length(pat); i++) {
    c = substr(pat, i, 1)
    if      (c == "*") re = re "[^/]*"
    else if (c == "?") re = re "[^/]"
    else if (index(".^$()+{}|\\", c) > 0) re = re "\\" c
    else re = re c
  }
  return (str ~ "^" re "$")
}

# a block device: /dev/sda, /dev/nvme0n1p2, /dev/mapper/vg-root, ...
# character devices (/dev/ttyUSB0, /dev/null) and bash's own /dev/tcp are not.
function isdev(p,   b) {
  if (p == "" || index(p, SENT) > 0) return 0
  if (p !~ /^\/dev\//) return 0
  b = substr(p, 6)
  if (b ~ /^(sd[a-z]+[0-9]*|hd[a-z]+[0-9]*|vd[a-z]+[0-9]*|xvd[a-z]+[0-9]*)$/) return 1
  if (b ~ /^(nvme[0-9]+n[0-9]+(p[0-9]+)?|mmcblk[0-9]+(p[0-9]+)?|nbd[0-9]+(p[0-9]+)?)$/) return 1
  if (b ~ /^(loop[0-9]+(p[0-9]+)?|md[0-9]+(p[0-9]+)?|dm-[0-9]+|ram[0-9]+|pmem[0-9]+[a-z]?)$/) return 1
  if (b ~ /^(sr[0-9]+|scd[0-9]+|fd[0-9]+|cdrom|dvd|floppy)$/) return 1
  if (b ~ /^(disk|mapper|block)\//) return 1
  return 0
}

# f() { f | f & } - a function whose body spawns itself more than once
function forkbomb(   i, j, name, self, amp, brace, depth) {
  for (i = 1; i + 2 <= TN; i++) {
    if (TT[i] != "W" || TW[i] == "") continue
    if (TT[i+1] != "O" || TW[i+1] != "(") continue
    if (TT[i+2] != "O" || TW[i+2] != ")") continue
    name = TW[i]
    brace = (TT[i+3] == "W" && TW[i+3] == "{")          # f() { ... }
    depth = 0
    self = 0; amp = 0
    for (j = i+3; j <= TN; j++) {                       # stay inside the body
      if (brace) { if (TT[j] == "W" && TW[j] == "}") break }
      else if (TT[j] == "O" && TW[j] == "(") depth++
      else if (TT[j] == "O" && TW[j] == ")") { if (--depth <= 0) break }
      else if (depth == 0 && TT[j] == "O" && (TW[j] == "\n" || TW[j] == ";")) break
      if (TT[j] == "W" && TW[j] == name) self++
      if (TT[j] == "O" && (TW[j] == "&" || TW[j] == "|" || TW[j] == "|&")) amp++
    }
    if (self >= 2 && amp > 0) return 1
  }
  return 0
}
GUARD_AWK

if command -v timeout >/dev/null 2>&1; then TO=(timeout 4); else TO=(); fi
reason=$(printf '%s' "$cmd" | ${TO[@]+"${TO[@]}"} awk "$AWK_PROG" 2>/dev/null)

case "$reason" in
  RM_ROOT)          msg='Заблокировано: рекурсивное удаление корня файловой системы или корня домашнего каталога.' ;;
  FIND_WIPE)        msg='Заблокировано: find удаляет всё дерево от корня файловой системы или домашнего каталога.' ;;
  NO_PRESERVE_ROOT) msg='Заблокировано: rm с --no-preserve-root — снятие защиты корня.' ;;
  MKFS)             msg='Заблокировано: mkfs — форматирование блочного устройства.' ;;
  DD_DEV)           msg='Заблокировано: dd пишет напрямую на блочное устройство.' ;;
  DEV_REDIR)        msg='Заблокировано: перенаправление вывода напрямую на блочное устройство.' ;;
  DEV_WRITE)        msg='Заблокировано: запись потока напрямую на блочное устройство.' ;;
  FORKBOMB)         msg='Заблокировано: fork-бомба.' ;;
  *)                exit 0 ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg"
exit 0
