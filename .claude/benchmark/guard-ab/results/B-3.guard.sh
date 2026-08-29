#!/usr/bin/env bash
# guard.sh — PreToolUse-хук для Claude Code: последний рубеж против катастрофических команд.
#
# Блокирует ровно пять классов (всё остальное пропускает):
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. mkfs* (форматирование);
#   3. запись потока на блочное устройство (dd of=, редирект >, tee);
#   4. fork-бомба;
#   5. rm --no-preserve-root.
#
# Решение принимается по тому, что реально выполнит shell: строка проходит через
# лексер (кавычки, $'...', подстановки, heredoc, комментарии, продолжения строк),
# затем разбирается на простые команды, и проверяется только слово в позиции
# команды. Поэтому `echo "rm -rf /"`, `# rm -rf /`, heredoc с таким текстом и
# grep-шаблон проходят, а `eval`, `bash -c`, `$(...)`, `sudo`, `$VAR` в позиции
# команды — разворачиваются и проверяются.
#
# Разбор сверен с настоящим bash дифференциальным тестом (см. guard_test.sh);
# два отклонения оставлены намеренно, обе — в сторону блокировки:
#   * тело заведомо ложной ветки (`while false; do rm -rf ~; done`) блокируется:
#     исполнимость ветки — свойство времени выполнения, статически неразрешимое;
#   * вложенный `sh -c` разбирается по правилам bash, поэтому `$'\x72\x6d'`
#     считается за `rm`, хотя dash так не умеет: чем окажется /bin/sh — неизвестно.
#
# stdin: один JSON. stdout: при блокировке ровно один JSON с deny, иначе пусто.
# Зависимости: bash, awk, jq. Сеть и внешние пакеты не используются.

export LC_ALL=C

