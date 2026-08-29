#!/usr/bin/env bash
# guard.sh — PreToolUse-хук Claude Code. Последний рубеж защиты от катастроф.
#
# Блокирует ровно необратимое:
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. форматирование блочного устройства (mkfs*);
#   3. запись потока прямо на блочное устройство (dd of=, редирект, tee, cp);
#   4. fork-бомбу;
#   5. rm --no-preserve-root.
#
# Решение принимается по тому, что реально выполнит shell: строка разбирается
# полноценным лексером (кавычки, экранирование, $'...', подстановки, heredoc,
# комментарии), затем проверяются только те слова, которые окажутся именем
# команды или её аргументом. Упоминание опасной команды в тексте, комментарии,
# heredoc-теле или шаблоне поиска не блокируется.
#
# Вход: JSON на stdin. Выход: при блокировке — один JSON-объект, иначе ничего.
# При любой внутренней ошибке хук молча пропускает вызов (сломанный хук не
# должен останавливать работу оператора).

set -u
export LC_ALL=C LANG=C

allow() { exit 0; }

payload=$(cat 2>/dev/null) || allow
[ -n "$payload" ] || allow
command -v jq >/dev/null 2>&1 || allow

# tool_name и cwd — двумя строками за один вызов jq
meta=$(printf '%s' "$payload" | jq -r 'try ((.tool_name // "") + "\n" + (.cwd // "")) catch ""' 2>/dev/null) || allow
tool=${meta%%$'\n'*}
cwd=${meta#*$'\n'}
[ "$tool" = "$cwd" ] && cwd=""

# Edit / Write и всё прочее — пропускаем по любым путям.
[ "$tool" = "Bash" ] || allow

cmd=$(printf '%s' "$payload" | jq -r 'try (.tool_input.command // "") catch ""' 2>/dev/null) || allow
[ -n "$cmd" ] || allow

# Реальные блочные устройства этой машины (без запуска подпроцессов).
blk=""
for _d in /sys/class/block/*; do
  [ -e "$_d" ] || continue
  blk="$blk ${_d##*/}"
done

