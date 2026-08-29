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
# подстановок команд, $'...' и раскрытия ~ / $HOME / $PWD. Поэтому упоминание
# опасной команды в аргументе, комментарии или теле heredoc'а не блокируется,
# а `\rm -fr "$HOME"` — блокируется.
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
  for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i

  HOME = ENVIRON["GUARD_HOME"]
  USER = ENVIRON["GUARD_USER"]
  if (HOME != "/") sub(/\/+$/, "", HOME)

  # слова, которые могут стоять перед простой командой
  split("! time then else elif do if while until { } ;; done fi", A, " ")
  for (i in A) RESERVED[A[i]] = 1
  # обёртки: реальная команда идёт после них
  split("sudo doas command builtin exec env nice ionice nohup setsid stdbuf xargs timeout chrt taskset busybox", A, " ")
  for (i in A) WRAP[A[i]] = 1
  # шелл, у которого -c <строка> — это код
  split("sh bash zsh ksh dash ash mksh", A, " ")
  for (i in A) SHELLS[A[i]] = 1
  # устройства, запись в которые безобидна
  split("/dev/null /dev/zero /dev/full /dev/random /dev/urandom /dev/stdin /dev/stdout /dev/stderr /dev/tty /dev/console /dev/ptmx", A, " ")
  for (i in A) DEVSAFE[A[i]] = 1
}

{ SRC = SRC SEP $0; SEP = "\001" }   # NUL-безопасная склейка, если RS встретился

END {
  push_src(SRC, ENVIRON["GUARD_CWD"])
  for (qi = 1; qi <= qn && qi <= 64; qi++) { CWD = qcwd[qi]; scan(qsrc[qi]) }
}

function deny(reason) { print reason; exit 0 }

# ------------------------------ накопление слова ---------------------------
# cwtail — буфер: склейка по символу даёт O(n^2) на длинных словах.
function reset_word() { cwtext = ""; cwtail = ""; cwunk = 0; cwglob = 0; inword = 0 }
function reset_cmd()  { wc = 0 }
function addstr(x)    { cwtail = cwtail x; inword = 1
                        if (length(cwtail) > 256) { cwtext = cwtext cwtail; cwtail = "" } }
function addunk()     { cwunk = 1; addstr(UNK) }
function wordtext()   { if (cwtail != "") { cwtext = cwtext cwtail; cwtail = "" } ; return cwtext }

function endword(   t) {
  if (!inword) return
  t = wordtext()
  if (redir_pending != "") {
    if (redir_pending == "<<" || redir_pending == "<<-") {
      hd_n++; hd_delim[hd_n] = t; hd_strip[hd_n] = (redir_pending == "<<-") ? 1 : 0
    } else if (!cwunk) {
      check_redirect(redir_pending, t)
    }
    redir_pending = ""
  } else {
    wc++; w[wc] = t; u[wc] = cwunk; g[wc] = cwglob
  }
  reset_word()
}