input=$(cat 2>/dev/null)
[ -n "$input" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

tool_name=$(printf '%s' "$input" | jq -r 'if type=="object" then (.tool_name // "") else "" end' 2>/dev/null)
[ "$tool_name" = "Bash" ] || exit 0   # Edit/Write и всё прочее — всегда пропускаем

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // "" | if type=="string" then . else "" end' 2>/dev/null)
[ -n "$cmd" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // "" | if type=="string" then . else "" end' 2>/dev/null)

GUARD_AWK=$(cat <<'AWKEOF'
# ------------------------------------------------------------------ утилиты
function push(s) {                      # очередь подскриптов (eval, $(...), bash -c)
  if (s == "" || nq >= MAXQ || length(s) > MAXLEN) return
  queue[++nq] = s
}
function clean(s) {
  gsub(SOH, "", s); gsub(STX, "", s); gsub(/\t/, " ", s); gsub(/\n/, " ", s)
  if (length(s) > 200) s = substr(s, 1, 200) "..."
  return s
}
function deny(r) { if (denied) return; denied = 1; print "DENY\t" clean(r) }
function maybedev(p, r) { print "MAYBE\t" clean(p) "\t" clean(r) }

# поиск символа с позиции from — чанками, чтобы не копировать хвост скрипта
function findch(ch, from,   off, chunk, pos, L) {
  off = from
  while (off <= N) {
    chunk = substr(S, off, 4096); L = length(chunk); pos = index(chunk, ch)
    if (pos > 0) return off + pos - 1
    if (L < 4096) break
    off += 4096
  }
  return 0
}
function hexval(h,   i, c, v, d) {
  v = 0
  for (i = 1; i <= length(h); i++) {
    c = tolower(substr(h, i, 1)); d = index("0123456789abcdef", c) - 1
    if (d < 0) break
    v = v * 16 + d
  }
  return v
}
function octval(o,   i, v) { v = 0; for (i = 1; i <= length(o); i++) v = v * 8 + (substr(o, i, 1) + 0); return v }
function shq(s,   out, i, c) {          # безопасная переупаковка слова в скрипт
  out = "'"
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "'") out = out "'" "\"" "'" "\"" "'"; else out = out c
  }
  return out "'"
}
function base_of(p) { sub(/^.*\//, "", p); return p }

# ------------------------------------------------------------------ лексер
# Глобальные: S,N,I — вход; W,HASW — текущее слово; TV[],TT[],NT — токены.
# TT: "W" слово, "O" оператор, "R" оператор перенаправления.
function emitword() {
  if (!HASW) return
  if (EXPHD) { HDN++; HD[HDN] = W; HDS[HDN] = EXPHD - 1; HDID[HDN] = HDSEQ; EXPHD = 0; W = ""; HASW = 0; return }
  NT++; TV[NT] = W; TT[NT] = "W"; W = ""; HASW = 0
}
function emitop(o) { emitword(); NT++; TV[NT] = o; TT[NT] = "O" }
function emitredir(o) { emitword(); NT++; TV[NT] = o; TT[NT] = "R" }

function skipsq() { I = findch("'", I); if (I == 0) I = N + 1; else I++ }
function skipdq(   c) {
  while (I <= N) {
    c = substr(S, I, 1)
    if (c == "\\") { I += 2; continue }
    if (c == "\"") { I++; return }
    I++
  }
}
# I стоит на "(" — вернуть содержимое сбалансированных скобок в INNER
function matchparen(   depth, c, start) {
  start = I + 1; depth = 0
  while (I <= N) {
    c = substr(S, I, 1)
    if (c == "\\") { I += 2; continue }
    if (c == "'") { I++; skipsq(); continue }
    if (c == "\"") { I++; skipdq(); continue }
    if (c == "(") { depth++; I++; continue }
    if (c == ")") { depth--; I++; if (depth <= 0) { INNER = substr(S, start, I - 1 - start); return } continue }
    I++
  }
  INNER = substr(S, start)
}
function varval(name) {
  if (name == "HOME") return (HOMEV != "" ? HOMEV : SOH)
  if (name == "USER" || name == "LOGNAME" || name == "USERNAME") return (USERV != "" ? USERV : SOH)
  return STX name STX   # включая PWD: его значение зависит от cd и известно только при разборе команд
}
function tilde(   j, u) {                              # I стоит на "~"
  if (substr(S, I + 1, 1) == "+") { I += 2; return (CURDIR != "" ? STX "PWD" STX : SOH) }
  j = I + 1
  while (j <= N && substr(S, j, 1) ~ /^[A-Za-z0-9_.-]$/) j++
  u = substr(S, I + 1, j - I - 1)
  I = j
  if (u == "") return (HOMEV != "" ? HOMEV : SOH)
  return SOH                                           # ~user — чужой дом, не знаем
}
function pansiq(   c, nc, hex, oct, out) {             # $'...' с раскрытием escape
  I++; out = ""
  while (I <= N) {
    c = substr(S, I, 1)
    if (c == "'") { I++; break }
    if (c == "\\") {
      nc = substr(S, I + 1, 1); I += 2
      if (nc == "n") out = out "\n"
      else if (nc == "t") out = out "\t"
      else if (nc == "r") out = out "\r"
      else if (nc == "e" || nc == "E") out = out sprintf("%c", 27)
      else if (nc == "a") out = out sprintf("%c", 7)
      else if (nc == "b") out = out sprintf("%c", 8)
      else if (nc == "f") out = out sprintf("%c", 12)
      else if (nc == "v") out = out sprintf("%c", 11)
      else if (nc == "x") {
        hex = ""
        while (length(hex) < 2 && substr(S, I, 1) ~ /^[0-9a-fA-F]$/) { hex = hex substr(S, I, 1); I++ }
        if (hex != "" && hexval(hex) > 0) out = out sprintf("%c", hexval(hex))
      } else if (nc ~ /^[0-7]$/) {
        oct = nc
        while (length(oct) < 3 && substr(S, I, 1) ~ /^[0-7]$/) { oct = oct substr(S, I, 1); I++ }
        if (octval(oct) > 0) out = out sprintf("%c", octval(oct))
      } else out = out nc
      continue
    }
    out = out c; I++
  }
  W = W out; HASW = 1
}
function psquote(   j) {
  I++; HASW = 1
  j = findch("'", I)
  if (j == 0) { W = W substr(S, I); I = N + 1; return }
  W = W substr(S, I, j - I); I = j + 1
}
function pdquote(   c, nc) {
  I++; HASW = 1
  while (I <= N) {
    c = substr(S, I, 1)
    if (c == "\"") { I++; return }
    if (c == "\\") {
      nc = substr(S, I + 1, 1)
      if (nc == "\n") { I += 2; continue }
      if (nc == "\"" || nc == "\\" || nc == "$" || nc == "`") { W = W nc; I += 2; continue }
      W = W c; I++; continue
    }
    if (c == "$") { pdollar(1); continue }
    if (c == "`") { pbacktick(); continue }
    W = W c; I++
  }
}
function pbacktick(   c, inner) {
  I++; inner = ""
  while (I <= N) {
    c = substr(S, I, 1)
    if (c == "\\") { inner = inner substr(S, I + 1, 1); I += 2; continue }
    if (c == "`") { I++; break }
    inner = inner c; I++
  }
  push(inner); W = W SOH; HASW = 1
}
function pdollar(indq,   c2, j, depth, c, name, body) {   # I стоит на "$"
  c2 = substr(S, I + 1, 1)
  if (c2 == "(") {
    if (substr(S, I + 2, 1) == "(") { I++; matchparen(); W = W SOH; HASW = 1; return }  # $(( ))
    I++; matchparen(); push(INNER); W = W SOH; HASW = 1; return
  }
  # $'...' и $"..." — только вне двойных кавычек; внутри них "$" литерален
  if (c2 == "'") { if (indq) { W = W "$"; HASW = 1; I++; return } I++; pansiq(); return }
  if (c2 == "\"") { if (indq) { W = W "$"; HASW = 1; I++; return } I++; pdquote(); return }
  if (c2 == "{") {
    j = I + 2; depth = 1
    while (j <= N) {
      c = substr(S, j, 1)
      if (c == "\\") { j += 2; continue }
      if (c == "{") depth++
      else if (c == "}") { depth--; if (depth <= 0) break }
      j++
    }
    body = substr(S, I + 2, j - I - 2); I = j + 1
    if (body ~ /^[A-Za-z_][A-Za-z0-9_]*$/) W = W varval(body); else W = W SOH
    HASW = 1; return
  }
  if (c2 ~ /^[A-Za-z_]$/) {
    j = I + 1
    while (j <= N && substr(S, j, 1) ~ /^[A-Za-z0-9_]$/) j++
    name = substr(S, I + 1, j - I - 1); I = j
    W = W varval(name); HASW = 1; return
  }
  if (c2 == "") { W = W "$"; HASW = 1; I++; return }
  if (c2 ~ /^[0-9@*?$!#-]$/) { W = W SOH; HASW = 1; I += 2; return }
  W = W "$"; HASW = 1; I++
}
function procsub() { matchparen(); push(INNER); W = W SOH; HASW = 1 }
function predir(c) {
  if (HASW && W ~ /^[0-9]+$/) { W = ""; HASW = 0 }        # префикс дескриптора: 2>
  if (c == "<") {
    if (substr(S, I, 3) == "<<<") { emitredir("<<<"); I += 3; return }
    if (substr(S, I, 3) == "<<-") { emitredir("<<"); TX[NT] = ++HDSEQ; EXPHD = 2; I += 3; return }
    if (substr(S, I, 2) == "<<")  { emitredir("<<"); TX[NT] = ++HDSEQ; EXPHD = 1; I += 2; return }
    if (substr(S, I, 2) == "<(")  { I++; procsub(); return }
    if (substr(S, I, 2) == "<&")  { emitredir("<&"); I += 2; return }
    emitredir("<"); I++; return
  }
  if (substr(S, I, 2) == ">>") { emitredir(">>"); I += 2; return }
  if (substr(S, I, 2) == ">|") { emitredir(">|"); I += 2; return }
  if (substr(S, I, 2) == ">(") { I++; procsub(); return }
  if (substr(S, I, 2) == ">&") { emitredir(">&"); I += 2; return }
  emitredir(">"); I++
}
# Тело heredoc — данные, а не команды. Но если его читает шелл (bash <<EOF),
# оно всё-таки исполняется, поэтому текст сохраняем в HDBODY[] на такой случай.
function skipheredocs(   k, e, line, body) {
  for (k = 1; k <= HDN; k++) {
    body = ""
    while (I <= N) {
      e = findch("\n", I)
      if (e == 0) { line = substr(S, I); I = N + 1 } else { line = substr(S, I, e - I); I = e + 1 }
      if (HDS[k]) sub(/^\t+/, "", line)
      sub(/\r$/, "", line)
      if (line == HD[k]) break
      if (length(body) < MAXLEN) body = body line "\n"
    }
    HDBODY[HDID[k]] = body
  }
  HDN = 0
}
function lex(s,   c, nc, j) {
  S = s; N = length(s); I = 1
  NT = 0; W = ""; HASW = 0; HDN = 0; EXPHD = 0; HDSEQ = 0
  delete HDBODY; delete TX
  while (I <= N) {
    if (NT > MAXTOK) break
    c = substr(S, I, 1)
    if (c == " " || c == "\t" || c == "\r") { emitword(); I++; continue }
    if (c == "\n") { emitop("\n"); I++; if (HDN) skipheredocs(); continue }
    if (c == "#" && !HASW) { j = findch("\n", I); I = (j == 0 ? N + 1 : j); continue }
    if (c == "\\") {
      nc = substr(S, I + 1, 1)
      if (nc == "\n") { I += 2; continue }
      if (nc == "") { W = W "\\"; HASW = 1; I++; continue }
      W = W nc; HASW = 1; I += 2; continue
    }
    if (c == "'") { psquote(); continue }
    if (c == "\"") { pdquote(); continue }
    if (c == "`") { pbacktick(); continue }
    if (c == "$") { pdollar(0); continue }
    if (c == "~" && (!HASW || W ~ /[=:]$/)) { W = W tilde(); HASW = 1; continue }
    if (c == ";") { if (substr(S, I, 2) == ";;") { emitop(";;"); I += 2 } else { emitop(";"); I++ } continue }
    if (c == "&") {
      if (substr(S, I, 2) == "&&") { emitop("&&"); I += 2; continue }
      if (substr(S, I, 3) == "&>>") { emitredir("&>>"); I += 3; continue }
      if (substr(S, I, 2) == "&>") { emitredir("&>"); I += 2; continue }
      emitop("&"); I++; continue
    }
    if (c == "|") {
      if (substr(S, I, 2) == "||") { emitop("||"); I += 2; continue }
      if (substr(S, I, 2) == "|&") { emitop("|&"); I += 2; continue }
      emitop("|"); I++; continue
    }
    if (c == "(" ) { emitop("("); I++; continue }
    if (c == ")" ) { emitop(")"); I++; continue }
    if (c == "<" || c == ">") { predir(c); continue }
    W = W c; HASW = 1; I++
  }
  emitword()
}

# ------------------------------------------------------------------ пути
function norm(p,   parts, n, i, k, res) {
  if (substr(p, 1, 1) != "/") {
    if (CURDIR == "") return ""
    p = CURDIR "/" p
  }
  n = split(p, parts, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") { if (k > 0) k--; continue }
    NST[++k] = parts[i]
  }
  res = ""
  for (i = 1; i <= k; i++) res = res "/" NST[i]
  return (res == "" ? "/" : res)
}
function resolve(p,   i, j, a, b, name, rest, guard) {
  guard = 0
  while ((i = index(p, STX)) > 0 && guard++ < 20) {
    a = substr(p, 1, i - 1); b = substr(p, i + 1); j = index(b, STX)
    if (j == 0) return a SOH
    name = substr(b, 1, j - 1); rest = substr(b, j + 1)
    if (name in VARS) p = a VARS[name] rest
    else if (name == "PWD" && CURDIR != "") p = a CURDIR rest
    else if (name == "OLDPWD") p = a SOH rest
    else p = a SOH rest
  }
  if (index(p, STX)) gsub(STX, SOH, p)
  return p
}
function rootkind(np) {
  if (np == "/") return 1
  if (HOMEV != "" && np == HOMEV) return 2
  return 0
}
function globmatch(pat, str,   re, i, c, j, cls) {
  re = "^"
  i = 1
  while (i <= length(pat)) {
    c = substr(pat, i, 1)
    if (c == "*") re = re "[^/]*"
    else if (c == "?") re = re "[^/]"
    else if (c == "[") {
      j = index(substr(pat, i + 1), "]")
      if (j == 0) { re = re "\\[" }
      else { cls = substr(pat, i, j + 1); re = re cls; i += j }
    }
    else if (index(".^$+(){}|\\", c) > 0) re = re "\\" c
    else re = re c
    i++
  }
  return (str ~ (re "$"))
}
# 0 — безопасно, 1 — корень ФС, 2 — корень дома
function rootish(p,   np, q, last, k) {
  p = resolve(p)
  if (p == "" || index(p, SOH)) return 0
  np = norm(p)
  if (np == "") return 0
  k = rootkind(np)
  if (k) return k
  if (p ~ /[*?[]/) {
    last = np; sub(/^.*\//, "", last)
    if (last ~ /[*?[]/) {                       # "/*", "~/*" — удаление содержимого корня
      q = np; sub(/\/[^\/]*$/, "", q); if (q == "") q = "/"
      k = rootkind(q); if (k) return k
    }
    if (globmatch(np, "/")) return 1            # шаблон, раскрывающийся в корень
    if (HOMEV != "" && globmatch(np, HOMEV)) return 2
  }
  return 0
}
function devcheck(t, why,   p) {
  p = resolve(t)
  if (p == "" || index(p, SOH)) return
  p = norm(p)
  if (p == "" || p !~ /^\/dev\//) return
  if (p ~ SAFEDEV) return
  if (p ~ BLOCKDEV) { deny(why ": " p); return }
  maybedev(p, why ": " p)                       # проверим -b на стороне bash
}

# ------------------------------------------------------------------ команды
function iswrapper(b) {
  return (b == "sudo" || b == "doas" || b == "env" || b == "nohup" || b == "setsid" ||
          b == "nice" || b == "ionice" || b == "stdbuf" || b == "timeout" || b == "command" ||
          b == "builtin" || b == "exec" || b == "xargs" || b == "time" || b == "unbuffer" ||
          b == "busybox" || b == "eatmydata" || b == "proxychains")
}
function skipwrapper(b, i,   k, a, eq) {
  k = i + 1
  if (b == "env") {
    while (k <= CN) {
      a = CW[k]
      if (a == "--") { k++; break }
      if (a == "-u" || a == "--unset" || a == "-C" || a == "--chdir" || a == "-S") { k += 2; continue }
      if (a ~ /^-/) { k++; continue }
      if (a ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { eq = index(a, "="); VARS[substr(a, 1, eq - 1)] = substr(a, eq + 1); k++; continue }
      break
    }
    return k
  }
  if (b == "sudo" || b == "doas") {
    while (k <= CN) {
      a = CW[k]
      if (a == "--") { k++; break }
      if (a == "-u" || a == "-g" || a == "-p" || a == "-C" || a == "-h" || a == "-t" ||
          a == "-r" || a == "-U" || a == "--user" || a == "--group" || a == "--prompt") { k += 2; continue }
      if (a ~ /^-/) { k++; continue }
      if (a ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { eq = index(a, "="); VARS[substr(a, 1, eq - 1)] = substr(a, eq + 1); k++; continue }
      break
    }
    return k
  }
  if (b == "nice" || b == "ionice") {
    while (k <= CN) {
      a = CW[k]
      if (a == "-n" || a == "-c" || a == "-p" || a == "--adjustment" || a == "--classdata") { k += 2; continue }
      if (a ~ /^-/) { k++; continue }
      break
    }
    return k
  }
  if (b == "timeout") {
    while (k <= CN && CW[k] ~ /^-/) {
      if (CW[k] == "-s" || CW[k] == "-k" || CW[k] == "--signal" || CW[k] == "--kill-after") k += 2; else k++
    }
    return k + 1                                    # плюс длительность
  }
  if (b == "xargs") {
    while (k <= CN) {
      a = CW[k]
      if (a == "-n" || a == "-P" || a == "-I" || a == "-i" || a == "-a" || a == "-d" ||
          a == "-E" || a == "-e" || a == "-s" || a == "-L" || a == "-l") { k += 2; continue }
      if (a ~ /^-/) { k++; continue }
      break
    }
    return k
  }
  while (k <= CN && CW[k] ~ /^-/) k++              # sudo-подобные обёртки без аргументных опций
  return k
}
function checkrm(i,   k, a, rec, nopr, endo, no, kind) {
  rec = 0; nopr = 0; endo = 0; no = 0
  for (k = i + 1; k <= CN; k++) {
    a = CW[k]
    if (!endo && a == "--") { endo = 1; continue }
    if (!endo && substr(a, 1, 2) == "--") {
      if (a == "--recursive") rec = 1
      else if (a == "--no-preserve-root") nopr = 1
      continue
    }
    if (!endo && substr(a, 1, 1) == "-" && length(a) > 1) {
      if (a ~ /[rR]/) rec = 1
      continue
    }
    OPS[++no] = a
  }
  if (nopr) { deny("rm --no-preserve-root: снята защита корня файловой системы"); return }
  if (!rec) return
  for (k = 1; k <= no; k++) {
    kind = rootish(OPS[k])
    if (kind == 1) { deny("рекурсивное удаление корня файловой системы: rm -r " clean(OPS[k])); return }
    if (kind == 2) { deny("рекурсивное удаление домашнего каталога: rm -r " clean(OPS[k])); return }
  }
}
function checkdd(i,   k, a) {
  for (k = i + 1; k <= CN; k++) {
    a = resolve(CW[k])
    if (substr(a, 1, 3) == "of=") devcheck(substr(a, 4), "dd пишет на блочное устройство")
  }
}
function checktee(i,   k, a) {
  for (k = i + 1; k <= CN; k++) {
    a = CW[k]
    if (substr(a, 1, 1) == "-") continue
    devcheck(a, "tee пишет на блочное устройство")
  }
}
# Возвращает 1, если источник скрипта найден в аргументах (-c или файл),
# и 0, если шелл будет читать скрипт со stdin.
function checksh(i,   k, a) {
  for (k = i + 1; k <= CN; k++) {
    a = CW[k]
    if (a == "-c" || a ~ /^-[a-zA-Z]*c$/) { if (k + 1 <= CN) push(resolve(CW[k + 1])); return 1 }
    if (a == "--") { return (k + 1 <= CN) }
    if (substr(a, 1, 1) != "-") return 1
  }
  return 0
}
function checkforkbin(i,   k, a) {                  # perl -e 'fork while fork' и аналоги
  for (k = i + 1; k <= CN; k++) {
    a = CW[k]
    if (a ~ /fork/ && a ~ /(while|for|until|repeat|True|true)/) {
      deny("fork-бомба: бесконечное порождение процессов")
      return
    }
  }
}
function docd(i,   k, a, p) {
  for (k = i + 1; k <= CN; k++) {
    a = CW[k]
    if (a == "--") continue
    if (substr(a, 1, 1) == "-" && length(a) > 1) continue
    if (a == "-") { CURDIR = ""; return }
    p = resolve(a)
    if (index(p, SOH) || p == "") { CURDIR = ""; return }
    CURDIR = norm(p)
    return
  }
  CURDIR = HOMEV                                    # cd без аргументов
}
function runcmd(pdepth,   i, k, n, nm, base, eq, s, r) {
  if (CN == 0) return
  i = 1
  while (i <= CN && CW[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
    eq = index(CW[i], "="); VARS[substr(CW[i], 1, eq - 1)] = substr(CW[i], eq + 1); i++
  }
  if (i > CN) return
  while (1) {
    nm = CW[i]
    if (index(nm, STX)) {                           # команда пришла из переменной: $CMD ...
      r = resolve(nm)
      if (r != "" && index(r, SOH) == 0) {
        # Результат подстановки переменной shell разбивает на слова, но заново
        # тильду и $-подстановки в нём не раскрывает — поэтому слова экранируем.
        n = split(r, PARTS, "[ \t\n]+")
        s = ""
        for (k = 1; k <= n; k++) if (PARTS[k] != "") s = (s == "" ? shq(PARTS[k]) : s " " shq(PARTS[k]))
        for (k = i + 1; k <= CN; k++) s = s " " shq(CW[k])
        push(s)
      }
      return
    }
    if (index(nm, SOH)) return                      # имя команды неизвестно — судить не о чем
    base = base_of(nm)
    if (iswrapper(base)) {
      k = skipwrapper(base, i)
      if (k <= i || k > CN) return
      i = k; continue
    }
    break
  }
  if (base ~ /^mkfs/)                { deny("форматирование файловой системы: " clean(nm)); return }
  if (base == "rm")                  { checkrm(i); return }
  if (base == "dd")                  { checkdd(i); return }
  if (base == "tee")                 { checktee(i); return }
  if (base ~ /^(ba|z|k|mk|da|a)?sh$/) {
    if (checksh(i) == 0) {                          # скрипт придёт шеллу на stdin
      if (CURHD != "" && (CURHD in HDBODY)) push(HDBODY[CURHD])
      else if (CURHS != "") push(resolve(CURHS))
      else if (PIPEDFROM != "") push(PIPEDFROM)
    }
    return
  }
  if (base == "eval") {
    s = ""
    for (k = i + 1; k <= CN; k++) s = s " " resolve(CW[k])
    push(s); return
  }
  if (base ~ /^(perl|python[0-9.]*|ruby|php)$/) { checkforkbin(i); return }
  if ((base == "cd" || base == "pushd") && pdepth == 0) { docd(i); return }
}
function checkredir(op, t) {
  if (op == "<" || op == "<<" || op == "<<<" || op == "<&") return
  if (op == ">&" && t ~ /^[0-9]+-?$/) return
  devcheck(t, "перенаправление вывода на блочное устройство")
}
# Что окажется на stdin следующей команды конвейера, если она — шелл
function setpipe(sep,   k, b, s, fmt) {
  PIPEDFROM = ""
  if ((sep != "|" && sep != "|&") || CN == 0) return
  b = base_of(CW[1])
  if (b != "echo" && b != "printf") return
  s = ""; fmt = (b == "printf")
  for (k = 2; k <= CN; k++) {
    if (b == "echo" && CW[k] ~ /^-[neE]+$/) continue
    if (fmt) { fmt = 0; if (index(CW[k], "%")) continue }
    s = (s == "" ? resolve(CW[k]) : s " " resolve(CW[k]))
  }
  PIPEDFROM = s
}
function isreserved(v) {
  return (v == "if" || v == "then" || v == "else" || v == "elif" || v == "fi" || v == "do" ||
          v == "done" || v == "while" || v == "until" || v == "for" || v == "case" ||
          v == "esac" || v == "select" || v == "function" || v == "{" || v == "}" ||
          v == "!" || v == "time" || v == "coproc")
}
function forkbomb(   p, name, q, depth, cnt, amp, closer) {
  for (p = 1; p <= NT; p++) {
    name = ""
    if (TT[p] == "W" && TT[p + 1] == "O" && TV[p + 1] == "(" && TT[p + 2] == "O" && TV[p + 2] == ")") {
      name = TV[p]; q = p + 3
    } else if (TT[p] == "W" && TV[p] == "function" && TT[p + 1] == "W") {
      name = TV[p + 1]; q = p + 2
      if (TT[q] == "O" && TV[q] == "(" && TT[q + 1] == "O" && TV[q + 1] == ")") q += 2
    }
    if (name == "") continue
    while (q <= NT && TT[q] == "O" && TV[q] == "\n") q++
    if (TT[q] == "W" && TV[q] == "{") closer = "}"
    else if (TT[q] == "O" && TV[q] == "(") closer = ")"
    else continue
    depth = 1; cnt = 0; amp = 0; q++
    while (q <= NT && depth > 0) {
      if (closer == "}" && TT[q] == "W" && TV[q] == "{") depth++
      else if (closer == "}" && TT[q] == "W" && TV[q] == "}") depth--
      else if (closer == ")" && TT[q] == "O" && TV[q] == "(") depth++
      else if (closer == ")" && TT[q] == "O" && TV[q] == ")") depth--
      if (depth <= 0) break
      if (TT[q] == "W" && TV[q] == name) cnt++
      if (TT[q] == "O" && TV[q] == "&") amp = 1
      q++
    }
    if (cnt >= 2 && amp) {
      deny("fork-бомба: функция " clean(name) " рекурсивно порождает себя в фоне")
      return
    }
  }
}
function analyze(s,   p, v, pdepth) {
  lex(s)
  forkbomb()
  if (denied) return
  CN = 0; pdepth = 0; CURHD = ""; CURHS = ""; PIPEDFROM = ""
  for (p = 1; p <= NT && !denied; p++) {
    if (TT[p] == "W") {
      v = TV[p]
      if (CN == 0 && isreserved(v)) continue
      if (CN == 0 && TT[p + 1] == "O" && TV[p + 1] == "(" && TT[p + 2] == "O" && TV[p + 2] == ")") {
        p += 2; continue                             # определение функции — тело разберём дальше
      }
      CW[++CN] = v
      continue
    }
    if (TT[p] == "R") {
      if (TV[p] == "<<") { CURHD = TX[p]; continue } # разделитель уже поглощён лексером
      if (TT[p + 1] == "W") {
        if (TV[p] == "<<<") CURHS = TV[p + 1]; else checkredir(TV[p], TV[p + 1])
        p++
      }
      continue
    }
    if (TV[p] == "(") pdepth++
    else if (TV[p] == ")") { pdepth--; if (pdepth < 0) pdepth = 0 }
    runcmd(pdepth); setpipe(TV[p]); CN = 0; CURHD = ""; CURHS = ""
  }
  if (!denied) runcmd(pdepth)
  CN = 0; CURHD = ""; CURHS = ""; PIPEDFROM = ""
}

BEGIN {
  SOH = sprintf("%c", 1); STX = sprintf("%c", 2)
  MAXQ = 64; MAXTOK = 300000; MAXLEN = 2000000
  denied = 0; nq = 0
  BLOCKDEV = "^/dev/(sd[a-z]+[0-9]*|hd[a-z]+[0-9]*|vd[a-z]+[0-9]*|xvd[a-z]+[0-9]*|" \
             "nvme[0-9]+n[0-9]+(p[0-9]+)?|mmcblk[0-9]+(p[0-9]+)?|loop[0-9]+(p[0-9]+)?|" \
             "md[0-9]+(p[0-9]+)?|dm-[0-9]+|sr[0-9]+|nbd[0-9]+(p[0-9]+)?|ram[0-9]+|pmem[0-9]+|" \
             "r?disk[0-9]+(s[0-9]+)?|mapper/.+|disk/.+|block/.+|root)$"
  SAFEDEV  = "^/dev/(null|zero|full|random|urandom|ptmx|console|stdin|stdout|stderr|kmsg|log|" \
             "tty[^/]*|pts/.+|fd/.+|shm/.+)$"
  HOMEV = ENVIRON["GUARD_HOME"]; CWDV = ENVIRON["GUARD_CWD"]; USERV = ENVIRON["GUARD_USER"]
  CURDIR = (substr(CWDV, 1, 1) == "/" ? norm(CWDV) : "")
  if (substr(HOMEV, 1, 1) != "/") HOMEV = ""; else HOMEV = norm(HOMEV)
  if (HOMEV == "/") HOMEV = ""
}
{ SCRIPT = SCRIPT $0 "\n" }
END {
  push(SCRIPT)
  for (qi = 1; qi <= nq && !denied; qi++) analyze(queue[qi])
}
AWKEOF
)

if command -v timeout >/dev/null 2>&1; then
  verdict=$(printf '%s' "$cmd" | GUARD_HOME="$HOME" GUARD_CWD="$cwd" GUARD_USER="${USER:-$LOGNAME}" \
            timeout 4 awk "$GUARD_AWK" 2>/dev/null)
else
  verdict=$(printf '%s' "$cmd" | GUARD_HOME="$HOME" GUARD_CWD="$cwd" GUARD_USER="${USER:-$LOGNAME}" \
            awk "$GUARD_AWK" 2>/dev/null)
fi

[ -n "$verdict" ] || exit 0

reason=""
while IFS=$'\t' read -r kind f1 f2; do
  if [ "$kind" = "DENY" ]; then reason=$f1; break; fi
  if [ "$kind" = "MAYBE" ] && [ -b "$f1" ]; then reason=$f2; break; fi
done <<EOF
$verdict
EOF

[ -n "$reason" ] || exit 0

jq -cn --arg r "guard.sh заблокировал команду: $reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
