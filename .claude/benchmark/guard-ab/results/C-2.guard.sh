#!/usr/bin/env bash
#
# guard.sh — PreToolUse-хук Claude Code, последний рубеж защиты.
#
# Контракт:
#   stdin  — один JSON-объект hook payload (.tool_name, .tool_input, .cwd);
#   stdout — при блокировке ровно один JSON-объект с permissionDecision=deny,
#            иначе пусто;
#   код возврата — всегда 0.
#
# Блокируется ровно пять классов необратимых команд:
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. форматирование блочного устройства (mkfs*);
#   3. запись потока прямо на блочное устройство (dd of=, редирект, tee);
#   4. fork-бомба;
#   5. rm --no-preserve-root.
# Всё остальное — включая рекурсивное удаление подкаталогов, нерекурсивное
# удаление, остановку сервисов, sudo как таковой и любые Edit/Write — проходит.
#
# Решение принимается по разбору того, что реально выполнит shell: строка
# токенизируется с учётом кавычек, экранирования, комментариев, heredoc'ов,
# подстановок команд, $'...', brace expansion, word splitting и раскрытия
# ~ / $HOME / ${HOME%…} / $@. Код, попадающий в shell не только через -c, но и
# через stdin (пайп, here-string, heredoc), разбирается как код; тело функции —
# только когда функцию действительно вызывают. Поэтому упоминание опасной
# команды в аргументе, комментарии или heredoc'е данных не блокируется, а
# `\rm -fr "${HOME:?}"` и `echo "rm -rf /" | bash` — блокируются.
#
# Принцип при любой неопределённости — пропустить (fail-open): неизвестная
# переменная, нечитаемый JSON, отсутствие jq/awk, превышение времени. Хук,
# который мешает работать, будет отключён и не защитит уже ни от чего.
#
# Границы: интерпретаторы кроме shell не разбираются (python -c '...' —
# для shell это просто аргумент), команды на удалённых машинах не наши.

set -u
export LC_ALL=C

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v awk >/dev/null 2>&1 || exit 0

