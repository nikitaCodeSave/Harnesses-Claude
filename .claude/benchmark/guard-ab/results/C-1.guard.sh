#!/usr/bin/env bash
#
# guard.sh — PreToolUse-хук Claude Code. Последний рубеж защиты.
#
# Блокирует ровно необратимое:
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. mkfs* по реальному блочному устройству;
#   3. запись потока на блочное устройство (dd of=, редирект, tee, cp);
#   4. fork-бомба;
#   5. rm --no-preserve-root.
# Всё остальное пропускает.
#
# Решение принимается по тому, что реально сделает shell: строка разбирается
# настоящим токенизатором (кавычки, escape, комментарии, heredoc, подстановки,
# переменные, word splitting), поэтому упоминание опасной команды в тексте или
# комментарии не блокирует, а `sudo bash -lc "rm -rf /"` или `A=-rf; rm $A /`
# — блокирует.
#
# Fail-open: любая внутренняя ошибка (битый JSON, нет jq, таймаут) => пропуск.
# Хук не должен становиться причиной простоя оператора.

set -u
export LC_ALL=C

# tr отбрасывает NUL: в корректном JSON его быть не может, а подстановка команды
# на нём иначе печатает предупреждение в stderr — хук должен молчать.
payload=$(tr -d '\000') || exit 0
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# tool_name и cwd — однострочные, command может быть многострочной, поэтому она
# идёт последней;  в конце защищает хвостовые переводы строк от $( ).
parsed=$(printf '%s' "$payload" | jq -r '
  def str(f): ((try f catch null) as $v | if ($v|type) == "string" then $v else "" end);
  str(.tool_name), str(.cwd), (str(.tool_input.command) + "")
' 2>/dev/null) || exit 0

tool_name=${parsed%%$'\n'*}
[ "$tool_name" = "Bash" ] || exit 0

rest=${parsed#*$'\n'}
cwd=${rest%%$'\n'*}
cmd=${rest#*$'\n'}
cmd=${cmd%$'\003'}
[ -n "$cmd" ] || exit 0

# Команда идёт в awk через stdin, а не через окружение: одна переменная среды
# ограничена 128 KiB (MAX_ARG_STRLEN), а команды бывают длиннее — иначе крупная
# команда молча осталась бы непроверенной.
reason=$(printf '%s' "$cmd" | G_CWD="$cwd" G_HOME="${HOME:-}" timeout 3 awk '
# ============================== состояние ==================================
# QUEUE    — регионы кода, ожидающие разбора (тело $(...), аргумент bash -c, ...)
# T/TK/TR  — токены текущей простой команды: значение / известно ли значение /
#            роль (0 аргумент, 1 цель записи-редиректа, 2 цель чтения)
# VAR/VARK — известные значения переменных
# FSTACK   — стек открытых { }: имя функции, факт саморекурсии, факт фона
# INF/LBG  — стек циклов: бесконечен ли, порождает ли процессы в фоне
# ===========================================================================

function short(x) { if (length(x) > 80) x = substr(x, 1, 80) "..."; return x }
function base(p)  { sub(/^.*\//, "", p); return p }
function block(r) { if (REASON == "") REASON = r }

# Позиция символа ch в s, начиная с from (0 — нет). Поиск идёт окнами по 512
# байт: копия хвоста на каждой итерации была бы квадратичной на больших вводах.
function find_ch(s, from, n, ch,   p, w) {
  while (from <= n) {
    w = substr(s, from, 512)
    p = index(w, ch)
    if (p > 0) return from + p - 1
    from += 512
  }
  return 0
}

# Значение токена нужно только для сравнения с путями и именами команд, поэтому
# копим не больше TOKMAX; всё длиннее — заведомо не наша цель, помечаем как
# неизвестное, чтобы не сравнивать усечённый префикс.
function addtok(x) {
  if (length(G_tok) + length(x) > TOKMAX) { G_known = 0; return }
  G_tok = G_tok x
}

# Неквотированное раскрытие рвётся на слова по пробелам — ровно поэтому
# A="-rf /"; rm $A выполняет удаление корня, хотя в строке нет "rm -rf /".
function addtok_split(x,   m, a, k) {
  if (x == "") return
  if (x !~ /[ \t\n]/) { addtok(x); G_started = 1; return }
  if (x ~ /^[ \t\n]/) flush_token()
  m = split(x, a, /[ \t\n]+/)
  for (k = 1; k <= m; k++) {
    if (a[k] == "") continue
    if (k > 1) flush_token()
    addtok(a[k]); G_started = 1
  }
  if (x ~ /[ \t\n]$/) flush_token()
}

function enqueue(s) {
  if (s == "" || QN >= 512 || ENQ_BYTES > 4194304) return
  ENQ_BYTES += length(s)
  QUEUE[++QN] = s
}

# Лексическая нормализация пути (без обращения к ФС): . .. // и относительность.
function norm(p, basedir,   n, i, a, m, st, r) {
  if (p == "") return ""
  if (substr(p, 1, 1) != "/") p = basedir "/" p
  n = split(p, a, "/")
  m = 0
  for (i = 1; i <= n; i++) {
    if (a[i] == "" || a[i] == ".") continue
    if (a[i] == "..") { if (m > 0) m--; continue }
    st[++m] = a[i]
  }
  r = ""
  for (i = 1; i <= m; i++) r = r "/" st[i]
  return (r == "") ? "/" : r
}

# Реальное блочное устройство этой машины? Решает не префикс /dev/, а то, чем
# путь на самом деле является: /dev/tcp — виртуальный сокет bash, /dev/ttyUSB0 и
# /dev/st0 — последовательный порт и лента, /dev/loop0 и /dev/nbd0 — файлы-образы.
# Ни одно из них не «рабочая машина», и запись туда — штатная работа.
function is_device(p,   b) {
  if (p !~ /^\/dev\//) return 0
  b = substr(p, 6)
  if (b ~ /^(tcp|udp)\//) return 0
  if (b ~ /^(loop|nbd|ram|zram)/) return 0
  if (b == "mapper/control") return 0
  if (b ~ /^(sd|hd|vd|xvd|nvme|mmcblk|sr[0-9]|scd|dm-|md[0-9]|pmem|mtdblock|dasd|ubiblock)/) return 1
  if (b ~ /^(mapper|disk|block|cciss|md)\//) return 1
  if (!PARTS_LOADED) load_parts()
  return (b in PARTS)
}

# Имена блочных устройств машины. Читается один раз и только при необходимости:
# то, чего в этом списке нет, редиректом не затирается — создастся обычный файл.
function load_parts(   line, a, n) {
  PARTS_LOADED = 1
  while ((getline line < "/proc/partitions") > 0) {
    n = split(line, a, " ")
    if (n >= 4 && a[1] ~ /^[0-9]+$/) PARTS[a[4]] = 1
  }
  close("/proc/partitions")
}

# Может ли glob-шаблон раскрыться ровно в путь target (* и ? не пересекают "/")?
# Так ловится rm -rf "$HOME"* — шаблон совпадает с самим домашним каталогом.
function glob_match(p, target,   re, i, n, c) {
  n = length(p)
  if (n > 512 || index(p, "[") > 0) return 0
  re = "^"
  for (i = 1; i <= n; i++) {
    c = substr(p, i, 1)
    if (c == "*") re = re "[^/]*"
    else if (c == "?") re = re "[^/]"
    else if (c == "\\") { i++; re = re "\\" substr(p, i, 1) }
    else if (index(".^$+(){}|]", c) > 0) re = re "\\" c
    else re = re c
  }
  return (target ~ (re "$"))
}

# Позиция закрывающей скобки, парной к s[i] == "(" ; кавычки не считаются.
function find_paren_end(s, i, n,   depth, ch, pos) {
  depth = 0
  while (i <= n) {
    ch = substr(s, i, 1)
    if (ch == "\\") { i += 2; continue }
    if (ch == SQ) {
      pos = find_ch(s, i + 1, n, SQ)
      if (pos == 0) return n
      i = pos + 1
      continue
    }
    if (ch == DQ) { i = skip_dq(s, i, n); continue }
    if (ch == "(") depth++
    else if (ch == ")") { depth--; if (depth == 0) return i }
    i++
  }
  return n
}

function skip_dq(s, i, n,   ch) {
  i++
  while (i <= n) {
    ch = substr(s, i, 1)
    if (ch == "\\") { i += 2; continue }
    if (ch == DQ) return i + 1
    i++
  }
  return n + 1
}

# --------------------------- переменные ------------------------------------
# Пользовательское присваивание важнее окружения: после HOME=/tmp/x настоящий
# домашний каталог уже не подставляется.
function varval(nm) {
  EXT = ""; EXK = 0
  if (nm in VARK) { if (VARK[nm]) { EXT = VAR[nm]; EXK = 1 } return }
  if (nm == "HOME") { if (HOMED != "") { EXT = HOMED; EXK = 1 } return }
  if (nm == "PWD") { EXT = CWD; EXK = 1; return }
}

# ${V}, ${V:?msg}, ${V:=d}, ${V:-d}, ${V%суффикс}, ${V#префикс} дают ровно
# значение переменной — тот же путь, что и голое $V. Остальные формы
# (${#V}, ${V/a/b}, ${V:+x}, ${V:1:2}) считаем неизвестными.
function parse_brace(t,   nm, rest, v, pat) {
  EXT = ""; EXK = 0
  if (t !~ /^[A-Za-z_]/) return
  nm = t
  sub(/[^A-Za-z0-9_].*$/, "", nm)
  rest = substr(t, length(nm) + 1)
  varval(nm)
  if (!EXK || rest == "") return
  v = EXT
  EXT = ""; EXK = 0
  if (rest ~ /^:?[?=]/) { EXT = v; EXK = 1; return }
  if (rest ~ /^:?-/) { if (v != "") { EXT = v; EXK = 1 } return }
  if (rest ~ /^[%#]/) {
    pat = rest
    sub(/^(%%?|##?)/, "", pat)
    if (pat == "" || pat ~ /[*?]/ || index(pat, "[") > 0) return
    if (substr(rest, 1, 1) == "%") {
      if (length(pat) <= length(v) && substr(v, length(v) - length(pat) + 1) == pat)
        v = substr(v, 1, length(v) - length(pat))
    } else {
      if (substr(v, 1, length(pat)) == pat) v = substr(v, length(pat) + 1)
    }
    EXT = v; EXK = 1
  }
}

# Значение подстановки команды, когда оно очевидно: $(pwd) — текущий каталог,
# $(echo X) — сам X. Иначе 0: значение неизвестно, гадать нельзя.
function eval_subst(t,   a, q) {
  gsub(/^[ \t\n]+|[ \t\n]+$/, "", t)
  if (t ~ /^(\/(usr\/)?bin\/)?pwd$/ || t ~ /^(\/(usr\/)?bin\/)?pwd +-[PL]$/) { EXT = CWD; return 1 }
  if (t ~ /^(echo|printf)( +-[neE]+)* +[^ \t]+$/) {
    a = t
    sub(/^(echo|printf)( +-[neE]+)* +/, "", a)
    q = substr(a, 1, 1)
    if (q == SQ || q == DQ) {
      if (length(a) < 2 || substr(a, length(a), 1) != q) return 0
      a = substr(a, 2, length(a) - 2)
    }
    if (a ~ /[$`\\*?|&;<>()]/ || index(a, SQ) > 0 || index(a, DQ) > 0) return 0
    EXT = a
    return 1
  }
  return 0
}

# --------------------------- подстановки $... ------------------------------
# Возвращает новую позицию; EXT — литеральный вклад в токен, EXK — известен ли он.
function do_expand(s, i, n,   c2, j, depth, ch, inner) {
  EXT = ""; EXK = 1
  c2 = substr(s, i + 1, 1)
  if (c2 == "(") {
    j = find_paren_end(s, i + 1, n)
    # $((...)) — арифметика, кода в ней нет; $(...) — подстановка команды.
    if (substr(s, i + 2, 1) == "(") { EXK = 0; return j + 1 }
    inner = substr(s, i + 2, j - i - 2)
    enqueue(inner)
    EXK = eval_subst(inner)
    if (!EXK) EXT = ""
    return j + 1
  }
  if (c2 == "{") {
    j = i + 2
    depth = 1
    while (j <= n) {
      ch = substr(s, j, 1)
      if (ch == "{") depth++
      else if (ch == "}") { depth--; if (depth == 0) break }
      j++
    }
    parse_brace(substr(s, i + 2, j - i - 2))
    return j + 1
  }
  if (c2 ~ /[A-Za-z_]/) {
    j = i + 1
    while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_]/) j++
    varval(substr(s, i + 1, j - i - 1))
    return j
  }
  if (c2 == "") { EXT = "$"; return i + 1 }
  if (c2 ~ /[0-9@*?$!#]/) { EXK = 0; return i + 2 }
  EXT = "$"
  return i + 1
}

# Содержимое "..." : литерал, но $(...) и `...` внутри — исполняемый код.
function read_dquote(s, i, n,   c, nx, res, kn, j, inr) {
  res = ""; kn = 1
  i++
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == DQ) { i++; break }
    if (c == "\\") {
      nx = substr(s, i + 1, 1)
      if (nx == DQ || nx == "\\" || nx == "$" || nx == "`") { if (length(res) < TOKMAX) res = res nx; else kn = 0; i += 2; continue }
      if (nx == "\n") { i += 2; continue }
      if (length(res) < TOKMAX) res = res c; else kn = 0
      i++
      continue
    }
    if (c == "$") {
      i = do_expand(s, i, n)
      res = res EXT
      if (!EXK) kn = 0
      continue
    }
    if (c == "`") {
      j = i + 1
      while (j <= n && substr(s, j, 1) != "`") { if (substr(s, j, 1) == "\\") j++; j++ }
      inr = substr(s, i + 1, j - i - 1)
      enqueue(inr)
      if (eval_subst(inr)) res = res EXT; else kn = 0
      i = j + 1
      continue
    }
    if (length(res) < TOKMAX) res = res c; else kn = 0
    i++
  }
  EXT = res; EXK = kn
  return i
}

# Содержимое ANSI-C строки вида $ + одинарные кавычки: нужен только литерал.
function read_ansi(s, i, n,   c, nx, res) {
  res = ""
  i += 2
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == SQ) { i++; break }
    if (c == "\\") {
      nx = substr(s, i + 1, 1)
      if (nx == "n") res = res "\n"
      else if (nx == "t") res = res "\t"
      else res = res nx
      i += 2
      continue
    }
    if (length(res) < TOKMAX) res = res c
    i++
  }
  EXT = res
  return i
}

# ------------------------------- heredoc -----------------------------------
function read_heredoc_delim(s, i, n,   j, c, d, q, pos) {
  j = i + 2
  if (substr(s, j, 1) == "-") j++
  while (j <= n && (substr(s, j, 1) == " " || substr(s, j, 1) == "\t")) j++
  d = ""; q = 0
  while (j <= n) {
    c = substr(s, j, 1)
    if (c == SQ) {
      q = 1
      pos = find_ch(s, j + 1, n, SQ)
      if (pos == 0) { d = d substr(s, j + 1, 256); j = n + 1; break }
      d = d substr(s, j + 1, pos - j - 1); j = pos + 1
      continue
    }
    if (c == DQ) { q = 1; pos = j; j = skip_dq(s, j, n); d = d substr(s, pos + 1, j - pos - 2); continue }
    if (c == "\\") { q = 1; d = d substr(s, j + 1, 1); j += 2; continue }
    if (c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" ||
        c == "<" || c == ">" || c == "(" || c == ")") break
    d = d c; j++
  }
  NPEND++
  PENDD[NPEND] = d
  PENDQ[NPEND] = q
  return j
}

# Тело heredoc — данные, а не код. Исключение: при неквотированном делимитере
# внутри всё же исполняются $(...) и `...`.
function skip_heredocs(s, i, n,   k, d, eol, line, tl, bstart, nx, body, found) {
  for (k = 1; k <= NPEND; k++) {
    d = PENDD[k]
    bstart = i
    found = 0
    while (i <= n) {
      eol = find_ch(s, i, n, "\n")
      if (eol == 0) { line = substr(s, i, n - i + 1); nx = n + 1 } else { line = substr(s, i, eol - i); nx = eol + 1 }
      tl = line
      sub(/^[ \t]+/, "", tl)
      if (line == d || tl == d) { body = substr(s, bstart, i - bstart); i = nx; found = 1; break }
      i = nx
    }
    if (!found) body = substr(s, bstart)
    if (PENDQ[k] == 0 && body != "") extract_subs(body)
  }
  NPEND = 0
  return i
}

function extract_subs(t,   i, n, c, j) {
  n = length(t)
  i = 1
  while (i <= n) {
    c = substr(t, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "$" && substr(t, i + 1, 1) == "(" && substr(t, i + 2, 1) != "(") {
      j = find_paren_end(t, i + 1, n)
      enqueue(substr(t, i + 2, j - i - 2))
      i = j + 1
      continue
    }
    if (c == "`") {
      j = i + 1
      while (j <= n && substr(t, j, 1) != "`") j++
      enqueue(substr(t, i + 1, j - i - 1))
      i = j + 1
      continue
    }
    i++
  }
}

# ------------------------------ токены -------------------------------------
function push_token(t, k) {
  NT++
  T[NT] = t; TK[NT] = k; TR[NT] = REDIR
  REDIR = 0
  # форма "function имя { ... }"
  if (NT == 2 && T[1] == "function") PENDING_FUNC = t
}

function flush_token() {
  if (G_started) { push_token(G_tok, G_known); G_tok = ""; G_started = 0; G_known = 1 }
}

function end_cmd(sep) {
  if (NT > 0) check_cmd()
  NT = 0
  REDIR = 0
  BG = 0
  PREV_SEP = sep
}

# ------------------------------- сканер ------------------------------------
function scan(s,   n, i, c, nx, j, k, inr) {
  n = length(s)
  if (n == 0) return
  NT = 0; REDIR = 0; NPEND = 0; FSP = 0; PENDING_FUNC = ""; PREV_SEP = ""; PIPE_TEXT = ""
  LOOPD = 0; PEND_INF = 0; BG = 0
  G_tok = ""; G_started = 0; G_known = 1
  i = 1
  while (i <= n && REASON == "") {
    c = substr(s, i, 1)

    if (c == " " || c == "\t") { flush_token(); i++; continue }

    if (c == "\\") {
      nx = substr(s, i + 1, 1)
      if (nx == "\n") { i += 2; continue }
      if (nx == "") { i++; continue }
      addtok(nx); G_started = 1
      i += 2
      continue
    }

    if (c == SQ) {
      j = find_ch(s, i + 1, n, SQ)
      if (j == 0) { addtok(substr(s, i + 1, n - i)); i = n + 1 }
      else { addtok(substr(s, i + 1, j - i - 1)); i = j + 1 }
      G_started = 1
      continue
    }

    if (c == DQ) {
      i = read_dquote(s, i, n)
      addtok(EXT)
      if (!EXK) G_known = 0
      G_started = 1
      continue
    }

    if (c == "$") {
      nx = substr(s, i + 1, 1)
      if (nx == SQ) { i = read_ansi(s, i, n); addtok(EXT); G_started = 1; continue }
      if (nx == DQ) { i++; continue }
      i = do_expand(s, i, n)
      if (EXK) addtok_split(EXT)
      else { addtok(EXT); G_known = 0; G_started = 1 }
      continue
    }

    if (c == "`") {
      j = i + 1
      while (j <= n && substr(s, j, 1) != "`") { if (substr(s, j, 1) == "\\") j++; j++ }
      inr = substr(s, i + 1, j - i - 1)
      enqueue(inr)
      if (eval_subst(inr)) addtok_split(EXT)
      else { G_known = 0; G_started = 1 }
      i = j + 1
      continue
    }

    if (c == "#" && !G_started) {
      j = find_ch(s, i, n, "\n")
      i = (j == 0) ? n + 1 : j
      continue
    }

    if (c == "~" && !G_started) {
      nx = substr(s, i + 1, 1)
      if (nx == "" || nx == "/" || nx == " " || nx == "\t" || nx == "\n" ||
          nx == ";" || nx == "&" || nx == "|" || nx == ")" || nx == DQ || nx == SQ) {
        if (HOMED != "") addtok(HOMED); else G_known = 0
        G_started = 1
        i++
        continue
      }
      G_known = 0; G_started = 1
      i++
      continue
    }

    if (c == "\n" || c == ";") {
      flush_token(); end_cmd(";")
      i++
      if (c == "\n" && NPEND > 0) i = skip_heredocs(s, i, n)
      continue
    }

    if (c == "&") {
      nx = substr(s, i + 1, 1)
      if (nx == ">") {
        flush_token()
        REDIR = 1
        i += 2
        if (substr(s, i, 1) == ">") i++
        continue
      }
      flush_token()
      if (nx == "&") { end_cmd("&&"); i += 2; continue }
      # фоновый запуск — признак fork-бомбы в теле функции или цикла
      for (k = 1; k <= FSP; k++) FBG[k] = 1
      BG = 1
      end_cmd("&")
      i++
      continue
    }

    if (c == "|") {
      nx = substr(s, i + 1, 1)
      flush_token()
      if (nx == "|") { end_cmd("||"); i += 2; continue }
      end_cmd("|")
      i += (nx == "&") ? 2 : 1
      continue
    }

    if (c == "(") {
      # "for ((...))" — арифметический цикл, а не подоболочка
      if (!G_started && NT > 0 && T[NT] == "for" && substr(s, i + 1, 1) == "(") {
        j = find_paren_end(s, i, n)
        PEND_INF = (substr(s, i, j - i + 1) ~ /;[ \t]*;/) ? 1 : 0
        NT = 0; REDIR = 0
        i = j + 1
        continue
      }
      # "имя ()" — определение функции; иначе — подоболочка
      if (G_started) {
        j = i + 1
        while (j <= n && (substr(s, j, 1) == " " || substr(s, j, 1) == "\t")) j++
        if (substr(s, j, 1) == ")") {
          PENDING_FUNC = G_tok
          G_tok = ""; G_started = 0; G_known = 1
          NT = 0
          i = j + 1
          continue
        }
      }
      flush_token(); end_cmd("(")
      i++
      continue
    }

    if (c == ")") { flush_token(); end_cmd(")"); i++; continue }

    if (c == "{" && !G_started) {
      nx = substr(s, i + 1, 1)
      if (nx == " " || nx == "\t" || nx == "\n" || nx == "") {
        flush_token(); end_cmd("{")
        FSP++
        FSTACK[FSP] = PENDING_FUNC; FREC[FSP] = 0; FBG[FSP] = 0
        PENDING_FUNC = ""
        i++
        continue
      }
    }

    if (c == "}" && !G_started) {
      flush_token(); end_cmd("}")
      if (FSP > 0) {
        if (FSTACK[FSP] != "" && FREC[FSP] && FBG[FSP])
          block("fork-бомба: функция " short(FSTACK[FSP]) "() рекурсивно порождает себя в фоне")
        FSP--
      }
      i++
      continue
    }

    if (c == ">" || c == "<") {
      # префикс дескриптора (2>, 1>>) — не аргумент команды
      if (G_started && G_tok ~ /^[0-9]+$/) { G_tok = ""; G_started = 0; G_known = 1 }
      else flush_token()
      if (c == "<" && substr(s, i + 1, 1) == "<") {
        if (substr(s, i + 2, 1) == "<") { REDIR = 2; i += 3; continue }
        i = read_heredoc_delim(s, i, n)
        continue
      }
      if (c == ">") {
        REDIR = 1
        i++
        nx = substr(s, i, 1)
        if (nx == ">" || nx == "|" || nx == "&") i++
      } else {
        REDIR = 2
        i++
        if (substr(s, i, 1) == "&") i++
        if (substr(s, i, 1) == ">") { REDIR = 1; i++ }
      }
      continue
    }

    addtok(c); G_started = 1
    i++
  }
  flush_token()
  end_cmd("")
}

# --------------------------- анализ команды --------------------------------
function check_cmd(   i, j, k, t, name, tgt, tmp, prev_pipe, val, xin, viax, nm, st, allas) {
  prev_pipe = PIPE_TEXT
  PIPE_TEXT = ""

  # цели редиректов записи — у любой команды
  for (j = 1; j <= NT; j++) {
    if (TR[j] == 1 && TK[j] && T[j] != "") {
      tgt = norm(T[j], CWD)
      if (is_device(tgt)) {
        block("запись потока напрямую на блочное устройство: " short(T[j]))
        return
      }
    }
  }

  # первое значащее слово команды
  i = 1
  while (i <= NT && TR[i] != 0) i++
  if (i > NT) return

  # ---- каркас циклов: do открывает тело, done закрывает ----
  if (T[i] == "done") {
    if (LOOPD > 0) {
      if (INF[LOOPD] && LBG[LOOPD] && !LSAFE[LOOPD])
        block("fork-бомба: бесконечный цикл безостановочно порождает процессы в фоне")
      LOOPD--
    }
    return
  }
  if (T[i] == "do") {
    LOOPD++
    INF[LOOPD] = PEND_INF; LBG[LOOPD] = 0; LSAFE[LOOPD] = 0
    PEND_INF = 0
    i++
    while (i <= NT && TR[i] != 0) i++
    if (i > NT) return
  }
  if (T[i] == "while" || T[i] == "until") {
    for (j = i + 1; j <= NT; j++) if (TR[j] == 0) break
    t = (j <= NT) ? T[j] : ""
    PEND_INF = ((T[i] == "while" && (t == ":" || t == "true")) ||
                (T[i] == "until" && t == "false")) ? 1 : 0
    i = j
    if (i > NT) return
  }
  if (T[i] == "for") {
    if (i + 2 <= NT && T[i + 2] == "in") bind_loop_var(T[i + 1], i + 3)
    PEND_INF = 0
    return
  }
  if (BG) for (k = 1; k <= LOOPD; k++) LBG[k] = 1

  # ---- чистые присваивания действуют на последующие команды ----
  # (префикс одной команды — HOME=/tmp x — сюда не попадает: он временный)
  st = i
  if (T[st] == "export" || T[st] == "declare" || T[st] == "local" ||
      T[st] == "typeset" || T[st] == "readonly") {
    st++
    # declare -r D=/ — флаги до присваиваний ничего не значат
    while (st <= NT && (TR[st] != 0 || (substr(T[st], 1, 1) == "-" && length(T[st]) > 1))) st++
  }
  allas = (st <= NT)
  for (k = st; k <= NT; k++) {
    if (TR[k] != 0) continue
    if (T[k] !~ /^[A-Za-z_][A-Za-z0-9_]*=/) { allas = 0; break }
  }
  if (allas) {
    for (k = st; k <= NT; k++) {
      if (TR[k] != 0) continue
      nm = T[k]
      sub(/=.*$/, "", nm)
      val = substr(T[k], length(nm) + 2)
      if (TK[k]) { VAR[nm] = val; VARK[nm] = 1 } else VARK[nm] = 0
    }
    return
  }

  # имя команды: пропускаем присваивания-префиксы и ключевые слова
  while (i <= NT) {
    if (TR[i] != 0) { i++; continue }
    t = T[i]
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
    if (t in KEYWORD) { i++; continue }
    break
  }
  if (i > NT) return

  # разворачиваем обёртки: sudo / env / nohup / timeout / xargs / ...
  while (i <= NT) {
    name = base(T[i])
    if (!(name in WRAPPER)) break
    if (name == "xargs") viax = 1
    i++
    while (i <= NT) {
      if (TR[i] != 0) { i++; continue }
      t = T[i]
      if (t == "{}") { i++; continue }
      if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
      if (name == "timeout" && t ~ /^[0-9]+([.][0-9]+)?[smhd]?$/) { i++; continue }
      if (substr(t, 1, 1) != "-" || t == "-") break
      if (index(OPTARG[name], " " t " ") > 0) {
        i++
        while (i <= NT && TR[i] != 0) i++
      }
      i++
    }
    if (i > NT) return
  }
  if (i > NT) return
  name = base(T[i])
  if (name == "busybox" && i < NT) { i++; name = base(T[i]) }

  # аргументы, которые xargs возьмёт из конвейера
  xin = (viax && PREV_SEP == "|") ? prev_pipe : ""

  # саморекурсивный вызов внутри тела функции
  for (k = 1; k <= FSP; k++) if (name != "" && name == FSTACK[k]) FREC[k] = 1
  # цикл с паузой процессы лавинообразно не плодит
  if (name == "sleep" || name == "wait" || name == "read")
    for (k = 1; k <= LOOPD; k++) LSAFE[k] = 1

  if (name == "cd" || name == "pushd") {
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0) continue
      if (T[j] ~ /^-/ && T[j] != "-") continue
      if (TK[j] && T[j] != "" && T[j] != "-") CWD = norm(T[j], CWD)
      return
    }
    if (name == "cd" && HOMED != "") CWD = norm(HOMED, "/")
    return
  }

  # mkfs форматирует то, что ему дали: устройство — беда, файл-образ — работа
  if (name ~ /^mkfs/ || name == "mke2fs") {
    if (name ~ /^(mke2fs|mkfs\.ext[234])$/) {
      for (j = i + 1; j <= NT; j++) if (TR[j] == 0 && T[j] == "-n") return   # сухой прогон
    }
    if (name == "mkfs.xfs") {
      for (j = i + 1; j <= NT; j++) if (TR[j] == 0 && T[j] == "-N") return
    }
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0 || !TK[j] || T[j] == "") continue
      if (substr(T[j], 1, 1) == "-") continue
      if (is_device(norm(T[j], CWD))) {
        block("форматирование блочного устройства: " short(T[i]) " " short(T[j]))
        return
      }
    }
    return
  }

  if (name == "dd") {
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0 || !TK[j]) continue
      if (substr(T[j], 1, 3) == "of=") {
        val = substr(T[j], 4)
        if (val != "" && is_device(norm(val, CWD))) {
          block("dd пишет напрямую на блочное устройство: " short(val))
          return
        }
      }
    }
    return
  }

  # tee и cp пишут в файл-аргумент ровно так же, как редирект
  if (name == "tee") {
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0 || !TK[j] || T[j] == "") continue
      if (substr(T[j], 1, 1) == "-" && T[j] != "-") continue
      if (is_device(norm(T[j], CWD))) {
        block("запись потока напрямую на блочное устройство: tee " short(T[j]))
        return
      }
    }
    return
  }

  if (name == "cp") {
    val = ""
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0) continue
      if (substr(T[j], 1, 1) == "-" && T[j] != "-") continue
      val = TK[j] ? T[j] : ""
    }
    if (val != "" && is_device(norm(val, CWD)))
      block("запись потока напрямую на блочное устройство: cp ... " short(val))
    return
  }

  if (name == "rm") { check_rm(i, xin); return }

  if (name == "find") { check_find(i); return }

  # вложенный код: sh -c / bash -c / su -c / eval / echo ... | sh
  if ((name in SHELLS) || name == "su") {
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0) continue
      if (T[j] ~ /^-[A-Za-z]*c[A-Za-z]*$/) {
        for (k = j + 1; k <= NT; k++) {
          if (TR[k] != 0) continue
          if (TK[k]) enqueue(T[k])
          break
        }
        break
      }
    }
    for (j = i + 1; j <= NT; j++) if (TR[j] == 2 && TK[j]) enqueue(T[j])   # bash <<< "..."
    if (PREV_SEP == "|" && prev_pipe != "") enqueue(prev_pipe)
    return
  }

  if (name == "eval") {
    tmp = ""
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0) continue
      if (!TK[j]) { tmp = ""; break }
      tmp = (tmp == "") ? T[j] : tmp " " T[j]
    }
    enqueue(tmp)
    return
  }

  # trap "код" SIGNAL — код исполнится по сигналу
  if (name == "trap") {
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0) continue
      if (TK[j]) enqueue(T[j])
      break
    }
    return
  }

  if (name == "echo" || name == "printf") {
    tmp = ""
    for (j = i + 1; j <= NT; j++) {
      if (TR[j] != 0) continue
      if (!TK[j]) { tmp = ""; break }
      if (T[j] ~ /^-[neE]+$/) continue
      tmp = (tmp == "") ? T[j] : tmp " " T[j]
    }
    PIPE_TEXT = tmp
    return
  }
}