# ------------------------------ сканер -------------------------------------
function scan(src,   c, c2, inner) {
  s = src; n = length(s); p = 1
  reset_cmd(); reset_word()
  hd_n = 0; redir_pending = ""; pdepth = 0
  fn_active = 0; fn_pending = ""; fn_name = ""; fn_depth = 0; fn_self = 0; fn_amp = 0

  while (p <= n) {
    c = substr(s, p, 1)

    if (c == " " || c == "\t" || c == "\r") { endword(); p++; continue }
    if (c == "\n") { endword(); flush_cmd(); p++; consume_heredocs(); continue }

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

    if (c == ";") { endword(); flush_cmd(); p += (substr(s, p + 1, 1) == ";") ? 2 : 1; continue }
    if (c == "|") { endword(); flush_cmd(); c2 = substr(s, p + 1, 1)
                    p += (c2 == "|" || c2 == "&") ? 2 : 1; continue }
    if (c == "&") {
      c2 = substr(s, p + 1, 1)
      if (c2 == ">") { redir_start(); p += 2; if (substr(s, p, 1) == ">") p++
                       redir_pending = "&>"; continue }
      if (fn_active) fn_amp = 1
      endword(); flush_cmd(); p += (c2 == "&") ? 2 : 1; continue
    }
    if (c == "(") {
      endword()
      if ((wc == 1 || (wc == 2 && w[1] == "function")) && fnparen()) {
        fn_pending = w[wc]; reset_cmd(); continue
      }
      flush_cmd(); pdepth++; cwdstack[pdepth] = CWD; p++; continue
    }
    if (c == ")") { endword(); flush_cmd()
                    if (pdepth > 0) { CWD = cwdstack[pdepth]; pdepth-- }
                    p++; continue }

    if (c == ">" || c == "<") {
      if (substr(s, p + 1, 1) == "(") {               # подстановка процесса
        inner = cmdsub(p + 2); push_src(inner, CWD); addunk(); continue
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
    addstr(c); p++
  }
  endword(); flush_cmd()
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

function dollar(indq,   c2, name, j, inner) {
  c2 = substr(s, p + 1, 1)
  if (c2 == "") { addstr("$"); p++; return }
  if (c2 == "'" && !indq) { ansic(); return }
  if (c2 == "\"" && !indq) { p++; dq(); return }
  if (c2 == "(") {
    if (substr(s, p + 2, 1) == "(") { cmdsub(p + 2); addunk(); return }   # $(( ))
    inner = cmdsub(p + 2); push_src(inner, CWD); addunk(); return
  }
  if (c2 == "{") { param(); return }
  if (c2 ~ /[A-Za-z_]/) {
    j = p + 1; name = ""
    while (j <= n && substr(s, j, 1) ~ /[A-Za-z_0-9]/) { name = name substr(s, j, 1); j++ }
    p = j; expand_var(name); return
  }
  addunk(); p += 2                                     # $1 $@ $? $$ ...
}

# ${VAR} раскрываем, ${VAR:-...} и прочее — считаем неизвестным
function param(   depth, body, c, j) {
  j = p + 2; depth = 1; body = ""
  while (j <= n) {
    c = substr(s, j, 1)
    if (c == "\\") { body = body substr(s, j + 1, 1); j += 2; continue }
    if (c == "{") depth++
    else if (c == "}") { depth--; if (depth == 0) { j++; break } }
    body = body c; j++
  }
  p = j
  if (body ~ /^[A-Za-z_][A-Za-z_0-9]*$/) expand_var(body)
  else addunk()
}

function expand_var(name,   v) {
  if (name in VARS)        v = VARS[name]
  else if (name == "PWD")  v = CWD
  else if (name in ENVIRON) v = ENVIRON[name]
  else { addunk(); return }
  if (v == "") { addunk(); return }
  if (index(v, UNK)) cwunk = 1
  addstr(v)
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

function btick(   c, inner) {
  p++; inner = ""
  while (p <= n) {
    c = substr(s, p, 1)
    if (c == "\\") { inner = inner substr(s, p + 1, 1); p += 2; continue }
    if (c == "`") { p++; break }
    inner = inner c; p++
  }
  push_src(inner, CWD); addunk()
}

# тело heredoc'а — данные, а не команды: пропускаем до ограничителя
function consume_heredocs(   i, e, line, t) {
  if (hd_n == 0) return
  for (i = 1; i <= hd_n; i++) {
    while (p <= n) {
      e = index(substr(s, p), "\n")
      if (e == 0) { line = substr(s, p); p = n + 1 } else { line = substr(s, p, e - 1); p = p + e }
      t = line; sub(/\r$/, "", t)
      if (hd_strip[i]) sub(/^\t+/, "", t)
      if (t == hd_delim[i]) break
    }
  }
  hd_n = 0
}

function push_src(str, cw) {
  if (str == "" || qn >= 64) return
  qn++; qsrc[qn] = str; qcwd[qn] = cw
}

# ------------------------------ разбор простой команды ----------------------
function flush_cmd(   i, ci, b, t) {
  endword()
  redir_pending = ""
  if (wc == 0) return

  if (!fn_active && wc >= 2 && w[1] == "function") {     # function name { ... }
    fn_pending = w[2]
    for (i = 1; i <= wc - 2; i++) { w[i] = w[i + 2]; u[i] = u[i + 2]; g[i] = g[i + 2] }
    wc -= 2
    if (wc == 0) return
  }

  for (i = 1; i <= wc; i++) {                          # границы тела функции
    if (w[i] == "{") {
      if (fn_active) fn_depth++
      else if (fn_pending != "") {
        fn_active = 1; fn_name = fn_pending; fn_pending = ""
        fn_depth = 1; fn_self = 0; fn_amp = 0
      }
    } else if (w[i] == "}" && fn_active) {
      fn_depth--
      if (fn_depth <= 0) {
        if (fn_self >= 2 && fn_amp) BOMB[fn_name] = 1
        fn_active = 0
      }
    }
  }

  ci = cmd_index()
  if (ci > 0 && ci <= wc && !u[ci]) {
    t = w[ci]; b = base(t)
    if (fn_active && t == fn_name) fn_self++
    else if (t in BOMB)
      deny("fork-бомба: функция «" clean(t) "» рекурсивно порождает себя в фоне")

    if (b == "rm")                                  check_rm(ci)
    else if (b ~ /^mkfs(\..*)?$/ || b == "mke2fs")  check_mkfs(ci)
    else if (b == "dd")                             check_dd(ci)
    else if (b == "tee")                            check_tee(ci)
    else if (b == "cd")                             do_cd(ci)
    else if (b == "pushd" || b == "popd")           CWD = ""
    else if (b == "eval")                           do_eval(ci)
    else if (b in SHELLS || b == "su")              do_shell_c(ci)
    else if (b == "export" || b == "declare" || b == "typeset" || b == "local") {
      for (i = ci + 1; i <= wc; i++)
        if (!u[i] && w[i] ~ /^[A-Za-z_][A-Za-z_0-9]*=/) record_assign(w[i])
    }
  }
  reset_cmd()
}

# индекс слова с реальным именем команды: пропускает присваивания,
# ключевые слова и обёртки (sudo, env, timeout, ...)
function cmd_index(   i, t, b) {
  i = 1
  while (i <= wc) {
    t = w[i]
    if (!u[i] && t ~ /^[A-Za-z_][A-Za-z_0-9]*=/) { record_assign(t); i++; continue }
    if (t in RESERVED) { i++; continue }
    if (!u[i]) { b = base(t); if (b in WRAP) { i = skip_wrapper(b, i); continue } }
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
  push_src(str, CWD)
}

function do_shell_c(ci,   j) {
  for (j = ci + 1; j < wc; j++)
    if (w[j] == "-c") { push_src(w[j + 1], CWD); return }
}

# ------------------------------ политика ------------------------------------
function check_rm(ci,   j, t, rec, npr, eo, kind) {
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