tool=$(printf '%s' "$input" | jq -r 'if type == "object" then (.tool_name // "") else "" end' 2>/dev/null) || exit 0
[ "$tool" = "Bash" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r 'if (.cwd | type) == "string" then .cwd else "" end' 2>/dev/null)
case "$cwd" in /*) ;; *) cwd="" ;; esac

read -r -d '' AWK_GUARD <<'AWK_GUARD_EOF'
# ---------------------------------------------------------------------------
# Токенизатор shell + политика. Вход: команда целиком на stdin.
# Выход: пустой (пропустить) либо одна строка с причиной блокировки.
# ---------------------------------------------------------------------------
BEGIN {
  RS  = "\001"
  UNK = "\002"                       # маркер нераскрываемого расширения
  BO  = "\003"; BC = "\004"; BS = "\005"   # неэкранированные { } , — для brace expansion
  for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i

  HOME = ENVIRON["GUARD_HOME"]
  USER = ENVIRON["GUARD_USER"]
  if (HOME != "/") sub(/\/+$/, "", HOME)

  # символы, из-за которых текст перестаёт быть литералом
  META = "$`;&|<>(){}[]*?~!\n"

  # слова, которые могут стоять перед простой командой
  split("! time then else elif do if while until { } ;; done fi", A, " ")
  for (i in A) RESERVED[A[i]] = 1
  # обёртки: реальная команда идёт после них
  split("sudo doas command builtin exec env nice ionice nohup setsid stdbuf xargs timeout chrt taskset busybox", A, " ")
  for (i in A) WRAP[A[i]] = 1
  # шелл, у которого -c <строка> — это код, а stdin без операнда — тоже код
  split("sh bash zsh ksh dash ash mksh", A, " ")
  for (i in A) SHELLS[A[i]] = 1
  # устройства, запись в которые безобидна
  split("/dev/null /dev/zero /dev/full /dev/random /dev/urandom /dev/stdin /dev/stdout /dev/stderr /dev/tty /dev/console /dev/ptmx", A, " ")
  for (i in A) DEVSAFE[A[i]] = 1
  # предикаты find, не сужающие обход дерева
  split("-depth -d -xdev -mount -noleaf -follow -print -print0 -ls -H -L -P", A, " ")
  for (i in A) FINDPLAIN[A[i]] = 1
}

{ SRC = SRC SEP $0; SEP = "\001" }   # NUL-безопасная склейка, если RS встретился

END {
  push_src(SRC, ENVIRON["GUARD_CWD"], "")
  for (qi = 1; qi <= qn && qi <= 64; qi++) {
    CWD = qcwd[qi]; CURFN = qfn[qi]
    selfn = 0; conc = 0
    scan(qsrc[qi])
    # тело функции разбирается только при вызове: два рекурсивных вызова себя
    # вместе с пайпом или & — это fork-бомба
    if (CURFN != "" && selfn >= 2 && conc)
      deny("fork-бомба: функция «" clean(CURFN) "» рекурсивно порождает свои копии")
  }
}

function deny(reason) { print reason; exit 0 }

# ------------------------------ накопление слова ---------------------------
# cwtail — буфер: склейка по символу даёт O(n^2) на длинных словах.
function reset_word() { cwtext = ""; cwtail = ""; cwunk = 0; cwglob = 0; cwbrace = 0; inword = 0 }
function reset_cmd()  { wc = 0 }
function addstr(x)    { cwtail = cwtail x; inword = 1
                        if (length(cwtail) > 256) { cwtext = cwtext cwtail; cwtail = "" } }
function addunk()     { cwunk = 1; addstr(UNK) }
function wordtext()   { if (cwtail != "") { cwtext = cwtext cwtail; cwtail = "" } ; return cwtext }

# результат раскрытия: в кавычках — одно слово, без кавычек — с word splitting
function emit(v, indq) { if (indq) addstr(v); else add_split(v) }

function add_split(v,   arr, m, i) {
  if (v == "") return
  if (redir_pending != "" || (index(v, " ") == 0 && index(v, "\t") == 0 && index(v, "\n") == 0)) {
    addstr(v); return
  }
  m = split(v, arr, /[ \t\n]+/)
  for (i = 1; i <= m; i++) {
    if (i > 1) endword()
    if (arr[i] != "") addstr(arr[i])
    else if (i == 1) endword()
  }
}

function endword(   t, k, cnt) {
  if (!inword) return
  t = wordtext()
  if (redir_pending != "") {
    if (redir_pending == "<<" || redir_pending == "<<-") {
      hd_n++; hd_delim[hd_n] = demark(t); hd_strip[hd_n] = (redir_pending == "<<-") ? 1 : 0
      hd_code[hd_n] = 0
    } else if (redir_pending == "<<<") {
      hs_text = demark(t); hs_ok = cwunk ? 0 : 1
    } else if (!cwunk) {
      check_redirect(redir_pending, demark(t))
    }
    redir_pending = ""; reset_word(); return
  }
  if (cwbrace) {
    cnt = brace_expand(t)
    for (k = 1; k <= cnt; k++) { wc++; w[wc] = demark(BEXP[k]); u[wc] = cwunk; g[wc] = cwglob }
  } else {
    wc++; w[wc] = demark(t); u[wc] = cwunk; g[wc] = cwglob
  }
  reset_word()
}

function demark(t) {
  if (index(t, BO)) gsub(BO, "{", t)
  if (index(t, BC)) gsub(BC, "}", t)
  if (index(t, BS)) gsub(BS, ",", t)
  return t
}

# ------------------------------ brace expansion -----------------------------
# {a,b} раскрывается так же, как это сделает shell; без запятой — литерал.
function brace_expand(t,   qh, qt, cur, cnt, i) {
  BQ[1] = t; qh = 1; qt = 1; cnt = 0
  while (qh <= qt && cnt < 32 && qt < 64) {
    cur = BQ[qh++]
    if (!expand_first(cur)) { BEXP[++cnt] = cur; continue }
    for (i = 1; i <= EXN; i++) BQ[++qt] = EXP[i]
  }
  while (qh <= qt && cnt < 64) BEXP[++cnt] = BQ[qh++]
  return cnt
}

function expand_first(t,   i, L, depth, start, c, alt, an, cur, pre, post) {
  L = length(t); start = 0
  for (i = 1; i <= L; i++) if (substr(t, i, 1) == BO) { start = i; break }
  if (!start) return 0
  depth = 0; an = 0; cur = ""
  for (i = start; i <= L; i++) {
    c = substr(t, i, 1)
    if (c == BO) { depth++; if (depth == 1) continue }
    else if (c == BC) { depth--; if (depth == 0) { alt[++an] = cur; break } }
    else if (c == BS && depth == 1) { alt[++an] = cur; cur = ""; continue }
    cur = cur c
  }
  if (depth != 0 || an < 2) return 0
  pre = substr(t, 1, start - 1); post = substr(t, i + 1)
  EXN = an
  for (i = 1; i <= an; i++) EXP[i] = pre alt[i] post
  return 1
}

# ------------------------------ сканер -------------------------------------
function scan(src,   c, c2, inner, nm) {
  s = src; n = length(s); p = 1
  reset_cmd(); reset_word()
  hd_n = 0; hd_used = 0; redir_pending = ""; pdepth = 0
  PIPEV = ""; PIPEOK = 0; hs_text = ""; hs_ok = 0

  while (p <= n) {
    c = substr(s, p, 1)

    if (c == " " || c == "\t" || c == "\r") { endword(); p++; continue }
    if (c == "\n") { endword(); flush_cmd(0); p++; consume_heredocs(); continue }

    if (c == "\\") {                                  # экранирование: \rm -> rm
      c2 = substr(s, p + 1, 1)
      if (c2 == "\n") { p += 2; continue }
      if (c2 == "")   { p++; continue }
      addstr(c2); p += 2; continue
    }
    if (c == "#" && !inword) { while (p <= n && substr(s, p, 1) != "\n") p++; continue }
    if (c == "'")  { sq(); continue }
    if (c == "\"") { dq(); continue }
    if (c == "$")  { dollar(0); continue }
    if (c == "`")  { btick(); continue }
    if (c == "~" && !inword) { tilde(); continue }

    if (c == ";") { endword(); flush_cmd(0); p += (substr(s, p + 1, 1) == ";") ? 2 : 1; continue }
    if (c == "|") {
      endword(); c2 = substr(s, p + 1, 1)
      if (c2 == "|") { flush_cmd(0); p += 2 }
      else { conc = 1; flush_cmd(1); p += (c2 == "&") ? 2 : 1 }
      continue
    }
    if (c == "&") {
      c2 = substr(s, p + 1, 1)
      if (c2 == ">") { redir_start(); p += 2
                       if (substr(s, p, 1) == ">") { p++; redir_pending = "&>>" }
                       else redir_pending = "&>"
                       continue }
      if (c2 != "&") conc = 1                        # фон, а не &&
      endword(); flush_cmd(0); p += (c2 == "&") ? 2 : 1; continue
    }
    if (c == "(") {
      endword()
      if ((wc == 1 || (wc == 2 && w[1] == "function")) && fnparen()) {
        nm = w[wc]; reset_cmd(); capture_body(nm); continue
      }
      flush_cmd(0); pdepth++; cwdstack[pdepth] = CWD; p++; continue
    }
    if (c == ")") { endword(); flush_cmd(0)
                    if (pdepth > 0) { CWD = cwdstack[pdepth]; pdepth-- }
                    p++; continue }
    if (c == "{" && !inword && wc == 2 && w[1] == "function") {   # function f { ... }
      nm = w[2]
      if (grab_body(nm)) { reset_cmd(); continue }
    }

    if (c == ">" || c == "<") {
      if (substr(s, p + 1, 1) == "(") {               # подстановка процесса
        inner = cmdsub(p + 2); push_src(inner, CWD, ""); addunk(); continue
      }
      redir_start()
      c2 = substr(s, p + 1, 1)
      if (c == ">") {
        if (c2 == ">")      { redir_pending = ">>"; p += 2 }
        else if (c2 == "|") { redir_pending = ">|"; p += 2 }
        else if (c2 == "&") { redir_pending = ">&"; p += 2 }
        else                { redir_pending = ">";  p++ }
      } else {
        if (c2 == "<") {
          if (substr(s, p + 2, 1) == "<")      { redir_pending = "<<<"; p += 3 }
          else if (substr(s, p + 2, 1) == "-") { redir_pending = "<<-"; p += 3 }
          else                                 { redir_pending = "<<";  p += 2 }
        }
        else if (c2 == "&") { redir_pending = "<&"; p += 2 }
        else if (c2 == ">") { redir_pending = "<>"; p += 2 }
        else                { redir_pending = "<";  p++ }
      }
      continue
    }

    if (c == "*" || c == "?" || c == "[") { cwglob = 1; addstr(c); p++; continue }
    if (c == "{") { cwbrace = 1; addstr(BO); p++; continue }
    if (c == "}") { addstr(BC); p++; continue }
    if (c == ",") { addstr(BS); p++; continue }
    addstr(c); p++
  }
  endword(); flush_cmd(0)
}

# «2>file»: цифры перед оператором — номер дескриптора, а не слово.
function redir_start() {
  if (inword && !cwunk && wordtext() ~ /^[0-9]+$/) reset_word()
  else endword()
}

# после слова идёт «()» — это определение функции
function fnparen(   j) {
  j = p + 1
  while (j <= n && (substr(s, j, 1) == " " || substr(s, j, 1) == "\t")) j++
  if (substr(s, j, 1) == ")") { p = j + 1; return 1 }
  return 0
}

# тело функции — это ещё не выполнение: запоминаем текст, разберём при вызове
function capture_body(nm) {
  while (p <= n && (substr(s, p, 1) == " " || substr(s, p, 1) == "\t" || substr(s, p, 1) == "\n")) p++
  return grab_body(nm)
}

function grab_body(nm,   c, body) {
  c = substr(s, p, 1)
  if (c == "{")      body = skip_group("{", "}")
  else if (c == "(") body = skip_group("(", ")")
  else return 0
  if (body == "") return 0
  FNBODY[nm] = body
  return 1
}

# ищет парную закрывающую скобку, пропуская кавычки, экранирование и комментарии
function skip_group(opn, cls,   depth, i, c, c2, start) {
  start = p; depth = 0; i = p
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "'") { i++; while (i <= n && substr(s, i, 1) != "'") i++; i++; continue }
    if (c == "\"") {
      i++
      while (i <= n) { c2 = substr(s, i, 1)
                       if (c2 == "\\") { i += 2; continue }
                       if (c2 == "\"") break
                       i++ }
      i++; continue
    }
    if (c == "#" && i > start && substr(s, i - 1, 1) ~ /[ \t\n;&|]/) {
      while (i <= n && substr(s, i, 1) != "\n") i++
      continue
    }
    if (c == opn) { depth++; i++; continue }
    if (c == cls) { depth--; i++
                      if (depth == 0) { p = i; return substr(s, start + 1, i - start - 2) }
                      continue }
    i++
  }
  return ""
}

function sq(   c) {                                    # '...'
  p++; inword = 1
  while (p <= n) { c = substr(s, p, 1); if (c == "'") { p++; return } addstr(c); p++ }
}

function dq(   c, c2) {                                # "..."
  p++; inword = 1
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "\"") { p++; return }
    if (c == "\\") {
      c2 = substr(s, p + 1, 1)
      if (c2 == "\"" || c2 == "\\" || c2 == "$" || c2 == "`") { addstr(c2); p += 2; continue }
      if (c2 == "\n") { p += 2; continue }
      addstr(c); p++; continue
    }
    if (c == "$") { dollar(1); continue }
    if (c == "`") { btick(); continue }
    addstr(c); p++
  }
}

function dollar(indq,   c2, name, j, inner, out) {
  c2 = substr(s, p + 1, 1)
  if (c2 == "") { addstr("$"); p++; return }
  if (c2 == "'" && !indq) { ansic(); return }
  if (c2 == "\"" && !indq) { p++; dq(); return }
  if (c2 == "(") {
    if (substr(s, p + 2, 1) == "(") { cmdsub(p + 2); addunk(); return }   # $(( ))
    inner = cmdsub(p + 2)
    push_src(inner, CWD, "")
    out = fold_output(inner)                           # $(echo /) — результат известен
    if (FOLDOK) emit(out, indq); else addunk()
    return
  }
  if (c2 == "{") { param(indq); return }
  if (c2 ~ /[A-Za-z_]/) {
    j = p + 1; name = ""
    while (j <= n && substr(s, j, 1) ~ /[A-Za-z_0-9]/) { name = name substr(s, j, 1); j++ }
    p = j; expand_var(name, indq); return
  }
  if (c2 == "@" || c2 == "*") { p += 2; expand_args(c2, indq); return }
  if (c2 ~ /[0-9]/) { p += 2; expand_pos(c2 + 0, indq); return }
  addunk(); p += 2                                     # $? $$ $! ...
}

# ${VAR}, ${VAR:-…}, ${VAR%…}, ${VAR/…/…}, ${VAR:i:j} — считаем, когда можем
function param(indq,   depth, body, c, j, name, rest, v) {
  j = p + 2; depth = 1; body = ""
  while (j <= n) {
    c = substr(s, j, 1)
    if (c == "\\") { body = body substr(s, j + 1, 1); j += 2; continue }
    if (c == "{") depth++
    else if (c == "}") { depth--; if (depth == 0) { j++; break } }
    body = body c; j++
  }
  p = j
  if (body ~ /^[A-Za-z_][A-Za-z_0-9]*$/) { expand_var(body, indq); return }
  if (body == "@" || body == "*")        { expand_args(body, indq); return }
  if (body ~ /^[0-9]+$/)                 { expand_pos(body + 0, indq); return }
  if (body ~ /^[A-Za-z_][A-Za-z_0-9]*[-+=?#%\/:^,]/) {
    name = body; sub(/[-+=?#%\/:^,].*$/, "", name)
    rest = substr(body, length(name) + 1)
    v = getvar(name)
    if (VOK && apply_op(v, rest)) { emit(OPRES, indq); return }
  }
  addunk()
}

function getvar(name,   v) {
  VOK = 0
  if (name in VARS)         v = VARS[name]
  else if (name == "IFS")   v = " "
  else if (name == "PWD")   v = CWD
  else if (name in ENVIRON) v = ENVIRON[name]
  else return ""
  if (v == "" || index(v, UNK)) return ""
  VOK = 1
  return v
}

# v заведомо установлена и непуста — иначе сюда не попадаем
function apply_op(v, rest,   arg, k, off, len) {
  if (rest ~ /^:?[-=?]/) { OPRES = v; return 1 }        # ${V:-w} ${V:=w} ${V:?w}
  if (rest ~ /^:?\+/) {                                 # ${V:+w} -> w
    arg = rest; sub(/^:?\+/, "", arg)
    if (arg == "" || has_meta(arg)) return 0
    OPRES = arg; return 1
  }
  if (substr(rest, 1, 2) == "##") return strip_pre(v, substr(rest, 3))
  if (substr(rest, 1, 1) == "#")  return strip_pre(v, substr(rest, 2))
  if (substr(rest, 1, 2) == "%%") return strip_suf(v, substr(rest, 3))
  if (substr(rest, 1, 1) == "%")  return strip_suf(v, substr(rest, 2))
  if (substr(rest, 1, 2) == "//") return replace(v, substr(rest, 3), 1)
  if (substr(rest, 1, 1) == "/")  return replace(v, substr(rest, 2), 0)
  if (rest ~ /^:[0-9]+$/) { OPRES = substr(v, substr(rest, 2) + 1); return 1 }
  if (rest ~ /^:[0-9]+:[0-9]+$/) {
    k = index(substr(rest, 2), ":")
    off = substr(rest, 2, k - 1) + 0; len = substr(rest, k + 2) + 0
    OPRES = substr(v, off + 1, len); return 1
  }
  return 0
}

function strip_pre(v, pat) {
  if (pat == "") { OPRES = v; return 1 }
  if (has_meta(pat)) return 0
  OPRES = (substr(v, 1, length(pat)) == pat) ? substr(v, length(pat) + 1) : v
  return 1
}

function strip_suf(v, pat) {
  if (pat == "") { OPRES = v; return 1 }
  if (has_meta(pat)) return 0
  if (length(pat) <= length(v) && substr(v, length(v) - length(pat) + 1) == pat)
    OPRES = substr(v, 1, length(v) - length(pat))
  else OPRES = v
  return 1
}

function replace(v, spec, all,   k, pat, rep, out, i) {
  k = index(spec, "/")
  if (k == 0) { pat = spec; rep = "" } else { pat = substr(spec, 1, k - 1); rep = substr(spec, k + 1) }
  if (pat == "" || has_meta(pat) || has_meta(rep)) return 0
  if (substr(pat, 1, 1) == "#" || substr(pat, 1, 1) == "%") return 0   # привязка к краю
  out = ""
  while ((i = index(v, pat)) > 0) {
    out = out substr(v, 1, i - 1) rep
    v = substr(v, i + length(pat))
    if (!all) break
  }
  OPRES = out v
  return 1
}

function has_meta(t,   i) {
  for (i = 1; i <= length(META); i++) if (index(t, substr(META, i, 1))) return 1
  return 0
}

function expand_var(name, indq,   v) {
  if (name in VARS)         v = VARS[name]
  else if (name == "IFS")   v = " "
  else if (name == "PWD")   v = CWD
  else if (name in ENVIRON) v = ENVIRON[name]
  else { addunk(); return }
  if (v == "") { addunk(); return }
  if (index(v, UNK)) cwunk = 1
  emit(v, indq)
}

# позиционные параметры знаем только после «set -- …»
function expand_args(kind, indq,   i, joined) {
  if (!ARGSET) { addunk(); return }
  if (kind == "@") {
    for (i = 1; i <= ARGN; i++) { if (i > 1) endword(); addstr(ARGVL[i]) }
    if (ARGN == 0) inword = 1
    return
  }
  joined = ""
  for (i = 1; i <= ARGN; i++) joined = joined (i > 1 ? " " : "") ARGVL[i]
  if (joined == "") { inword = 1; return }
  emit(joined, indq)
}

function expand_pos(k, indq) {
  if (!ARGSET || k < 1) { addunk(); return }
  if (k <= ARGN) { emit(ARGVL[k], indq); return }
  inword = 1                                           # заведомо пусто
}

function tilde(   j, c, name) {
  j = p + 1; name = ""
  while (j <= n) { c = substr(s, j, 1); if (c !~ /[A-Za-z0-9_.-]/) break; name = name c; j++ }
  p = j
  if (name == "") { if (HOME != "") addstr(HOME); else addunk(); return }
  if (name == USER && HOME != "") { addstr(HOME); return }
  addunk()
}

# $'...' — раскрываем escape-последовательности (обфускация вида $'\x72\x6d')
function ansic(   c, c2, code, k) {
  p += 2; inword = 1
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "'") { p++; return }
    if (c == "\\") {
      c2 = substr(s, p + 1, 1); p += 2
      if      (c2 == "n") addstr("\n")
      else if (c2 == "t") addstr("\t")
      else if (c2 == "r") addstr("\r")
      else if (c2 == "e" || c2 == "E") addstr("\033")
      else if (c2 == "a") addstr("\007")
      else if (c2 == "b") addstr("\010")
      else if (c2 == "f") addstr("\014")
      else if (c2 == "v") addstr("\013")
      else if (c2 == "x") {
        code = 0; k = 0
        while (k < 2 && p <= n && hexval(substr(s, p, 1)) >= 0) {
          code = code * 16 + hexval(substr(s, p, 1)); p++; k++
        }
        if (k > 0) { if (code > 0) addstr(sprintf("%c", code)) } else addstr("x")
      }
      else if (c2 ~ /[0-7]/) {
        code = c2 + 0; k = 1
        while (k < 3 && p <= n && substr(s, p, 1) ~ /[0-7]/) {
          code = code * 8 + (substr(s, p, 1) + 0); p++; k++
        }
        if (code > 0) addstr(sprintf("%c", code))
      }
      else addstr(c2)
      continue
    }
    addstr(c); p++
  }
}

function hexval(ch) { return index("0123456789abcdef", tolower(ch)) - 1 }

# читает содержимое $( ... ) начиная с from, ставит p за закрывающую скобку
function cmdsub(from,   depth, i, c, inner) {
  i = from; depth = 1; inner = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { inner = inner c substr(s, i + 1, 1); i += 2; continue }
    if (c == "'") { inner = inner c; i++
                    while (i <= n && substr(s, i, 1) != "'") { inner = inner substr(s, i, 1); i++ }
                    inner = inner "'"; i++; continue }
    if (c == "\"") { inner = inner c; i++
                     while (i <= n && substr(s, i, 1) != "\"") {
                       if (substr(s, i, 1) == "\\") { inner = inner substr(s, i, 2); i += 2; continue }
                       inner = inner substr(s, i, 1); i++
                     }
                     inner = inner "\""; i++; continue }
    if (c == "(") depth++
    else if (c == ")") { depth--; if (depth == 0) { p = i + 1; return inner } }
    inner = inner c; i++
  }
  p = n + 1
  return inner
}

function btick(   c, inner, out) {
  p++; inner = ""
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "\\") { inner = inner substr(s, p + 1, 1); p += 2; continue }
    if (c == "`") { p++; break }
    inner = inner c; p++
  }
  push_src(inner, CWD, "")
  out = fold_output(inner)
  if (FOLDOK) add_split(out); else addunk()
}

# вывод команды, когда он полностью определён текстом: `echo …`, `pwd`
function fold_output(str,   L, i, c, cur, inw, nt, tk, k, cmd, out) {
  FOLDOK = 0
  if (str == "" || length(str) > 4096) return ""
  if (has_meta(str)) return ""
  L = length(str); nt = 0; cur = ""; inw = 0
  for (i = 1; i <= L; i++) {
    c = substr(str, i, 1)
    if (c == " " || c == "\t") { if (inw) { tk[++nt] = cur; cur = ""; inw = 0 } ; continue }
    if (c == "'" || c == "\"") {
      inw = 1; k = c; i++
      while (i <= L && substr(str, i, 1) != k) { cur = cur substr(str, i, 1); i++ }
      continue
    }
    if (c == "\\") { inw = 1; cur = cur substr(str, i + 1, 1); i++; continue }
    cur = cur c; inw = 1
  }
  if (inw) tk[++nt] = cur
  if (nt == 0) return ""
  cmd = base(tk[1])
  if (cmd == "pwd" && nt == 1) { if (CWD == "") return ""; FOLDOK = 1; return CWD }
  if (cmd == "echo") {
    k = 2
    while (k <= nt && tk[k] ~ /^-[neE]+$/) k++
    out = ""
    for (; k <= nt; k++) out = out (out == "" ? "" : " ") tk[k]
    FOLDOK = 1; return out
  }
  if (cmd == "printf" && nt >= 3 && (tk[2] == "%s" || tk[2] == "%s\\n" || tk[2] == "%s\n")) {
    out = ""
    for (k = 3; k <= nt; k++) out = out (out == "" ? "" : "\n") tk[k]
    FOLDOK = 1; return out
  }
  return ""
}

# то же для уже разобранной команды слева от пайпа
function pipe_out(ci,   j, b, out) {
  POK = 0
  if (ci < 1 || ci > wc || u[ci]) return ""
  b = base(w[ci])
  if (b == "echo") {
    j = ci + 1
    while (j <= wc && !u[j] && w[j] ~ /^-[neE]+$/) j++
    out = ""
    for (; j <= wc; j++) { if (u[j]) return "" ; out = out (out == "" ? "" : " ") w[j] }
    POK = 1; return out
  }
  if (b == "printf" && ci + 2 <= wc && !u[ci + 1] &&
      (w[ci + 1] == "%s" || w[ci + 1] == "%s\\n" || w[ci + 1] == "%s\n")) {
    out = ""
    for (j = ci + 2; j <= wc; j++) { if (u[j]) return "" ; out = out (out == "" ? "" : "\n") w[j] }
    POK = 1; return out
  }
  if (b == "pwd" && ci == wc) { if (CWD == "") return "" ; POK = 1; return CWD }
  return ""
}

# тело heredoc'а — данные, а не команды; исключение — heredoc, который читает shell
function consume_heredocs(   i, e, line, t, bstart, lstart) {
  if (hd_n == 0) { hd_used = 0; return }
  for (i = 1; i <= hd_n; i++) {
    bstart = p; lstart = p
    while (p <= n) {
      lstart = p
      e = index(substr(s, p), "\n")
      if (e == 0) { line = substr(s, p); p = n + 1 } else { line = substr(s, p, e - 1); p = p + e }
      t = line; sub(/\r$/, "", t)
      if (hd_strip[i]) sub(/^\t+/, "", t)
      if (t == hd_delim[i]) break
      lstart = p
    }
    # тело берём одним срезом: посимвольная склейка дала бы O(n^2)
    if (hd_code[i]) push_src(substr(s, bstart, lstart - bstart), CWD, "")
  }
  hd_n = 0; hd_used = 0
}

function push_src(str, cw, fn) {
  if (str == "" || qn >= 64) return
  qn++; qsrc[qn] = str; qcwd[qn] = cw; qfn[qn] = fn
}

# ------------------------------ разбор простой команды ----------------------
function flush_cmd(to_pipe,   i, ci, b, t, sdin, sok) {
  endword()
  redir_pending = ""
  hd_start = hd_used + 1

  if (wc > 0) {
    # перевод строки внутри пайпа команду не заканчивает: поток забирает
    # только та команда, у которой есть слова
    sdin = PIPEV; sok = PIPEOK
    PIPEV = ""; PIPEOK = 0
    if (hs_ok) { sdin = hs_text; sok = 1 }            # here-string важнее пайпа
    hs_text = ""; hs_ok = 0

    ci = cmd_index()
    if (ci > 0 && ci <= wc && !u[ci]) {
      t = w[ci]; b = base(t)
      if (CURFN != "" && t == CURFN) selfn++
      if (t in FNBODY && !(t in EXPANDED)) {           # вызов функции — разбираем тело
        EXPANDED[t] = 1; push_src(FNBODY[t], CWD, t)
      }

      if (b == "rm")                                  check_rm(ci, sdin, sok)
      else if (b ~ /^mkfs(\..*)?$/ || b == "mke2fs")  check_mkfs(ci)
      else if (b == "dd")                             check_dd(ci)
      else if (b == "tee")                            check_tee(ci)
      else if (b == "find")                           check_find(ci)
      else if (b == "cd")                             do_cd(ci)
      else if (b == "pushd" || b == "popd")           CWD = ""
      else if (b == "eval")                           do_eval(ci)
      else if (b == "trap")                           do_trap(ci)
      else if (b == "set")                            do_set(ci)
      else if (b in SHELLS || b == "su")              do_shell(ci, sdin, sok)
      else if (b == "source" || b == ".")             do_source(ci, sdin, sok)
      else if (b == "export" || b == "declare" || b == "typeset" || b == "local") {
        for (i = ci + 1; i <= wc; i++)
          if (!u[i] && w[i] ~ /^[A-Za-z_][A-Za-z_0-9]*=/) record_assign(w[i])
      }
    }
    if (to_pipe) { PIPEV = pipe_out(ci); PIPEOK = POK }
  }
  hd_used = hd_n
  reset_cmd()
}

# индекс слова с реальным именем команды: пропускает присваивания,
# ключевые слова и обёртки (sudo, env, timeout, ...)
function cmd_index(   i, t, b) {
  VIAXARGS = 0
  i = 1
  while (i <= wc) {
    t = w[i]
    if (!u[i] && t ~ /^[A-Za-z_][A-Za-z_0-9]*=/) { record_assign(t); i++; continue }
    if (t in RESERVED) { i++; continue }
    if (!u[i]) { b = base(t)
                 if (b in WRAP) { if (b == "xargs") VIAXARGS = 1; i = skip_wrapper(b, i); continue } }
    break
  }
  return i
}

function skip_wrapper(b, i,   t) {
  i++
  while (i <= wc) {
    t = w[i]
    if (t == "--") { i++; break }
    if (!u[i] && t ~ /^[A-Za-z_][A-Za-z_0-9]*=/) { record_assign(t); i++; continue }
    if (!u[i] && substr(t, 1, 1) == "-" && length(t) > 1) {
      i += takes_value(b, t) ? 2 : 1
      continue
    }
    break
  }
  if (b == "timeout" && i <= wc) i++                   # длительность
  return i
}

function takes_value(b, t) {
  if (b == "sudo")    return (t ~ /^-[ugpChTrtUD]$/)
  if (b == "doas")    return (t ~ /^-[uC]$/)
  if (b == "env")     return (t ~ /^-[uSC]$/)
  if (b == "nice")    return (t == "-n")
  if (b == "ionice")  return (t ~ /^-[cnp]$/)
  if (b == "timeout") return (t ~ /^-[sk]$/)
  if (b == "stdbuf")  return (t ~ /^-[ioe]$/)
  if (b == "xargs")   return (t ~ /^-[IiLnPsdEa]$/)
  if (b == "chrt")    return (t == "-p")
  if (b == "taskset") return (t ~ /^-[pc]$/)
  return 0
}

function record_assign(t,   e, name) {
  e = index(t, "=")
  name = substr(t, 1, e - 1)
  VARS[name] = substr(t, e + 1)
}

function base(t,   i) {
  i = length(t)
  while (i > 0 && substr(t, i, 1) != "/") i--
  return (i > 0) ? substr(t, i + 1) : t
}

function do_cd(ci,   j, t) {
  for (j = ci + 1; j <= wc; j++) {
    t = w[j]
    if (t == "--") continue
    if (!u[j] && substr(t, 1, 1) == "-" && length(t) > 1) continue
    if (u[j] || t == "-") { CWD = ""; return }
    CWD = normalize(t); return
  }
  CWD = HOME
}

function do_eval(ci,   j, str) {
  str = ""
  for (j = ci + 1; j <= wc; j++) str = str (j > ci + 1 ? " " : "") w[j]
  push_src(str, CWD, "")
}

# обработчик trap выполнится позже, но выполнится
function do_trap(ci,   j, t) {
  for (j = ci + 1; j <= wc; j++) {
    t = w[j]
    if (!u[j] && substr(t, 1, 1) == "-" && length(t) > 1) continue
    if (u[j] || t == "-" || t == "") return
    push_src(t, CWD, ""); return
  }
}

function do_set(ci,   j, seen) {
  seen = 0
  for (j = ci + 1; j <= wc; j++) {
    if (!seen) { if (!u[j] && w[j] == "--") { seen = 1; ARGN = 0; ARGSET = 1 } ; continue }
    if (u[j]) { ARGSET = 0; return }
    ARGVL[++ARGN] = w[j]
  }
}

# «-c строка» в любой записи (-c, -xc, -cx, -c --), иначе код может прийти со stdin
function do_shell(ci, sdin, sok,   j, t, eo, want) {
  eo = 0; want = 0
  for (j = ci + 1; j <= wc; j++) {
    t = w[j]
    if (!eo && !u[j] && t == "--") { eo = 1; continue }
    if (!eo && !u[j] && t ~ /^[-+][A-Za-z]+$/) {
      if (index(t, "c")) want = 1
      if (t ~ /[oO]$/) j++                             # -o <имя-опции>
      continue
    }
    if (want) { if (!u[j]) push_src(w[j], CWD, "") ; return }
    if (!u[j] && (t == "-" || t == "/dev/stdin")) break
    return                                             # операнд-файл сценария
  }
  if (want) return
  stdin_code(sdin, sok)
}

function do_source(ci, sdin, sok,   j, t) {
  for (j = ci + 1; j <= wc; j++) {
    if (u[j]) return
    t = w[j]
    if (t == "-" || t == "/dev/stdin") stdin_code(sdin, sok)
    return
  }
}

# shell читает код со стандартного ввода: пайп, here-string или heredoc
function stdin_code(sdin, sok) {
  if (sok) { push_src(sdin, CWD, ""); return }
  if (hd_n >= hd_start) hd_code[hd_start] = 1
}

# ------------------------------ политика ------------------------------------
function check_rm(ci, sdin, sok,   j, t, rec, npr, eo, kind, m, arr, i) {
  rec = 0; npr = 0; eo = 0
  for (j = ci + 1; j <= wc; j++) {
    t = w[j]
    if (!eo && t == "--") { eo = 1; continue }
    if (eo || u[j] || substr(t, 1, 1) != "-" || length(t) < 2) continue
    if (substr(t, 1, 2) == "--") {
      if (t == "--recursive")             rec = 1
      else if (t == "--no-preserve-root") npr = 1
    } else if (t ~ /[rR]/) rec = 1
  }
  if (npr)  deny("rm --no-preserve-root: снята штатная защита корня файловой системы")
  if (!rec) return

  eo = 0
  for (j = ci + 1; j <= wc; j++) {
    t = w[j]
    if (!eo && t == "--") { eo = 1; continue }
    if (u[j]) continue
    if (!eo && substr(t, 1, 1) == "-" && length(t) > 1) continue
    kind = target_kind(t, g[j])
    if (kind == "root") deny("рекурсивное удаление корня файловой системы: rm ... " clean(t))
    if (kind == "home") deny("рекурсивное удаление домашнего каталога: rm ... " clean(t))
  }

  if (VIAXARGS && sok) {                             # цели придут из пайпа
    m = split(sdin, arr, /[ \t\n\r]+/)
    for (i = 1; i <= m; i++) {
      if (arr[i] == "") continue
      kind = target_kind(arr[i], 0)
      if (kind == "root") deny("рекурсивное удаление корня файловой системы: xargs rm ... " clean(arr[i]))
      if (kind == "home") deny("рекурсивное удаление домашнего каталога: xargs rm ... " clean(arr[i]))
    }
  }
}

function check_mkfs(ci,   j) {
  for (j = ci + 1; j <= wc; j++)
    if (!u[j] && is_device(w[j]))
      deny("форматирование блочного устройства: " clean(w[ci]) " ... " clean(w[j]))
}

function check_dd(ci,   j, t) {
  for (j = ci + 1; j <= wc; j++) {
    t = w[j]
    if (!u[j] && substr(t, 1, 3) == "of=" && is_device(substr(t, 4)))
      deny("dd пишет напрямую на блочное устройство: " clean(t))
  }
}

function check_tee(ci,   j, t) {
  for (j = ci + 1; j <= wc; j++) {
    t = w[j]
    if (u[j] || (substr(t, 1, 1) == "-" && length(t) > 1)) continue
    if (is_device(t)) deny("tee пишет напрямую на блочное устройство: " clean(t))
  }
}

function check_redirect(op, t) {
  if (op != ">" && op != ">>" && op != ">|" && op != ">&" && op != "&>" && op != "&>>") return
  if (is_device(t)) deny("перенаправление потока напрямую на блочное устройство: " op " " clean(t))
}

# find сносит дерево целиком, когда обход ничем не сужен, а действие — удаление
function check_find(ci,   j, k, t, act, narrowed, ps, pe, kind) {
  act = 0; narrowed = 0
  j = ci + 1
  while (j <= wc && !u[j] && (w[j] == "-H" || w[j] == "-L" || w[j] == "-P")) j++
  ps = j
  while (j <= wc && !(!u[j] && substr(w[j], 1, 1) == "-" && length(w[j]) > 1) &&
         !(!u[j] && (w[j] == "!" || w[j] == "("))) j++
  pe = j - 1
  if (pe < ps) return

  for (; j <= wc; j++) {
    t = w[j]
    if (u[j]) { narrowed = 1; continue }
    if (t == "-delete") { act = 1; continue }
    if (t == "-exec" || t == "-execdir" || t == "-ok" || t == "-okdir") {
      if (j + 1 <= wc && !u[j + 1] && base(w[j + 1]) == "rm") { act = 1; check_exec_rm(j + 1) }
      j++
      while (j <= wc && w[j] != ";" && w[j] != "+") j++
      continue
    }
    if (t in FINDPLAIN) continue
    narrowed = 1
  }
  if (!act || narrowed) return

  for (k = ps; k <= pe; k++) {
    if (u[k]) continue
    kind = target_kind(w[k], g[k])
    if (kind == "root") deny("find удаляет всё дерево от корня файловой системы: find " clean(w[k]) " ...")
    if (kind == "home") deny("find удаляет домашний каталог целиком: find " clean(w[k]) " ...")
  }
}

# «-exec rm -rf <путь>» — цели стоят прямо в строке find
function check_exec_rm(ci,   j, t, rec, kind) {
  rec = 0
  for (j = ci + 1; j <= wc && w[j] != ";" && w[j] != "+"; j++) {
    t = w[j]
    if (!u[j] && substr(t, 1, 1) == "-" && length(t) > 1 && t ~ /[rR]/) rec = 1
  }
  if (!rec) return
  for (j = ci + 1; j <= wc && w[j] != ";" && w[j] != "+"; j++) {
    t = w[j]
    if (u[j] || (substr(t, 1, 1) == "-" && length(t) > 1)) continue
    kind = target_kind(t, g[j])
    if (kind == "root") deny("рекурсивное удаление корня файловой системы: find -exec rm ... " clean(t))
    if (kind == "home") deny("рекурсивное удаление домашнего каталога: find -exec rm ... " clean(t))
  }
}

# "" — не корень и не дом; "root"/"home" — уничтожение всего дерева
function target_kind(txt, isglob,   pth, i, last, dir) {
  if (index(txt, UNK)) return ""
  pth = normalize(txt)
  if (pth == "") return ""
  if (pth == "/") return "root"
  if (HOME != "" && pth == HOME) return "home"
  if (isglob) {
    i = length(pth)
    while (i > 1 && substr(pth, i, 1) != "/") i--
    last = substr(pth, i + 1)
    dir  = (i <= 1) ? "/" : substr(pth, 1, i - 1)
    # последний компонент — glob, выметающий каталог целиком (*, .*, ...)
    if (last ~ /\*/ && last ~ /^[][*?.{},!^-]*$/) {
      if (dir == "/") return "root"
      if (HOME != "" && dir == HOME) return "home"
    }
  }
  return ""
}

