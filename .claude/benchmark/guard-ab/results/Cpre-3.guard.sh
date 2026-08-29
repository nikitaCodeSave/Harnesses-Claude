#!/usr/bin/env bash
# guard.sh - PreToolUse hook for Claude Code: last line of defense.
#
# Blocks exactly the irreversible, machine-destroying class:
#   1. recursive removal of the filesystem root or of the user's home root
#   2. mkfs* (formatting a block device)
#   3. writing a stream straight to a block device (dd of=, redirect, tee)
#   4. fork bomb
#   5. rm --no-preserve-root
# Everything else passes.
#
# Decisions are made on what the shell would actually execute: the command line
# is lexed the way bash lexes it (quotes, comments, here-docs, command
# substitution, eval / sh -c), so a merely *mentioned* dangerous command -
# in an argument, a comment, a here-doc body, a search pattern - never blocks.
# When anything is unknown (unexpanded variable, unparsable input, missing jq)
# the hook fails open: no output, exit 0.

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
export GUARD_HOME GUARD_CWD

read -r -d '' AWK_PROG <<'GUARD_AWK'
BEGIN {
  RS   = "\002"                      # read the whole command as one record
  SENT = "\001"                      # marker for an unpredictable expansion
  BRK  = "\\'\"$`|&;()<> \t\n#~"     # characters that end a plain run

  HOME = ENVIRON["GUARD_HOME"]
  sub(/\/+$/, "", HOME)
  if (HOME !~ /^\//) HOME = ""

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
    EFF = EFF0
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
  if (c2 == "{") {
    j = I + 2
    while (j <= N && substr(S, j, 1) != "}") j++
    name = substr(S, I+2, j - I - 2)
    RV = varval(name); RI = j + 1; return
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

function varval(name) {
  if (name == "HOME") return HOME
  if (name == "PWD")  return EFF0
  if (name in VARS)   return VARS[name]
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

function tilde(   c2) {
  c2 = substr(S, I+1, 1)
  if (c2 == "" || c2 == "/" || index(" \t\n;|&<>)", c2) > 0) { RV = HOME; RI = I + 1; return }
  RV = SENT; RI = I + 1
  while (RI <= N && substr(S, RI, 1) ~ /^[A-Za-z0-9_.-]$/) RI++
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
    endcmd()
  }
  endcmd()
}

function endcmd(   ci, b, k, s2) {
  if (CWN == 0 && RTN == 0) { CHD = ""; CHS = ""; return }

  for (k = 1; k <= RTN; k++) if (isdev(RT[k])) block("DEV_REDIR")

  ci = realcmd()
  if (ci > 0) {
    b = bn(CW[ci])
    if (b ~ /^mkfs(\.[A-Za-z0-9_+-]+)?$/) block("MKFS")
    if (b == "rm")     check_rm(ci)
    if (b == "dd")     check_dd(ci)
    if (b == "tee")    check_tee(ci)
    if (b == "cd" || b == "pushd") do_cd(ci)
    if (b == "eval") {
      s2 = ""
      for (k = ci+1; k <= CWN; k++) s2 = s2 (k > ci+1 ? " " : "") CW[k]
      enqueue(s2)
    }
    if (b ~ /^(sh|bash|zsh|dash|ksh|ash|mksh|rbash)$/) check_shell(ci)
  }
  CWN = 0; RTN = 0; CHD = ""; CHS = ""
}

# Skips assignments, shell reserved words and transparent wrappers
# (sudo, env, xargs, timeout, ...) to find the word that is really executed.
function realcmd(   i, t, b) {
  i = 1
  while (i <= CWN) {
    t = CW[i]
    if (t == "") { i++; continue }
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
    b = bn(t)
    if (b ~ /^(if|then|elif|else|fi|while|until|for|select|do|done|case|esac|in|function|coproc|\{|\}|\(|\)|!|\[\[)$/) { i++; continue }
    if (b == "sudo" || b == "doas") {
      i++
      while (i <= CWN && CW[i] ~ /^-/) {
        if (CW[i] ~ /^-[uUgpCTRDh]$/) i++
        i++
      }
      continue
    }
    if (b == "env") {
      i++
      while (i <= CWN && (CW[i] ~ /^-/ || CW[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
      continue
    }
    if (b ~ /^(command|builtin|exec|nohup|time|setsid|stdbuf|nice|ionice|busybox|xargs|unbuffer|proot|chroot|timeout|ssh-agent)$/) {
      i++
      while (i <= CWN && (CW[i] ~ /^-/ || CW[i] ~ /^[0-9]+(\.[0-9]+)?[smhd]?$/)) i++
      continue
    }
    return i
  }
  return 0
}

function check_rm(ci,   k, a, rec, nopr, endopt, tn, tg) {
  rec = 0; nopr = 0; endopt = 0; tn = 0
  for (k = ci+1; k <= CWN; k++) {
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
  }
  if (nopr) block("NO_PRESERVE_ROOT")
  if (!rec) return
  for (k = 1; k <= tn; k++) if (isroot(tg[k])) block("RM_ROOT")
}

function check_dd(ci,   k, a) {
  for (k = ci+1; k <= CWN; k++) {
    a = CW[k]
    if (a ~ /^of=/ && isdev(substr(a, 4))) block("DD_DEV")
  }
}

function check_tee(ci,   k, a) {
  for (k = ci+1; k <= CWN; k++) {
    a = CW[k]
    if (a ~ /^-./) continue
    if (isdev(a)) block("DEV_WRITE")
  }
}

function do_cd(ci,   k, a) {
  a = ""
  for (k = ci+1; k <= CWN; k++) {
    if (CW[k] ~ /^-./) continue
    a = CW[k]; break
  }
  if (a == "")  { EFF = (HOME != "" ? HOME : SENT); return }
  if (a == "-") { EFF = SENT; return }
  if (index(a, SENT) > 0) { EFF = SENT; return }
  EFF = resolve(a)
}

# sh -c '<script>' / here-string / here-doc fed to a shell all get executed
function check_shell(ci,   k) {
  for (k = ci+1; k <= CWN; k++) {
    if (CW[k] ~ /^-[A-Za-z]*c$/ && k < CWN) { enqueue(CW[k+1]); break }
    if (CW[k] !~ /^-/) break
  }
  if (CHS != "") enqueue(CHS)
  if (CHD != "") enqueue(CHD)
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

# true only for the filesystem root and the root of the user's home
function isroot(t,   p, hp) {
  if (t == "" || index(t, SENT) > 0) return 0
  p = resolve(t)
  if (index(p, SENT) > 0) return 0
  if (p == "/" || p == "/*") return 1
  if (HOME != "") {
    if (p == HOME || p == HOME "/*") return 1
    hp = HOME
    sub(/\/[^\/]*$/, "", hp)
    if (hp != "" && hp != "/" && (p == hp || p == hp "/*")) return 1
  }
  return 0
}

# a real device under /dev, not one of the harmless pseudo-devices
function isdev(p) {
  if (p == "" || index(p, SENT) > 0) return 0
  if (p !~ /^\/dev\//) return 0
  if (p ~ /^\/dev\/(null|zero|full|random|urandom|ptmx|console|kmsg|log|fuse|zfs|tty[0-9]*|pts\/[0-9]+|std(in|out|err)|fd\/[0-9]+|shm\/.+|mqueue\/.+|net\/.+|snd\/.+|dri\/.+|input\/.+|bus\/.+|char\/.+|cpu\/.+|nvidia[a-z0-9]*)$/) return 0
  return 1
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