IFS= read -r -d '' AWKSRC <<'GUARD_AWK'
# ------------------------------------------------------------------ утилиты
function basename(p) { sub(/.*\//, "", p); return p }

function findc(from, ch,   k) {
  for (k = from; k <= LN; k++) if (substr(LS, k, 1) == ch) return k
  return 0
}

function hexval(h,   i, c, v) {
  v = 0
  for (i = 1; i <= length(h); i++) {
    c = index("0123456789abcdef", tolower(substr(h, i, 1)))
    v = v * 16 + (c - 1)
  }
  return v
}

function octval(o,   i, v) {
  v = 0
  for (i = 1; i <= length(o); i++) v = v * 8 + (substr(o, i, 1) + 0)
  return v
}

# Подстановки, результат которых очевиден без запуска: $(echo слово), $(pwd).
# Всё остальное считается неизвестным (и потому неопасным).
function trivial_subst(s,   t) {
  t = s
  sub(/^[ \t\n]+/, "", t)
  sub(/[ \t\n;]+$/, "", t)
  if (t == "pwd" || t == "pwd -P" || t == "pwd -L" || t == "$PWD") return CWDD
  if (t ~ /^echo[ \t]+-n[ \t]+/) sub(/^echo[ \t]+-n[ \t]+/, "", t)
  else if (t ~ /^echo[ \t]+/) sub(/^echo[ \t]+/, "", t)
  else return ""
  if (t !~ /^[A-Za-z0-9_\/.,:+=%@^~-]+([ \t]+[A-Za-z0-9_\/.,:+=%@^~-]+)*$/) return ""
  gsub(/[ \t]+/, " ", t)
  return t
}

function push_script(s) {
  if (s == "") return
  if (QN >= MAXQ || TOTB > MAXTOTAL) return
  QN++; Q[QN] = s; TOTB += length(s)
}

function deny(msg) { printf "%s\n", msg; exit 0 }

# ------------------------------------------------------------------- лексер
# Накопление слова кусками: плоские участки добавляются одним substr.
function fp(   t) {
  if (PS) {
    if (WLEN < MAXLIT) { t = substr(LS, PS, LI - PS); W = W t; WLEN += length(t) } else WT = 1
    PS = 0
  }
}
function addc(ch) { fp(); if (WLEN < MAXLIT) { W = W ch; WLEN++ } else WT = 1; INW = 1 }
function adds(s2) { fp(); if (WLEN < MAXLIT) { W = W s2; WLEN += length(s2) } else WT = 1; INW = 1 }

function endword() {
  fp()
  if (INW) {
    NT++; TT[NT] = "W"; TV[NT] = W
    TU[NT] = WU; TG[NT] = WG; TQ[NT] = WQ; TR[NT] = WT; THD[NT] = 0
  }
  W = ""; WLEN = 0; INW = 0; WU = 0; WG = 0; WQ = 0; WT = 0
}
function emitop(v) {
  endword()
  NT++; TT[NT] = "O"; TV[NT] = v; TU[NT] = 0; TG[NT] = 0; TQ[NT] = 0; TR[NT] = 0; THD[NT] = 0
}
function emitrd(v) {
  NT++; TT[NT] = "R"; TV[NT] = v; TU[NT] = 0; TG[NT] = 0; TQ[NT] = 0; TR[NT] = 0; THD[NT] = 0
}

# $(...) и (...) — возвращает содержимое, LI ставится за закрывающую скобку
function capture_paren(st,   k, depth, c, q) {
  depth = 0; k = st; q = ""
  while (k <= LN) {
    c = substr(LS, k, 1)
    if (q == "") {
      if (c == "\\") { k += 2; continue }
      if (c == "\047" || c == "\"") { q = c; k++; continue }
      if (c == "(") { depth++; k++; continue }
      if (c == ")") {
        depth--; k++
        if (depth <= 0) { LI = k; return substr(LS, st + 1, k - st - 2) }
        continue
      }
      k++
    } else {
      if (q == "\"" && c == "\\") { k += 2; continue }
      if (c == q) q = ""
      k++
    }
  }
  LI = LN + 1
  return substr(LS, st + 1)
}

# ${...} — st указывает на первый символ содержимого
function capture_brace(st,   k, depth, c, q) {
  depth = 1; k = st; q = ""
  while (k <= LN) {
    c = substr(LS, k, 1)
    if (q == "") {
      if (c == "\\") { k += 2; continue }
      if (c == "\047" || c == "\"") { q = c; k++; continue }
      if (c == "{") depth++
      else if (c == "}") {
        depth--
        if (depth == 0) { LI = k + 1; return substr(LS, st, k - st) }
      }
      k++
    } else {
      if (q == "\"" && c == "\\") { k += 2; continue }
      if (c == q) q = ""
      k++
    }
  }
  LI = LN + 1
  return substr(LS, st)
}

function skip_arith(   k, depth, c) {
  k = LI + 1; depth = 0
  while (k <= LN) {
    c = substr(LS, k, 1)
    if (c == "(") depth++
    else if (c == ")") { depth--; if (depth <= 0) { LI = k + 1; return } }
    k++
  }
  LI = LN + 1
}

function btick(   k, c, inner, v) {
  inner = ""; k = LI + 1
  while (k <= LN) {
    c = substr(LS, k, 1)
    if (c == "\\") {
      c = substr(LS, k + 1, 1)
      if (c == "`" || c == "\\" || c == "$") { inner = inner c; k += 2; continue }
      inner = inner "\\"; k++; continue
    }
    if (c == "`") { k++; break }
    inner = inner c; k++
  }
  LI = k
  push_script(inner)
  v = trivial_subst(inner)
  if (v != "") adds(v); else { WU = 1; INW = 1 }
}

# $'...'
function ansi_c(   c, d, out, j, h) {
  LI += 2; out = ""
  while (LI <= LN) {
    c = substr(LS, LI, 1)
    if (c == "\047") { LI++; break }
    if (c == "\\") {
      d = substr(LS, LI + 1, 1)
      if (d == "x" || d == "X") {
        h = ""; j = LI + 2
        while (j <= LN && substr(LS, j, 1) ~ /[0-9a-fA-F]/ && length(h) < 2) { h = h substr(LS, j, 1); j++ }
        if (h != "") { if (hexval(h) > 0) out = out sprintf("%c", hexval(h)); LI = j }
        else { out = out "x"; LI += 2 }
        continue
      }
      if (d ~ /[0-7]/) {
        h = ""; j = LI + 1
        while (j <= LN && substr(LS, j, 1) ~ /[0-7]/ && length(h) < 3) { h = h substr(LS, j, 1); j++ }
        if (octval(h) > 0) out = out sprintf("%c", octval(h))
        LI = j
        continue
      }
      if (d == "n") out = out "\n"
      else if (d == "t") out = out "\t"
      else if (d == "r") out = out "\r"
      else if (d == "\\") out = out "\\"
      else if (d == "\047") out = out "\047"
      else if (d == "\"") out = out "\""
      else if (d == "e" || d == "E") out = out sprintf("%c", 27)
      else if (d == "a") out = out sprintf("%c", 7)
      else if (d == "b") out = out sprintf("%c", 8)
      else if (d == "f") out = out sprintf("%c", 12)
      else if (d == "v") out = out sprintf("%c", 11)
      else if (d == "") { LI++; break }
      else out = out d
      LI += 2
      continue
    }
    out = out c
    LI++
  }
  adds(out); WQ = 1; INW = 1
}

function dollar(   c, name, inner, j, v) {
  fp()
  c = substr(LS, LI + 1, 1)
  if (c == "(") {
    if (substr(LS, LI + 2, 1) == "(") { LI++; skip_arith(); WU = 1; INW = 1; return }
    inner = capture_paren(LI + 1)
    push_script(inner)
    v = trivial_subst(inner)
    if (v != "") adds(v); else { WU = 1; INW = 1 }
    return
  }
  if (c == "{") {
    inner = capture_brace(LI + 2)
    if (inner ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && (inner in VARV)) adds(VARV[inner])
    else { WU = 1; INW = 1 }
    return
  }
  if (c == "\047") { ansi_c(); return }
  if (c == "\"") { LI++; dq(); return }
  if (c ~ /[A-Za-z_]/) {
    j = LI + 1
    while (j <= LN && substr(LS, j, 1) ~ /[A-Za-z0-9_]/) j++
    name = substr(LS, LI + 1, j - LI - 1)
    LI = j
    if (name in VARV) adds(VARV[name])
    else { WU = 1; INW = 1 }
    return
  }
  if (c == "") { addc("$"); LI++; return }
  if (c ~ /[0-9@*?!#$-]/) { LI += 2; WU = 1; INW = 1; return }
  addc("$"); LI++
}

function dq(   c, d) {
  fp()
  INW = 1; WQ = 1; LI++
  while (LI <= LN) {
    c = substr(LS, LI, 1)
    if (c == "\"") { fp(); LI++; return }
    if (c == "\\") {
      fp()
      d = substr(LS, LI + 1, 1)
      if (d == "\n") LI += 2
      else if (d == "$" || d == "`" || d == "\"" || d == "\\") { addc(d); LI += 2 }
      else { addc("\\"); LI++ }
      continue
    }
    if (c == "$") { fp(); dollar(); continue }
    if (c == "`") { fp(); btick(); continue }
    if (!PS) PS = LI
    LI++
  }
  fp()
}

function redirop(c,   nx, nx2) {
  if (substr(LS, LI + 1, 1) == "(") {          # <(...) / >(...)
    push_script(capture_paren(LI + 1))
    WU = 1; INW = 1
    return
  }
  fp()
  if (INW && W ~ /^[0-9]+$/ && !WQ) { W = ""; WLEN = 0; INW = 0; WU = 0; WG = 0; WQ = 0; WT = 0 }
  else endword()
  nx = substr(LS, LI + 1, 1); nx2 = substr(LS, LI + 2, 1)
  if (c == ">") {
    if (nx == ">") { emitrd(">>"); LI += 2 }
    else if (nx == "&") { emitrd(">&"); LI += 2 }
    else if (nx == "|") { emitrd(">|"); LI += 2 }
    else { emitrd(">"); LI++ }
    return
  }
  if (nx == "<" && nx2 == "<") { emitrd("<<<"); LI += 3; return }
  if (nx == "<" && nx2 == "-") { emitrd("<<-"); LI += 3; HQN++; HQT[HQN] = NT; return }
  if (nx == "<") { emitrd("<<"); LI += 2; HQN++; HQT[HQN] = NT; return }
  if (nx == "&") { emitrd("<&"); LI += 2; return }
  if (nx == ">") { emitrd("<>"); LI += 2; return }
  emitrd("<"); LI++
}

function do_heredocs(   h, tok, delim, strip, content, j, line, tl, nx) {
  for (h = 1; h <= HQN; h++) {
    tok = HQT[h]
    strip = (TV[tok] == "<<-")
    delim = (TT[tok + 1] == "W") ? TV[tok + 1] : ""
    content = ""
    while (LI <= LN) {
      j = findc(LI, "\n")
      if (j == 0) { line = substr(LS, LI); nx = LN + 1 } else { line = substr(LS, LI, j - LI); nx = j + 1 }
      tl = line
      if (strip) sub(/^\t+/, "", tl)
      LI = nx
      if (tl == delim) break
      if (length(content) < MAXLIT) content = content line "\n"
    }
    TV[tok] = content
    THD[tok] = 1
  }
  HQN = 0
  delete HQT
}

function lex(s,   c, j) {
  LS = s; LN = length(s); LI = 1
  NT = 0
  delete TT; delete TV; delete TU; delete TG; delete TQ; delete TR; delete THD
  W = ""; WLEN = 0; INW = 0; PS = 0; WU = 0; WG = 0; WQ = 0; WT = 0
  HQN = 0; delete HQT
  while (LI <= LN) {
    c = substr(LS, LI, 1)
    if (c == " " || c == "\t" || c == "\r") { endword(); LI++; continue }
    if (c == "\n") { endword(); emitop("\n"); LI++; if (HQN) do_heredocs(); continue }
    if (c == "\\") {
      fp()
      c = substr(LS, LI + 1, 1)
      if (c == "\n") LI += 2
      else if (c == "") { addc("\\"); LI++ }
      else { addc(c); WQ = 1; LI += 2 }
      continue
    }
    if (c == "\047") {
      fp(); INW = 1; WQ = 1
      j = findc(LI + 1, "\047")
      if (j == 0) { adds(substr(LS, LI + 1)); LI = LN + 1 }
      else { adds(substr(LS, LI + 1, j - LI - 1)); LI = j + 1 }
      continue
    }
    if (c == "\"") { dq(); continue }
    if (c == "$") { dollar(); continue }
    if (c == "`") { fp(); btick(); continue }
    if (c == "#" && !INW && !PS) { j = findc(LI, "\n"); LI = (j ? j : LN + 1); continue }
    if (c == "<" || c == ">") { redirop(c); continue }
    if (c == "|") {
      j = substr(LS, LI + 1, 1)
      if (j == "|") { emitop("||"); LI += 2 } else if (j == "&") { emitop("|&"); LI += 2 } else { emitop("|"); LI++ }
      continue
    }
    if (c == "&") {
      j = substr(LS, LI + 1, 1)
      if (j == "&") { emitop("&&"); LI += 2 }
      else if (j == ">") {
        endword()
        if (substr(LS, LI + 2, 1) == ">") { emitrd("&>>"); LI += 3 } else { emitrd("&>"); LI += 2 }
      }
      else { emitop("&"); LI++ }
      continue
    }
    if (c == ";") {
      j = substr(LS, LI + 1, 1)
      if (j == ";") { emitop(";;"); LI += 2 } else { emitop(";"); LI++ }
      continue
    }
    if (c == "(" || c == ")") { emitop(c); LI++; continue }
    if (c == "*" || c == "?" || c == "[") WG = 1
    if (!PS) PS = LI
    INW = 1
    LI++
  }
  endword()
}

# ------------------------------------------------------------------ парсер
function newcmd() {
  NC++; CNW[NC] = 0; CRDN[NC] = 0; CHD[NC] = ""; CPIPE[NC] = PIP; CDEP[NC] = PDEPTH
  CBASE[NC] = ""; CBP[NC] = 0
}
function endcmd() {
  if (CNW[NC] == 0 && CRDN[NC] == 0 && CHD[NC] == "") { CPIPE[NC] = PIP; CDEP[NC] = PDEPTH; return }
  newcmd()
}

function parse(   k, v, skipnext, pend) {
  NC = 0; PIP = 1; PDEPTH = 0
  delete CW; delete CNW; delete CU; delete CG; delete CQ; delete CT
  delete CRD; delete CRDOP; delete CRDN; delete CRDU
  delete CHD; delete CPIPE; delete CDEP; delete CBASE; delete CBP
  newcmd()
  skipnext = 0; pend = ""
  for (k = 1; k <= NT; k++) {
    if (TT[k] == "R") {
      if (THD[k] == 1) { CHD[NC] = CHD[NC] TV[k]; skipnext = 1 }
      else pend = TV[k]
      continue
    }
    if (TT[k] == "W") {
      if (skipnext) { skipnext = 0; continue }
      if (pend != "") {
        if (pend == "<<<") CHD[NC] = CHD[NC] TV[k] "\n"
        else {
          CRDN[NC]++
          CRD[NC, CRDN[NC]] = TV[k]; CRDOP[NC, CRDN[NC]] = pend; CRDU[NC, CRDN[NC]] = TU[k]
        }
        pend = ""
        continue
      }
      CNW[NC]++
      CW[NC, CNW[NC]] = TV[k]; CU[NC, CNW[NC]] = TU[k]
      CG[NC, CNW[NC]] = TG[k]; CQ[NC, CNW[NC]] = TQ[k]; CT[NC, CNW[NC]] = TR[k]
      continue
    }
    v = TV[k]
    pend = ""
    if (v == "(") { PDEPTH++; PIP++; endcmd(); continue }
    if (v == ")") { if (PDEPTH > 0) PDEPTH--; PIP++; endcmd(); continue }
    if (v == "|" || v == "|&") { endcmd(); continue }
    PIP++; endcmd()
  }
  if (CNW[NC] == 0 && CRDN[NC] == 0 && CHD[NC] == "") NC--
}

# ------------------------------------------------------------------- пути
function norm(p,   parts, i2, m, st, sn, out, u, rest) {
  if (p == "") return ""
  if (substr(p, 1, 1) == "~") {
    if (p == "~") { if (HOMED == "") return ""; p = HOMED }
    else if (substr(p, 2, 1) == "/") { if (HOMED == "") return ""; p = HOMED substr(p, 2) }
    else {
      # ~пользователь: раскрываем только текущего пользователя, чужие дома неизвестны
      rest = p
      sub(/^~[^\/]*/, "", rest)
      u = substr(p, 2, length(p) - length(rest) - 1)
      if (USERNAME == "" || u != USERNAME || HOMED == "") return ""
      p = HOMED rest
    }
  }
  if (substr(p, 1, 1) != "/") {
    if (CWDD == "" || substr(CWDD, 1, 1) != "/") return ""
    p = CWDD "/" p
  }
  m = split(p, parts, "/")
  sn = 0
  for (i2 = 1; i2 <= m; i2++) {
    if (parts[i2] == "" || parts[i2] == ".") continue
    if (parts[i2] == "..") { if (sn > 0) sn--; continue }
    sn++; st[sn] = parts[i2]
  }
  out = ""
  for (i2 = 1; i2 <= sn; i2++) out = out "/" st[i2]
  if (out == "") out = "/"
  return out
}

# 0 — безопасно, 1 — корень ФС, 2 — домашний каталог, 3 — каталог всех домов
function root_target(t,   p, hp, par) {
  p = norm(t)
  if (p == "") return 0
  if (p == "/" || p == "/*" || p == "/.*") return 1
  if (HOMED == "") return 0
  hp = norm(HOMED)
  if (hp == "" || hp == "/") return 0
  if (p == hp || p == hp "/*") return 2
  par = hp
  sub(/\/[^\/]*$/, "", par)
  if (par != "" && par != "/" && (p == par || p == par "/*")) return 3
  return 0
}

function isblk(p,   q, b) {
  q = norm(p)
  if (q == "") q = p
  if (q !~ /^\/dev\//) return 0
  if (q ~ /^\/dev\/(null|zero|full|random|urandom|console|ptmx|stdin|stdout|stderr|tty)$/) return 0
  if (q ~ /^\/dev\/(fd|pts|shm|char|input|snd|bus|net|dri|usb|cpu|mqueue|hugepages|mem)\//) return 0
  if (q ~ /^\/dev\/tty[A-Za-z0-9]*$/) return 0
  if (q ~ /^\/dev\/(sd|hd|vd|xvd)[a-z]+[0-9]*$/) return 1
  if (q ~ /^\/dev\/nvme[0-9]+n[0-9]+(p[0-9]+)?$/) return 1
  if (q ~ /^\/dev\/mmcblk[0-9]+(p[0-9]+)?$/) return 1
  if (q ~ /^\/dev\/(loop|sr|scd|md|ram|nbd|dm-|fd)[0-9]+(p[0-9]+)?$/) return 1
  if (q ~ /^\/dev\/(mapper|disk|block|md|mmc)\//) return 1
  if (q ~ /^\/dev\/r?disk[0-9]+(s[0-9]+)*$/) return 1
  if (q == "/dev/root") return 1
  b = basename(q)
  if (b != "" && (b in BLKSET)) return 1
  return 0
}

# ---------------------------------------------------------------- проверки
function setvar(w, unk,   nm, e) {
  e = index(w, "=")
  if (e < 2) return
  nm = substr(w, 1, e - 1)
  if (nm !~ /^[A-Za-z_][A-Za-z0-9_]*$/) return
  if (unk) { delete VARV[nm]; return }
  VARV[nm] = substr(w, e + 1)
}

function skipopts(c, p, argopts, assign,   n, w, ch) {
  n = CNW[c]
  while (p <= n) {
    w = CW[c, p]
    if (w == "--") { p++; break }
    if (substr(w, 1, 2) == "--") { p++; continue }
    if (substr(w, 1, 1) == "-" && length(w) > 1) {
      ch = substr(w, length(w), 1)
      if (index(argopts, ch ":") > 0) p += 2; else p++
      continue
    }
    if (assign && w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { p++; continue }
    break
  }
  return p
}

function unwrap(c, p,   n, base, guard) {
  n = CNW[c]; guard = 0
  while (p <= n && guard++ < 40) {
    base = basename(CW[c, p])
    if (base == "sudo" || base == "doas") { p = skipopts(c, p + 1, "u:g:p:C:U:h:R:T:D:", 1); continue }
    if (base == "env") { p = skipopts(c, p + 1, "u:C:S:", 1); continue }
    if (base == "nohup" || base == "setsid" || base == "stdbuf" || base == "ionice" ||
        base == "nice" || base == "command" || base == "builtin" || base == "exec" ||
        base == "unbuffer" || base == "catchsegv" || base == "proxychains" || base == "systemd-run") {
      p = skipopts(c, p + 1, "n:c:i:o:e:a:p:t:P:u:G:", 0); continue
    }
    if (base == "timeout") { p = skipopts(c, p + 1, "s:k:", 0); if (p <= n) p++; continue }
    if (base == "xargs") { p = skipopts(c, p + 1, "n:P:I:i:d:E:s:a:L:l:", 0); continue }
    if (base == "flock" || base == "chroot" || base == "busybox") {
      p = skipopts(c, p + 1, "w:E:c:u:g:", 0)
      if (base != "busybox" && p <= n) p++
      continue
    }
    break
  }
  return p
}

function check_rm(c, p,   n, q, w, rec, eo, k, d, tn, TGT, TGU, msg) {
  n = CNW[c]; rec = 0; eo = 0; tn = 0
  for (q = p + 1; q <= n; q++) {
    w = CW[c, q]
    if (!eo && w == "--") { eo = 1; continue }
    if (!eo && substr(w, 1, 2) == "--") {
      if (w == "--no-preserve-root")
        deny("Заблокировано: rm --no-preserve-root снимает защиту корня файловой системы. Это необратимо.")
      if (w == "--recursive" || w ~ /^--recursive=/) rec = 1
      continue
    }
    if (!eo && substr(w, 1, 1) == "-" && length(w) > 1) {
      if (w ~ /[rR]/) rec = 1
      continue
    }
    tn++; TGT[tn] = w; TGU[tn] = (CU[c, q] || CT[c, q])
  }
  if (!rec) return
  for (k = 1; k <= tn; k++) {
    if (TGU[k]) continue
    d = root_target(TGT[k])
    if (d == 1) msg = "Заблокировано: рекурсивное удаление корня файловой системы (" TGT[k] " -> " norm(TGT[k]) "). Это уничтожит машину."
    else if (d == 2) msg = "Заблокировано: рекурсивное удаление корня домашнего каталога (" TGT[k] " -> " norm(TGT[k]) "). Это уничтожит все данные пользователя."
    else if (d == 3) msg = "Заблокировано: рекурсивное удаление каталога со всеми домашними каталогами (" TGT[k] " -> " norm(TGT[k]) ")."
    else continue
    deny(msg)
  }
}

function check_dd(c, p,   n, q, w, path) {
  n = CNW[c]
  for (q = p + 1; q <= n; q++) {
    w = CW[c, q]
    if (substr(w, 1, 3) != "of=") continue
    if (CU[c, q] || CT[c, q]) continue
    path = substr(w, 4)
    if (isblk(path))
      deny("Заблокировано: dd пишет поток прямо на блочное устройство " path ". Данные диска будут затёрты без возможности восстановления.")
  }
}

function check_tee(c, p,   n, q, w) {
  n = CNW[c]
  for (q = p + 1; q <= n; q++) {
    w = CW[c, q]
    if (substr(w, 1, 1) == "-" && length(w) > 1) continue
    if (CU[c, q] || CT[c, q]) continue
    if (isblk(w))
      deny("Заблокировано: запись потока на блочное устройство " w " через tee. Данные диска будут затёрты.")
  }
}

function check_cp(c, p,   n, q, w, last) {
  n = CNW[c]; last = ""
  for (q = p + 1; q <= n; q++) {
    w = CW[c, q]
    if (substr(w, 1, 1) == "-" && length(w) > 1) continue
    if (CU[c, q] || CT[c, q]) { last = ""; continue }
    last = w
  }
  if (last != "" && isblk(last))
    deny("Заблокировано: копирование прямо на блочное устройство " last ". Данные диска будут затёрты.")
}

# mkfs --help / --version ничего не форматирует
function only_help(c, p,   n, q, w, help) {
  n = CNW[c]; help = 0
  for (q = p + 1; q <= n; q++) {
    w = CW[c, q]
    if (w == "--help" || w == "-h" || w == "--version" || w == "-V") { help = 1; continue }
    return 0
  }
  return help
}

function check_redirs(c,   k, op, t) {
  for (k = 1; k <= CRDN[c]; k++) {
    op = CRDOP[c, k]
    if (op != ">" && op != ">>" && op != ">|" && op != "&>" && op != "&>>" && op != ">&" && op != "<>") continue
    if (CRDU[c, k]) continue
    t = CRD[c, k]
    if (op == ">&" && t ~ /^([0-9]+|-)$/) continue
    if (isblk(t))
      deny("Заблокировано: перенаправление вывода прямо на блочное устройство " t ". Данные диска будут затёрты.")
  }
}

function shell_handle(c, p,   n, q, w, found) {
  n = CNW[c]; found = 0
  for (q = p + 1; q <= n; q++) {
    w = CW[c, q]
    if (w == "--") continue
    if (substr(w, 1, 2) == "--") {
      if (w == "--command" || w == "-command") { found = q + 1; break }
      continue
    }
    if (substr(w, 1, 1) == "-" && length(w) > 1) {
      if (index(w, "c") > 0) { found = q + 1; break }
      if (substr(w, length(w), 1) == "o") q++
      continue
    }
    break
  }
  if (found) {
    if (found <= n && !CU[c, found] && !CT[c, found]) push_script(CW[c, found])
    return
  }
  if (CHD[c] != "") push_script(CHD[c])
}

function do_eval(c, p,   n, q, scr) {
  n = CNW[c]; scr = ""
  for (q = p + 1; q <= n; q++) {
    if (CU[c, q] || CT[c, q]) return
    scr = scr (scr == "" ? "" : " ") CW[c, q]
  }
  push_script(scr)
}

function do_cd(c, p,   n, q, w, t) {
  if (CDEP[c] > 0) return
  n = CNW[c]; t = ""
  for (q = p + 1; q <= n; q++) {
    w = CW[c, q]
    if (w == "-") { CWDD = ""; return }
    if (substr(w, 1, 1) == "-" && length(w) > 1) continue
    if (CU[c, q] || CT[c, q] || CG[c, q]) { CWDD = ""; return }
    t = w
    break
  }
  if (t == "") { if (HOMED != "") CWDD = HOMED; return }
  CWDD = norm(t)
}

function check(c,   n, p, w, base, q) {
  n = CNW[c]
  if (CHECKING) check_redirs(c)
  p = 1
  while (p <= n) {
    w = CW[c, p]
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { setvar(w, CU[c, p] || CT[c, p]); p++; continue }
    if (w in RESV) { p++; continue }
    break
  }
  if (p > n) return
  p = unwrap(c, p)
  if (p < 1 || p > n) return
  base = basename(CW[c, p])
  if (CU[c, p] || CT[c, p]) return          # имя команды неизвестно — не судим
  CBASE[c] = base; CBP[c] = p
  if (base == "export" || base == "declare" || base == "local" || base == "readonly" || base == "typeset") {
    for (q = p + 1; q <= n; q++)
      if (CW[c, q] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) setvar(CW[c, q], CU[c, q] || CT[c, q])
    return
  }
  if (base == "unset") { for (q = p + 1; q <= n; q++) delete VARV[CW[c, q]]; return }
  if (base == "cd" || base == "pushd") { do_cd(c, p); return }
  if (base in SHELL) { shell_handle(c, p); return }
  if (base == "su") { shell_handle(c, p); return }
  if (base == "eval") { do_eval(c, p); return }
  if (!CHECKING) return
  if (base ~ /^mkfs(\.[A-Za-z0-9_+.-]+)?$/ || base == "mke2fs" || base == "mkdosfs" || base == "mkntfs") {
    if (!only_help(c, p))
      deny("Заблокировано: " base " форматирует блочное устройство — всё его содержимое будет уничтожено безвозвратно.")
    return
  }
  if (base == "rm") { check_rm(c, p); return }
  if (base == "dd") { check_dd(c, p); return }
  if (base == "tee") { check_tee(c, p); return }
  if (base == "cp") { check_cp(c, p); return }
}

# echo/printf/heredoc, уходящие в интерпретатор по конвейеру: shell это выполнит
function pipe_scan(   c, c2, p, n, q, w, ok, scr) {
  for (c = 1; c <= NC; c++) {
    if (!(CBASE[c] in SHELL)) continue
    p = CBP[c]; n = CNW[c]; ok = 1
    for (q = p + 1; q <= n; q++) {
      w = CW[c, q]
      if (substr(w, 1, 1) == "-" && length(w) > 1) {
        if (substr(w, 1, 2) != "--" && index(w, "c") > 0) ok = 0
        continue
      }
      ok = 0
      break
    }
    if (!ok) continue
    for (c2 = 1; c2 <= NC; c2++) {
      if (c2 == c || CPIPE[c2] != CPIPE[c]) continue
      if (CBASE[c2] != "echo" && CBASE[c2] != "printf" && CBASE[c2] != "cat") continue
      if (CHD[c2] != "") push_script(CHD[c2])
      if (CBASE[c2] == "cat") continue
      scr = ""
      for (q = CBP[c2] + 1; q <= CNW[c2]; q++) {
        w = CW[c2, q]
        if (CU[c2, q] || CT[c2, q]) { scr = ""; break }
        if (scr == "" && w ~ /^-[neE]+$/) continue
        scr = scr (scr == "" ? "" : " ") w
      }
      if (scr != "") push_script(scr)
    }
  }
}

# определение функции, зовущей саму себя через конвейер/фон — fork-бомба
function forkbomb(   k, i2, name, t, cnt, haspipe, hasamp, depth, started, lim) {
  for (k = 1; k <= NT - 2; k++) {
    if (TT[k] != "W" || TT[k + 1] != "O" || TV[k + 1] != "(" || TT[k + 2] != "O" || TV[k + 2] != ")") continue
    name = TV[k]
    if (name == "" || name ~ /=$/) continue
    cnt = 0; haspipe = 0; hasamp = 0; depth = 0; started = 0
    lim = (k + 3 + 400 < NT) ? k + 3 + 400 : NT
    for (i2 = k + 3; i2 <= lim; i2++) {
      if (TT[i2] == "W") {
        t = TV[i2]
        if (t ~ /^\{/) { started = 1; depth++; sub(/^\{+/, "", t) }
        if (t ~ /\}$/) { sub(/\}+$/, "", t) ; if (started) { depth--; if (t == name) cnt++; if (depth <= 0) break } }
        if (t == name) cnt++
        continue
      }
      if (TT[i2] == "O") {
        if (TV[i2] == "|" || TV[i2] == "|&") haspipe = 1
        else if (TV[i2] == "&") hasamp = 1
      }
    }
    if (cnt >= 2 && (haspipe || hasamp))
      deny("Заблокировано: fork-бомба (функция " name " рекурсивно порождает себя). Машина уйдёт в отказ.")
  }
}

function checkall(   c) {
  for (c = 1; c <= NC; c++) check(c)
  if (CHECKING) pipe_scan()
}

# -------------------------------------------------------------------- вход
BEGIN {
  MAXLIT = 16384; MAXQ = 200; MAXTOTAL = 4000000
  n = split("if then elif else fi do done while until for select case esac in function coproc time ! { } (( ))", a, " ")
  for (i = 1; i <= n; i++) RESV[a[i]] = 1
  n = split("sh bash zsh dash ksh ash mksh rbash", a, " ")
  for (i = 1; i <= n; i++) SHELL[a[i]] = 1
  for (k in ENVIRON) if (k ~ /^[A-Za-z_][A-Za-z0-9_]*$/) VARV[k] = ENVIRON[k]
  delete VARV["OLDPWD"]
  delete VARV["GUARD_CWD"]
  delete VARV["GUARD_BLK"]
  HOMED = ENVIRON["HOME"]
  USERNAME = ENVIRON["USER"]
  if (USERNAME == "") USERNAME = ENVIRON["LOGNAME"]
  if (USERNAME == "" && HOMED != "") USERNAME = basename(HOMED)
  CWD0 = ENVIRON["GUARD_CWD"]
  if (CWD0 == "" || substr(CWD0, 1, 1) != "/") CWD0 = ""
  CWDD = CWD0
  if (CWD0 != "") VARV["PWD"] = CWD0
  n = split(ENVIRON["GUARD_BLK"], a, " ")
  for (i = 1; i <= n; i++) if (a[i] != "") BLKSET[a[i]] = 1
  S = ""
}

{ S = S $0 "\n" }

END {
  if (S == "") exit 0
  # Проход 1: собрать значения переменных (в том числе присвоенных ниже по тексту).
  CHECKING = 0
  lex(S); parse(); checkall()
  QN = 0; TOTB = 0; delete Q
  CWDD = CWD0
  # Проход 2: собственно проверка, с очередью вложенных скриптов.
  CHECKING = 1
  push_script(S)
  qi = 1
  while (qi <= QN) {
    sc = Q[qi]; qi++
    lex(sc)
    forkbomb()
    parse()
    checkall()
  }
  exit 0
}
GUARD_AWK

runner=""
command -v timeout >/dev/null 2>&1 && runner="timeout 4"

reason=$(printf '%s' "$cmd" | GUARD_CWD="$cwd" GUARD_BLK="$blk" $runner awk "$AWKSRC" 2>/dev/null) || allow
reason=${reason%%$'\n'*}

if [ -n "$reason" ]; then
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
exit 0