function normalize(path,   parts, out, m, i, k, res) {
  if (path == "") return ""
  if (substr(path, 1, 1) != "/") {
    if (CWD == "" || substr(CWD, 1, 1) != "/") return ""    # cwd неизвестен
    path = CWD "/" path
  }
  m = split(path, parts, "/")
  k = 0
  for (i = 1; i <= m; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") { if (k > 0) k--; continue }
    out[++k] = parts[i]
  }
  res = ""
  for (i = 1; i <= k; i++) res = res "/" out[i]
  return (res == "") ? "/" : res
}

function is_device(t,   pth) {
  if (t == "") return 0
  pth = normalize(t)
  if (pth == "") pth = t
  if (substr(pth, 1, 5) != "/dev/") return 0
  if (pth in DEVSAFE) return 0
  if (pth ~ /^\/dev\/(tty|pts\/|fd\/|shm\/|std|net\/|snd\/|input\/|dri\/|char\/|null|zero|full|random|urandom|console|ptmx)/) return 0
  if (pth ~ /^\/dev\/(sd|hd|vd|xvd|nvme|mmcblk|loop|dm-|md[0-9]|nbd|sr[0-9]|fd[0-9]|ram[0-9]|pmem|zd[0-9]|rdisk|disk[0-9])/) return 1
  if (pth ~ /^\/dev\/(mapper|disk|block)\//) return 1
  return sysblock(pth)                                 # спросить у самой ФС
}

function sysblock(pth,   q) {
  if (pth ~ /[\000-\037]/) return 0
  q = pth; gsub(/'/, "'\"'\"'", q)
  return (system("test -b '" q "'") == 0)
}

# текст для сообщения: без управляющих символов, не длиннее 120 байт,
# без обрубленной UTF-8-последовательности на конце
function clean(t,   i, o, c, len) {
  o = ""; len = length(t)
  for (i = 1; i <= len && length(o) < 120; i++) {
    c = substr(t, i, 1)
    if (c == UNK)     { o = o "?"; continue }
    if (ORD[c] < 32)  { o = o " "; continue }
    o = o c
  }
  if (i <= len) {
    while (length(o) > 0 && ORD[substr(o, length(o), 1)] >= 128) o = substr(o, 1, length(o) - 1)
    o = o "..."
  }
  return o
}
AWK_GUARD_EOF

export GUARD_HOME="${HOME-}" GUARD_USER="${USER-}" GUARD_CWD="$cwd"

run_guard() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 awk "$AWK_GUARD"
  else
    awk "$AWK_GUARD"
  fi
}

reason=$(
  printf '%s' "$input" \
  | jq -j '(.tool_input // {}) | if (.command | type) == "string" then .command else "" end' 2>/dev/null \
  | run_guard 2>/dev/null
) || exit 0

[ -n "$reason" ] || exit 0

full="Заблокировано guard.sh — ${reason}. Операция необратима; если она действительно нужна, выполните её вручную вне агента."
out=$(jq -nc --arg r "$full" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null) \
  || out=""
if [ -z "$out" ]; then
  out='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Заблокировано guard.sh: необратимая операция."}}'
fi
printf '%s\n' "$out"
exit 0