# for VAR in список — тело выполнится с каждым значением, поэтому связываем
# переменную с самым опасным из них: цикл дойдёт и до него.
function bind_loop_var(nm, start,   k, cano, best, cnt, homec) {
  if (nm !~ /^[A-Za-z_][A-Za-z0-9_]*$/) return
  homec = (HOMED == "") ? "" : norm(HOMED, "/")
  best = ""; cnt = 0
  for (k = start; k <= NT; k++) {
    if (TR[k] != 0) continue
    if (!TK[k]) { VARK[nm] = 0; return }
    cnt++
    if (cnt == 1) best = T[k]
    cano = norm(T[k], CWD)
    if (cano == "/" || (homec != "" && cano == homec)) { best = T[k]; break }
  }
  if (cnt == 0) { VARK[nm] = 0; return }
  VAR[nm] = best; VARK[nm] = 1
}

# Оставить в T[] только вложенную команду, начиная с start и до ; или + .
function shift_tokens(start,   k, m) {
  m = 0
  for (k = start; k <= NT; k++) {
    if (TR[k] == 0 && (T[k] == ";" || T[k] == "+")) break
    m++
    T[m] = T[k]; TK[m] = TK[k]; TR[m] = TR[k]
  }
  NT = m
}

# find удаляет дерево и сам (-delete), и чужими руками (-exec rm -r). Опасно
# ровно тогда, когда набор ничем не сужен: find / -name "*.log" -delete — работа,
# а find / -delete — та же уничтоженная машина, что и rm -rf /.
function check_find(i,   j, k, t, np, deleting, filt, execst, cano, homec, pipe) {
  np = 0; deleting = 0; filt = 0; execst = 0
  j = i + 1
  while (j <= NT) {
    if (TR[j] != 0) { j++; continue }
    t = T[j]
    if (t == "(" || t == "!" || (substr(t, 1, 1) == "-" && length(t) > 1)) break
    if (TK[j] && t != "") FPTH[++np] = t
    j++
  }
  for (; j <= NT; j++) {
    if (TR[j] != 0) continue
    t = T[j]
    if (t == "-delete") { deleting = 1; continue }
    if (t == "-exec" || t == "-execdir" || t == "-ok" || t == "-okdir") {
      if (execst == 0) execst = j + 1
      if (j + 1 <= NT && base(T[j + 1]) == "rm") {
        for (k = j + 2; k <= NT; k++) {
          if (T[k] == ";" || T[k] == "+") break
          if (substr(T[k], 1, 1) == "-" && T[k] ~ /[rR]/) deleting = 1
        }
      }
      # опции вложенной команды — не условия find: перескакиваем через неё
      for (k = j + 1; k <= NT; k++) if (TR[k] == 0 && (T[k] == ";" || T[k] == "+")) break
      j = k
      continue
    }
    if (t == "-maxdepth" || t == "-mindepth" || t == "-type" || t == "-xtype" ||
        t == "-D" || t == "-O") { j++; continue }
    if (t ~ /^-(print0?|printf|ls|depth|xdev|mount|nowarn|warn|follow|daystart|noleaf|H|L|P|a|o|and|or|not)$/) continue
    if (substr(t, 1, 1) == "-") { filt = 1; continue }
  }
  if (np == 0) { np = 1; FPTH[1] = "." }

  homec = (HOMED == "") ? "" : norm(HOMED, "/")
  if (deleting && !filt) {
    for (k = 1; k <= np; k++) {
      cano = norm(FPTH[k], CWD)
      if (cano == "/") {
        block("find без сужающих условий удаляет всё дерево корня файловой системы: find " short(FPTH[k]))
        return
      }
      if (homec != "" && homec != "/" && cano == homec) {
        block("find без сужающих условий удаляет всё дерево домашнего каталога: find " short(FPTH[k]))
        return
      }
    }
  }

  pipe = ""
  if (!filt) for (k = 1; k <= np; k++) pipe = (pipe == "") ? FPTH[k] : pipe " " FPTH[k]

  # вложенная команда -exec исполняется по-настоящему
  if (execst > 0) {
    shift_tokens(execst)
    if (NT > 0) check_cmd()
  }
  PIPE_TEXT = pipe
}

