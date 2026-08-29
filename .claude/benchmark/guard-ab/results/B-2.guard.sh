#!/usr/bin/env bash
# guard.sh — PreToolUse-хук Claude Code: последний рубеж защиты от катастрофических команд.
#
# Блокируется ровно пять классов (всё остальное пропускается):
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. форматирование блочного устройства (mkfs*);
#   3. запись потока на блочное устройство (dd of=/dev/..., редирект > /dev/...);
#   4. fork-бомба;
#   5. rm --no-preserve-root.
#
# Решение принимается по тому, что реально сделает shell: строка разбирается
# лексером (кавычки, escape-последовательности, комментарии, heredoc, подстановки
# команд), после чего проверяются выделенные простые команды. Упоминание опасной
# команды внутри аргумента, комментария или тела heredoc не блокируется.
#
# Философия отказов: при любой внутренней проблеме (нет jq, битый JSON, таймаут
# разбора) хук молча пропускает вызов. Хук, который начинает блокировать всё
# подряд из-за собственной ошибки, ломает работу оператора сильнее, чем помогает.

LC_ALL=C
export LC_ALL

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
# Edit/Write и любые прочие инструменты — вне политики.
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
case $cwd in /*) ;; *) cwd=$PWD ;; esac

GUARD_HOME=${HOME:-}
GUARD_CWD=$cwd
export GUARD_HOME GUARD_CWD

read -r -d '' AWK_GUARD <<'AWK_PROGRAM_END'
# ---------------------------------------------------------------------------
# Лексер shell + проверка политики. На stdin — текст команды, на stdout —
# одна строка с причиной блокировки (или ничего, если блокировать не нужно).
# ---------------------------------------------------------------------------

BEGIN {
    SQ = "\047"          # одинарная кавычка
    M_DOLLAR = "\001"    # маркеры «этот символ экранирован, shell его не раскроет»
    M_TILDE  = "\002"
    M_STAR   = "\003"
    M_QUEST  = "\004"
    M_BRACK  = "\005"
}

{ TEXT = TEXT $0 "\n" }

END { main() }

function main(   qi, ph) {
    HOME_DIR = ENVIRON["GUARD_HOME"]
    if (HOME_DIR ~ /^\//) HOME_DIR = norm_abs(HOME_DIR); else HOME_DIR = ""
    CWD = ENVIRON["GUARD_CWD"]
    if (CWD ~ /^\//) CWD = norm_abs(CWD); else CWD = ""

    # Каталоги, рекурсивное удаление которых уничтожает машину или дом.
    DANG["/"] = 1
    if (HOME_DIR != "" && HOME_DIR != "/") {
        DANG[HOME_DIR] = 1
        ph = parent(HOME_DIR)
        if (ph == "/home" || ph == "/Users" || ph == "/export/home" || ph == "/var/home")
            DANG[ph] = 1
    }

    QN = 0
    push(TEXT)
    for (qi = 1; qi <= QN && REASON == ""; qi++) analyze(Q[qi])

    if (REASON != "") print clean(REASON)
}

# Очередь текстов на разбор: сама команда плюс строки, которые shell выполнит
# отдельным разбором (sh -c "...", eval "...").
function push(t) {
    if (REASON != "" || t == "" || QN >= 32) return
    QN++
    Q[QN] = t
}

function analyze(s) {
    lex(s)
    walk()
}

# ===========================================================================
# Лексер
# ===========================================================================
# Каждое слово хранится в двух видах:
#   TV — литеральное значение (кавычки сняты) — по нему опознаётся имя команды;
#   TE — то же, но символы, которые shell НЕ будет раскрывать (были в кавычках
#        или экранированы), заменены маркерами — по нему раскрываются ~, $HOME
#        и опознаются настоящие globи.
# Типы токенов: W — слово, R — цель перенаправления, O — оператор.

function addc(lit, ex) { CW = CW lit; CE = CE ex; HASW = 1 }

# символ пришёл из кавычек/escape — раскрытия к нему не применяются
function addq(c,   e) {
    e = c
    if (c == "$") e = M_DOLLAR
    else if (c == "~") e = M_TILDE
    else if (c == "*") e = M_STAR
    else if (c == "?") e = M_QUEST
    else if (c == "[") e = M_BRACK
    addc(c, e)
}

# символ внутри двойных кавычек: $ и ` живые, globи и ~ — нет
function adddq(c) {
    if (c == "~" || c == "*" || c == "?" || c == "[") addq(c)
    else addc(c, c)
}

function wpush() {
    if (!HASW) return
    if (PENDR == "<<" || PENDR == "<<-") {
        HDN++
        HD[HDN] = CW                 # разделитель heredoc: кавычки shell снимает
        HDS[HDN] = (PENDR == "<<-")
        PENDR = ""
    } else if (PENDR != "") {
        NT++; TT[NT] = "R"; TV[NT] = CW; TE[NT] = CE; TR[NT] = PENDR
        PENDR = ""
    } else {
        NT++; TT[NT] = "W"; TV[NT] = CW; TE[NT] = CE; TR[NT] = ""
    }
    CW = ""; CE = ""; HASW = 0
}

function opush(o) {
    wpush()
    PENDR = ""
    NT++; TT[NT] = "O"; TV[NT] = o; TE[NT] = o; TR[NT] = ""
    if (o ~ /[<>]/) PENDR = o        # следующее слово — цель перенаправления
}

function lex(s,   n, i, c, c2, c3, st, sp, j, inner) {
    NT = 0; CW = ""; CE = ""; HASW = 0; PENDR = ""; HDN = 0; BT = 0
    delete TT; delete TV; delete TE; delete TR
    n = length(s)
    i = 1
    st = 0                            # 0 — обычный, 1 — '..', 2 — "..", 3 — $'..'
    sp = 0
    while (i <= n) {
        c = substr(s, i, 1)

        if (st == 1) {                                    # '...' — всё буквально
            if (c == SQ) { st = 0; i++; continue }
            addq(c); i++; continue
        }
        if (st == 3) {                                    # $'...' — escape живут
            if (c == "\\") { addq(substr(s, i + 1, 1)); i += 2; continue }
            if (c == SQ) { st = 0; i++; continue }
            addq(c); i++; continue
        }
        if (st == 2) {                                    # "..."
            if (c == "\"") { st = 0; i++; continue }
            if (c == "\\") {
                c2 = substr(s, i + 1, 1)
                if (c2 == "\n") { i += 2; continue }
                if (c2 == "$" || c2 == "`" || c2 == "\"" || c2 == "\\") { addq(c2); i += 2; continue }
                addq("\\"); i++; continue
            }
            # $ и ` внутри двойных кавычек обрабатываются общим кодом ниже
        }

        # --- общее для st==0 и st==2: подстановки ---
        if (c == "$") {
            c2 = substr(s, i + 1, 1)
            if (c2 == "(") {
                if (substr(s, i + 2, 1) == "(") { i = skip_arith(s, i + 2); continue }
                sp++; STK[sp] = st; st = 0
                opush("$(")                                # содержимое — команда
                i += 2; continue
            }
            if (c2 == "{") {
                j = brace_end(s, i + 2)
                inner = substr(s, i + 2, j - i - 2)
                if (inner ~ /^[A-Za-z_][A-Za-z0-9_]*$/) addc("", "$" inner)
                i = j + 1; continue
            }
            if (st == 0 && c2 == SQ) { st = 3; HASW = 1; i += 2; continue }
            if (st == 0 && c2 == "\"") { st = 2; HASW = 1; i += 2; continue }
            addc("$", "$"); i++; continue
        }
        if (c == "`") {
            if (BT) { BT = 0; if (sp > 0) { st = STK[sp]; sp-- }; opush(")") }
            else { BT = 1; sp++; STK[sp] = st; st = 0; opush("$(") }
            i++; continue
        }
        if (st == 2) { adddq(c); i++; continue }

        # --- дальше только st == 0 ---
        if (c == "\\") {
            c2 = substr(s, i + 1, 1)
            if (c2 == "\n" || c2 == "") { i += 2; continue }   # продолжение строки
            addq(c2); i += 2; continue
        }
        if (c == SQ) { st = 1; HASW = 1; i++; continue }
        if (c == "\"") { st = 2; HASW = 1; i++; continue }
        if (c == " " || c == "\t" || c == "\r") { wpush(); i++; continue }
        if (c == "#" && !HASW) {                              # комментарий до конца строки
            while (i <= n && substr(s, i, 1) != "\n") i++
            continue
        }
        if (c == "\n") {
            opush("\n"); i++
            if (HDN > 0) i = skip_heredocs(s, i)               # тело heredoc — данные
            continue
        }

        c3 = substr(s, i, 3); c2 = substr(s, i, 2)
        if (c3 == "<<-") { opush("<<-"); i += 3; continue }
        if (c3 == "<<<") { opush("<<<"); i += 3; continue }
        if (c3 == "&>>") { opush("&>>"); i += 3; continue }
        if (c2 == "<<") { opush("<<"); i += 2; continue }
        if (c2 == ">>") { opush(">>"); i += 2; continue }
        if (c2 == "&>") { opush("&>"); i += 2; continue }
        if (c2 == ">|") { opush(">|"); i += 2; continue }
        if (c2 == ">&") { opush(">&"); i += 2; continue }
        if (c2 == "<&") { opush("<&"); i += 2; continue }
        if (c2 == "&&") { opush("&&"); i += 2; continue }
        if (c2 == "||") { opush("||"); i += 2; continue }
        if (c2 == "|&") { opush("|&"); i += 2; continue }
        if (c2 == ";;") { opush(";;"); i += 2; continue }
        if (c2 == "<(" || c2 == ">(") {                        # подстановка процесса
            sp++; STK[sp] = st
            opush("$("); i += 2; continue
        }
        if (c == "<" || c == ">" || c == ";" || c == "&" || c == "|") { opush(c); i++; continue }
        if (c == "(") { sp++; STK[sp] = st; opush("("); i++; continue }
        if (c == ")") { if (sp > 0) { st = STK[sp]; sp-- }; opush(")"); i++; continue }
        if ((c == "{" || c == "}") && !HASW) { opush(c); i++; continue }

        addc(c, c); i++
    }
    wpush()
}

# $(( ... )) — арифметика, команд не выполняет: пропускаем до закрывающих скобок
function skip_arith(s, p,   n, depth, c) {
    n = length(s); depth = 2; p++
    while (p <= n) {
        c = substr(s, p, 1)
        if (c == "(") depth++
        else if (c == ")") { depth--; if (depth == 0) return p + 1 }
        p++
    }
    return n + 1
}

function brace_end(s, p,   n) {
    n = length(s)
    while (p <= n && substr(s, p, 1) != "}") p++
    return p
}

# Тело heredoc — это данные, а не команды. Пропускаем до строки-разделителя.
function skip_heredocs(s, i,   k, j, line, rest, n) {
    n = length(s)
    for (k = 1; k <= HDN; k++) {
        while (i <= n) {
            rest = substr(s, i)
            j = index(rest, "\n")
            if (j == 0) { i = n + 1; break }
            line = substr(rest, 1, j - 1)
            i = i + j
            if (HDS[k]) sub(/^\t+/, "", line)
            sub(/\r$/, "", line)
            if (line == HD[k]) break
        }
    }
    HDN = 0
    return i
}

# ===========================================================================
# Обход токенов: выделение простых команд
# ===========================================================================

function is_sep(o) {
    return (o == ";" || o == ";;" || o == "&" || o == "&&" || o == "||" ||
            o == "|" || o == "|&" || o == "(" || o == ")" || o == "{" ||
            o == "}" || o == "$(" || o == "\n")
}

function walk(   i, cn, sdep) {
    VCWD = CWD
    cn = 0; sdep = 0
    for (i = 1; i <= NT && REASON == ""; i++) {
        if (TT[i] == "O") {
            if (is_sep(TV[i])) { if (cn) check_cmd(cn); cn = 0 }
            # cd внутри подоболочки не меняет каталог снаружи
            if (TV[i] == "(" || TV[i] == "$(") { sdep++; SVC[sdep] = VCWD }
            else if (TV[i] == ")" && sdep > 0) { VCWD = SVC[sdep]; sdep-- }
        } else if (TT[i] == "R") {
            check_redir(TR[i], TE[i])
        } else {
            cn++; AW[cn] = TV[i]; AE[cn] = TE[i]
        }
    }
    if (cn && REASON == "") check_cmd(cn)
    if (REASON == "") forkbomb()
}

function base(p) { sub(/^.*\//, "", p); return p }

# Опции обёрток, которые забирают следующее слово как свой аргумент.
function argopt(name, o) {
    if (name == "sudo" || name == "doas") return (o ~ /^-(u|g|p|C|U|r|t|h|D|R|T)$/)
    if (name == "xargs") return (o ~ /^-(I|i|n|P|d|E|e|a|L|l|s)$/)
    if (name == "timeout") return (o ~ /^(-s|-k)$/)
    if (name == "env") return (o ~ /^-u$/)
    if (name == "nice") return (o ~ /^-n$/)
    if (name == "ionice") return (o ~ /^-(c|n|p|P|u)$/)
    if (name == "stdbuf") return (o ~ /^-(i|o|e)$/)
    if (name == "watch") return (o ~ /^(-n|-d)$/)
    return 0
}

function is_wrapper(n) {
    return (n == "sudo" || n == "doas" || n == "nohup" || n == "setsid" ||
            n == "stdbuf" || n == "nice" || n == "ionice" || n == "command" ||
            n == "builtin" || n == "exec" || n == "unbuffer" || n == "time" ||
            n == "timeout" || n == "xargs" || n == "env" || n == "watch" ||
            n == "busybox")
}

function is_kw(w) {
    return (w == "if" || w == "then" || w == "elif" || w == "else" ||
            w == "while" || w == "until" || w == "do" || w == "!" ||
            w == "{" || w == "}" || w == "coproc")
}

function check_cmd(cn,   i, j, w, name, script) {
    i = 1
    while (i <= cn) {                                   # префиксные присваивания и ключевые слова
        w = AW[i]
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?=/ || is_kw(w)) { i++; continue }
        break
    }
    while (i <= cn) {                                   # обёртки: sudo, env, xargs, timeout ...
        name = base(AW[i])
        if (!is_wrapper(name)) break
        i++
        while (i <= cn && substr(AW[i], 1, 1) == "-") {
            if (AW[i] == "--") { i++; break }
            if (argopt(name, AW[i])) i += 2; else i++
        }
        while (i <= cn && AW[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) i++
        if (name == "timeout" && i <= cn && AW[i] ~ /^[0-9]/) i++    # длительность
    }
    if (i > cn) return
    name = base(AW[i])

    # Строку, которую shell разберёт заново, ставим в очередь.
    if (name ~ /^(sh|bash|zsh|dash|ksh|ash|su)$/) {
        for (j = i + 1; j < cn; j++)
            if (AW[j] ~ /^-[A-Za-z]*c[A-Za-z]*$/) { push(AW[j + 1]); return }
        return
    }
    if (name == "eval") {
        script = ""
        for (j = i + 1; j <= cn; j++) script = script " " AW[j]
        push(script); return
    }
    if (name == "cd") { track_cd(i, cn); return }

    if (name == "rm") { check_rm(i, cn); return }
    if (name ~ /^mkfs/ || name == "mke2fs") { check_mkfs(i, cn); return }
    if (name == "dd") { check_dd(i, cn); return }
    if (name == "tee") { check_tee(i, cn); return }
    if (name == "find") { check_find(i, cn); return }
}

# Отслеживание cd внутри одной строки: `cd / && rm -rf *` должно решаться по «/».
function track_cd(i, cn,   j, t) {
    t = ""
    for (j = i + 1; j <= cn; j++) {
        if (AW[j] == "-P" || AW[j] == "-L" || AW[j] == "-e" || AW[j] == "-@") continue
        t = AE[j]; break
    }
    if (t == "") { VCWD = HOME_DIR; return }            # cd без аргументов — в дом
    if (t == "-") { VCWD = ""; return }
    t = unmark(expand(t))
    if (t ~ /[$*?]/) { VCWD = ""; return }              # цель неизвестна — не гадаем
    VCWD = norm(t)
}

function check_rm(i, cn,   j, a, rec, nopres, endopt, pn, k) {
    rec = 0; nopres = 0; endopt = 0; pn = 0
    for (j = i + 1; j <= cn; j++) {
        a = AW[j]
        if (!endopt && a == "--") { endopt = 1; continue }
        if (!endopt && a ~ /^--/) {
            if (a == "--recursive") rec = 1
            else if (a == "--no-preserve-root") nopres = 1
            continue
        }
        if (!endopt && a ~ /^-./) { if (a ~ /[rR]/) rec = 1; continue }
        pn++; PATHIDX[pn] = j
    }
    if (nopres) {
        DENY("снятие защиты корня у rm (--no-preserve-root)", frag(i, cn))
        return
    }
    if (!rec) return                                   # нерекурсивное rm дерево не сносит
    for (k = 1; k <= pn; k++) {
        j = PATHIDX[k]
        if (path_danger(AE[j]))
            DENY("рекурсивное удаление " (DANGWHAT == "/" ? "корня файловой системы" : "корня домашнего каталога") " (" DANGWHAT ")", frag(i, cn))
    }
}

function check_mkfs(i, cn,   j, p) {
    for (j = i + 1; j <= cn; j++) {
        p = norm(unmark(expand(AE[j])))
        if (is_dev_danger(p)) { DENY("форматирование блочного устройства " p, frag(i, cn)); return }
    }
}

function check_dd(i, cn,   j, v, p) {
    for (j = i + 1; j <= cn; j++) {
        v = unmark(expand(AE[j]))
        if (v !~ /^of=/) continue
        p = norm(substr(v, 4))
        if (is_dev_danger(p)) { DENY("запись потока прямо на блочное устройство " p " (dd)", frag(i, cn)); return }
    }
}

# `curl img | sudo tee /dev/sda` — та же запись потока на устройство, что и dd.
function check_tee(i, cn,   j, p) {
    for (j = i + 1; j <= cn; j++) {
        if (substr(AW[j], 1, 1) == "-") continue
        p = norm(unmark(expand(AE[j])))
        if (is_dev_danger(p)) { DENY("запись потока прямо на блочное устройство " p " (tee)", frag(i, cn)); return }
    }
}

function check_find(i, cn,   j, del) {
    del = 0
    for (j = i + 1; j <= cn; j++) {
        if (AW[j] == "-delete") del = 1
        else if ((AW[j] == "-exec" || AW[j] == "-execdir") && j + 1 <= cn && base(AW[j + 1]) == "rm") del = 1
    }
    if (!del) return
    for (j = i + 1; j <= cn && substr(AW[j], 1, 1) != "-"; j++)
        if (path_danger(AE[j]))
            DENY("рекурсивное удаление " (DANGWHAT == "/" ? "корня файловой системы" : "корня домашнего каталога") " (" DANGWHAT ", find -delete)", frag(i, cn))
}

function check_redir(op, e,   p) {
    if (op !~ />/) return
    p = norm(unmark(expand(e)))
    if (is_dev_danger(p)) DENY("запись потока прямо на блочное устройство " p " (перенаправление)", "> " p)
}

# ===========================================================================
# Пути и устройства
# ===========================================================================

function unmark(s) {
    gsub(M_DOLLAR, "$", s); gsub(M_TILDE, "~", s)
    gsub(M_STAR, "*", s); gsub(M_QUEST, "?", s); gsub(M_BRACK, "[", s)
    return s
}

# Раскрытие ~, $HOME и $PWD — ровно так, как это сделает shell.
function expand(e) {
    if (HOME_DIR != "") {
        if (e == "~") return HOME_DIR
        if (substr(e, 1, 2) == "~/") e = HOME_DIR substr(e, 2)
        e = subst_var(e, "HOME", HOME_DIR)
    }
    if (VCWD != "") e = subst_var(e, "PWD", VCWD)
    return e
}

function subst_var(e, nm, val,   pre, m, post) {
    while (match(e, "[$][{]?" nm "[}]?")) {
        pre = substr(e, 1, RSTART - 1)
        m = substr(e, RSTART, RLENGTH)
        post = substr(e, RSTART + RLENGTH)
        if (substr(m, length(m), 1) == "}" || post !~ /^[A-Za-z0-9_]/) e = pre val post
        else break                                       # $HOMEDIR — другая переменная
    }
    return e
}

function norm_abs(p) { CWD_SAVE = CWD; CWD = "/"; p = norm(p); CWD = CWD_SAVE; return p }

# Лексическая нормализация пути относительно текущего (виртуального) каталога.
function norm(p,   parts, m, i, k, res) {
    if (p == "") return ""
    if (substr(p, 1, 1) != "/") {
        if (VCWD == "" && CWD == "") return ""
        p = (VCWD != "" ? VCWD : CWD) "/" p
    }
    m = split(p, parts, "/")
    k = 0
    for (i = 1; i <= m; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (k > 0) k--; continue }
        k++; NST[k] = parts[i]
    }
    res = ""
    for (i = 1; i <= k; i++) res = res "/" NST[i]
    return (res == "" ? "/" : res)
}

function parent(p) { sub(/\/[^\/]*$/, "", p); return (p == "" ? "/" : p) }

# Опасен ли путь как цель рекурсивного удаления. DANGWHAT — что именно совпало.
function path_danger(e,   p, glob, d) {
    p = expand(e)
    if (p == "") return 0
    glob = 0
    if (p == "*") { glob = 1; p = "." }                  # rm -rf *  — всё в текущем каталоге
    else if (p ~ /\/\*\/?$/) {                            # rm -rf /*  или  ~/*
        glob = 1
        sub(/\/\*\/?$/, "", p)
        if (p == "") p = "/"
    }
    p = unmark(p)
    d = norm(p)
    if (d == "") return 0
    if (d in DANG) { DANGWHAT = d; return 1 }
    return 0
}

# Псевдоустройства, запись в которые безобидна; всё прочее в /dev — блочные и
# символьные устройства, писать в них потоком катастрофично.
function is_dev_danger(p) {
    if (p !~ /^\/dev\//) return 0
    if (p ~ /^\/dev\/(null|zero|full|random|urandom|tty|console|ptmx|stdin|stdout|stderr)$/) return 0
    if (p ~ /^\/dev\/tty[0-9]+$/) return 0
    if (p ~ /^\/dev\/(fd|pts|shm)\//) return 0
    return 1
}

# ===========================================================================
# Fork-бомба: определение функции, которая порождает саму себя в фоне, и её вызов
# ===========================================================================

function forkbomb(   i, j, nm, depth, k, amp, pipe, fin, inv) {
    for (i = 1; i + 3 <= NT; i++) {
        if (TT[i] != "W" || TV[i] == "") continue
        if (TT[i + 1] != "O" || TV[i + 1] != "(") continue
        if (TT[i + 2] != "O" || TV[i + 2] != ")") continue
        j = i + 3
        while (j <= NT && TT[j] == "O" && TV[j] == "\n") j++
        if (j > NT || TT[j] != "O" || TV[j] != "{") continue
        nm = TV[i]
        depth = 1; k = 0; amp = 0; pipe = 0
        for (j++; j <= NT; j++) {
            if (TT[j] == "O") {
                if (TV[j] == "{") depth++
                else if (TV[j] == "}") { depth--; if (depth == 0) break }
                else if (TV[j] == "&") amp = 1
                else if (TV[j] == "|") pipe = 1
            } else if (TT[j] == "W" && TV[j] == nm) k++
        }
        fin = j
        if (!(k >= 1 && amp && (pipe || k >= 2))) continue
        inv = 0
        for (j = fin + 1; j <= NT; j++) if (TT[j] == "W" && TV[j] == nm) { inv = 1; break }
        if (inv) { DENY("fork-бомба: функция " nm " рекурсивно порождает себя в фоне", frag_tokens(i, fin + 1)); return }
    }
}

# ===========================================================================
# Причина отказа
# ===========================================================================

function frag(i, cn,   s, j) {
    s = AW[i]
    for (j = i + 1; j <= cn; j++) s = s " " AW[j]
    return s
}

function frag_tokens(a, b,   s, j) {
    s = ""
    for (j = a; j <= b && j <= NT; j++) s = s (j > a ? " " : "") TV[j]
    return s
}

function short(s) {
    gsub(/[\n\t\r]/, " ", s)
    if (length(s) > 160) s = substr(s, 1, 160) "..."
    return s
}

function DENY(what, frg) {
    if (REASON != "") return
    REASON = "guard.sh: заблокировано — " what ". Действие необратимо и уничтожает рабочую машину. " \
             "Если оно осознанное, выполните его вручную вне агента. Фрагмент: " short(frg)
}

function clean(s) {
    s = unmark(s)
    gsub("[\001-\010\013\014\016-\037]", " ", s)
    return s
}
AWK_PROGRAM_END

# timeout — страховка от того, что разбор упрётся в 5-секундный лимит хука.
if command -v timeout >/dev/null 2>&1; then
    reason=$(printf '%s\n' "$cmd" | timeout 3s awk "$AWK_GUARD" 2>/dev/null | head -n 1)
else
    reason=$(printf '%s\n' "$cmd" | awk "$AWK_GUARD" 2>/dev/null | head -n 1)
fi

[ -n "$reason" ] || exit 0

jq -nc --arg r "$reason" \
   '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