function check_rm(i, xin,   j, k, m, t, rec, nopres, endopt, np, p, last, cano, glob, homec, pat, xa) {
  rec = 0; nopres = 0; endopt = 0; np = 0
  for (j = i + 1; j <= NT; j++) {
    if (TR[j] != 0) continue
    t = T[j]
    if (!endopt && t == "--") { endopt = 1; continue }
    if (!endopt && substr(t, 1, 2) == "--") {
      if (t ~ /^--r/) rec = 1                 # --recursive и его сокращения
      else if (t ~ /^--no-p/) nopres = 1
      continue
    }
    if (!endopt && substr(t, 1, 1) == "-" && length(t) > 1) {
      if (t ~ /[rR]/) rec = 1
      continue
    }
    np++; RP[np] = t; RPK[np] = TK[j]
  }

  # цели, которые придут в rm из конвейера через xargs
  if (xin != "") {
    m = split(xin, xa, /[ \t\n]+/)
    for (k = 1; k <= m; k++) if (xa[k] != "") { np++; RP[np] = xa[k]; RPK[np] = 1 }
  }

  if (nopres) {
    block("rm --no-preserve-root: снята защита корня файловой системы")
    return
  }
  if (!rec) return                            # нерекурсивное удаление дерево не сносит

  homec = (HOMED == "") ? "" : norm(HOMED, "/")
  for (k = 1; k <= np; k++) {
    if (!RPK[k] || RP[k] == "") continue      # значение неизвестно — не гадаем
    p = RP[k]
    glob = 0
    if (index(p, "*") > 0 || index(p, "?") > 0) {
      # шаблон может раскрыться в сам корень или сам дом: rm -rf "$HOME"*
      pat = (substr(p, 1, 1) == "/") ? p : CWD "/" p
      if (glob_match(pat, "/")) {
        block("рекурсивное удаление корня файловой системы по шаблону: rm " short(RP[k]))
        return
      }
      if (homec != "" && homec != "/" && glob_match(pat, homec)) {
        block("рекурсивное удаление домашнего каталога по шаблону: rm " short(RP[k]))
        return
      }
      last = p
      sub(/^.*\//, "", last)
      if (last == "*" || last == "**" || last == ".*" || last == ".[!.]*" || last == ".??*") {
        glob = 1
        if (index(p, "/") == 0) p = "."
        else { sub(/\/[^\/]*$/, "", p); if (p == "") p = "/" }
      } else continue                         # частичный шаблон — цель неизвестна
    }
    cano = norm(p, CWD)
    if (cano == "/") {
      block(glob ? "рекурсивное удаление всего содержимого корня файловой системы: rm " short(RP[k]) \
                 : "рекурсивное удаление корня файловой системы: rm " short(RP[k]))
      return
    }
    if (homec != "" && homec != "/" && cano == homec) {
      block(glob ? "рекурсивное удаление всего содержимого домашнего каталога: rm " short(RP[k]) \
                 : "рекурсивное удаление домашнего каталога: rm " short(RP[k]))
      return
    }
  }
}

function init(   a, n, i) {
  n = split("if then else elif fi while until do done for select case esac in " \
            "function time ! [[ ]] coproc", a, " ")
  for (i = 1; i <= n; i++) KEYWORD[a[i]] = 1

  n = split("sudo doas env nohup setsid stdbuf nice ionice timeout command builtin " \
            "exec xargs unbuffer", a, " ")
  for (i = 1; i <= n; i++) WRAPPER[a[i]] = 1

  n = split("sh bash zsh dash ksh mksh ash busybox", a, " ")
  for (i = 1; i <= n; i++) SHELLS[a[i]] = 1

  # опции обёрток, забирающие отдельный аргумент
  OPTARG["sudo"]    = " -u -g -p -C -h -r -t -T -U --user --group --prompt --host --role --type "
  OPTARG["doas"]    = " -u -C "
  OPTARG["env"]     = " -u -C -S --unset --chdir --split-string "
  OPTARG["timeout"] = " -s -k --signal --kill-after "
  OPTARG["nice"]    = " -n --adjustment "
  OPTARG["ionice"]  = " -c -n -p -P -u "
  OPTARG["xargs"]   = " -I -i -n -L -P -s -E -d -a --replace --max-args --max-lines --max-procs --max-chars --eof --delimiter --arg-file "
  OPTARG["stdbuf"]  = " -i -o -e --input --output --error "
  OPTARG["exec"]    = " -a "
}

BEGIN {
  # RS — последовательность, которой в командах не бывает: весь ввод читается
  # одной записью, без построчной склейки (та была бы квадратичной по объёму).
  RS = "\001\002\003"
  TOKMAX = 8192
  SQ = sprintf("%c", 39)
  DQ = sprintf("%c", 34)
  HOMED = ENVIRON["G_HOME"]
  if (substr(HOMED, 1, 1) != "/" || HOMED == "/") HOMED = ""
  CWD = ENVIRON["G_CWD"]
  if (substr(CWD, 1, 1) != "/") CWD = "/"
  CWD = norm(CWD, "/")
  REASON = ""
  QN = 0
  ENQ_BYTES = 0
  init()
}

{ SRC = SRC $0 }

END {
  enqueue(SRC)
  for (qi = 1; qi <= QN && REASON == ""; qi++) scan(QUEUE[qi])
  if (REASON != "") print REASON
}
' 2>/dev/null)

[ -n "$reason" ] || exit 0

jq -cn --arg r "guard.sh: $reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
  2>/dev/null
exit 0
