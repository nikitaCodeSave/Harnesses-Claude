#!/usr/bin/env bash
#
# guard.sh — PreToolUse-хук Claude Code: последний рубеж защиты.
#
# Блокирует ровно один класс — необратимое уничтожение рабочей машины:
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. mkfs* — форматирование блочного устройства;
#   3. запись потока прямо на блочное устройство (dd of=, редирект, tee);
#   4. fork-бомба;
#   5. rm --no-preserve-root.
# Всё остальное — молча пропускается (пустой stdout, exit 0).
#
# Решение принимается по разбору строки так, как её разберёт shell: кавычки,
# комментарии, тела heredoc и содержимое подстановок разбираются отдельно, и
# опасная команда блокируется только когда она стоит в позиции команды.
# Упоминание в аргументе / комментарии / записываемом файле — пропускается.
#
# stdin: {"tool_name":..., "cwd":..., "tool_input":{"command":...}}
# stdout при блокировке: один JSON-объект с permissionDecision=deny.

LC_ALL=C
export LC_ALL

input=$(cat 2>/dev/null)
[ -n "$input" ] || exit 0

# tool_name, cwd — по строке; command идёт последним, т.к. может быть многострочной.
payload=$(printf '%s' "$input" | jq -r '(.tool_name // ""), (.cwd // ""), (.tool_input.command // "")' 2>/dev/null) || exit 0

tool=${payload%%$'\n'*}
[ "$tool" = "Bash" ] || exit 0

rest=${payload#*$'\n'}
cwd=${rest%%$'\n'*}
cmd=${rest#*$'\n'}
[ -n "$cmd" ] || exit 0

AWK_PROG=$(cat <<'GUARD_AWK'
# ---------------------------------------------------------------- лексер + анализ
# Вход: текст команды (все строки склеиваются в TXT).
# Выход: одна строка — причина блокировки, либо ничего.
#
# Маркеры внутри значения слова:
#   \001 — раскрытие в $HOME / ~
#   \002 — раскрытие с неизвестным значением ($VAR, $(...), `...`)
#   \003 — граница снятых кавычек (только в скелете SKEL)

BEGIN {
    MH = "\001"; MU = "\002"; MQ = "\003"
    HOMEDIR = ENVIRON["GUARD_HOME"]
    CURCWD  = ENVIRON["GUARD_CWD"]
    if (HOMEDIR != "/") sub(/\/+$/, "", HOMEDIR)
    if (substr(CURCWD, 1, 1) != "/") CURCWD = ""
    # спецсимволы вне кавычек / внутри двойных кавычек
    SPECU  = " \t\n#'\"\\$`|&;<>(){}~"
    RESPECU = "[ \t\n#'\"\\\\$`|&;<>(){}~]"
    SPECD  = "\"\\$`"
    RESPECD = "[\"\\\\$`]"
    QN = 0; QI = 0; SKN = 0; SB = ""; BLOCKED = ""
}

{ sub(/\r$/, ""); TXT = TXT $0 "\n" }

END {
    enqueue(TXT)
    while (QI < QN && BLOCKED == "") { QI++; scan(Q[QI]) }
    if (BLOCKED == "") forkbomb()
    if (BLOCKED != "") print BLOCKED
}

function BLOCK(msg) { if (BLOCKED == "") BLOCKED = msg }

function enqueue(t) { if (t != "" && QN < 200) Q[++QN] = t }

function skel_add(t) { SB = SB t; if (length(SB) > 4096) { SKA[++SKN] = SB; SB = "" } }

function addstr(t) { WV = WV t; INWORD = 1 }

function basename(p,   i) {
    i = length(p)
    while (i > 0 && substr(p, i, 1) != "/") i--
    return (i > 0) ? substr(p, i + 1) : p
}

# читаемое представление значения для текста причины
function show(a,   i) {
    while ((i = index(a, MH)) > 0) a = substr(a, 1, i - 1) "$HOME" substr(a, i + 1)
    while ((i = index(a, MU)) > 0) a = substr(a, 1, i - 1) "?" substr(a, i + 1)
    gsub(/[\n\r\t]/, " ", a)
    if (length(a) > 80) a = substr(a, 1, 80) "..."
    return a
}

# быстрый проход по обычным символам (иначе на десятках КБ посимвольный цикл дорог)
function fastcopy(s, p, re, sk,   chunk, r, t) {
    chunk = substr(s, p, 1024)
    r = match(chunk, re)
    if (r == 0) t = chunk
    else if (r == 1) return p
    else t = substr(chunk, 1, r - 1)
    addstr(t)
    if (sk) skel_add(t)
    return p + length(t)
}

# ---------------------------------------------------------------- основной лексер
function scan(s,   n, p, c, nx, j, k, np, user) {
    n = length(s); p = 1
    AN = 0; WV = ""; INWORD = 0; PENDRED = 0; PENDHD = 0; REDOUT = 0; HDN = 0; HDEXEC = 0
    skel_add(MQ)
    while (p <= n) {
        if (BLOCKED != "") return
        c = substr(s, p, 1)

        if (index(SPECU, c) == 0) {
            np = fastcopy(s, p, RESPECU, 1)
            if (np > p) { p = np; continue }
            addstr(c); skel_add(c); p++; continue
        }

        if (c == " " || c == "\t") { endword(); skel_add(" "); p++; continue }

        if (c == "\n") {
            endword(); finish_cmd(); skel_add("\n")
            p = eat_hd(s, p + 1)
            continue
        }

        if (c == "#") {
            if (INWORD) { addstr(c); skel_add(c); p++; continue }
            j = index(substr(s, p), "\n")
            if (j == 0) p = n + 1; else p = p + j - 1
            continue
        }

        if (c == "'") {
            INWORD = 1
            j = index(substr(s, p + 1), "'")
            if (j == 0) { addstr(substr(s, p + 1)); p = n + 1 }
            else { addstr(substr(s, p + 1, j - 1)); p = p + j + 1 }
            skel_add(MQ); continue
        }

        if (c == "\"") { INWORD = 1; p = dq(s, p + 1); continue }

        if (c == "$") { p = dollar(s, p, 0); continue }

        if (c == "`") { p = btick(s, p); continue }

        if (c == "\\") {
            nx = substr(s, p + 1, 1)
            if (nx == "\n") { p += 2; continue }
            if (nx == "") { addstr("\\"); skel_add("\\"); p++; continue }
            addstr(nx); skel_add(MQ); p += 2; continue
        }

        if (c == "~") {
            if (!INWORD) {
                k = p + 1
                while (k <= n && substr(s, k, 1) ~ /[A-Za-z0-9_.-]/) k++
                user = substr(s, p + 1, k - p - 1)
                nx = substr(s, k, 1)
                if (nx == "" || nx == "/" || index(SPECU, nx) > 0) {
                    if (user == "") addstr(MH)
                    else if (user == "root") addstr("/root")
                    else addstr("/home/" user)
                    skel_add(MQ); p = k; continue
                }
            }
            addstr("~"); skel_add("~"); p++; continue
        }

        if (c == ";") {
            endword(); finish_cmd(); skel_add(";"); p++
            if (substr(s, p, 1) == ";") p++
            if (substr(s, p, 1) == "&") p++
            continue
        }

        if (c == "&") {
            nx = substr(s, p + 1, 1)
            if (nx == ">") {                     # &> / &>>
                endword(); skel_add("&>"); p += 2
                if (substr(s, p, 1) == ">") p++
                PENDRED = 1; REDOUT = 1; continue
            }
            endword(); finish_cmd(); skel_add("&"); p++
            if (nx == "&") p++
            continue
        }

        if (c == "|") {
            endword(); finish_cmd(); skel_add("|"); p++
            nx = substr(s, p, 1)
            if (nx == "|" || nx == "&") p++
            continue
        }

        if (c == "(" || c == ")") { endword(); finish_cmd(); skel_add(c); p++; continue }

        if (c == "{" || c == "}") {
            nx = substr(s, p + 1, 1)
            if (!INWORD && (c == "}" || nx == "" || nx == " " || nx == "\t" || nx == "\n")) {
                endword(); finish_cmd(); skel_add(c); p++; continue
            }
            addstr(c); skel_add(c); p++; continue
        }

        if (c == "<") {
            if (INWORD && WV ~ /^[0-9]+$/) { WV = ""; INWORD = 0 }
            if (substr(s, p + 1, 1) == "<") {
                if (substr(s, p + 2, 1) == "<") {   # here-string: слово — данные, не файл
                    endword(); skel_add("<<<"); PENDRED = 0; p += 3; continue
                }
                endword(); skel_add("<<"); p += 2
                if (substr(s, p, 1) == "-") { HDSTRIPNEXT = 1; p++ } else HDSTRIPNEXT = 0
                PENDHD = 1; continue
            }
            endword(); skel_add("<"); p++
            if (substr(s, p, 1) == ">") p++
            PENDRED = 1; REDOUT = 0; continue
        }

        if (c == ">") {
            if (INWORD && WV ~ /^[0-9]+$/) { WV = ""; INWORD = 0 }
            endword(); skel_add(">"); p++
            if (substr(s, p, 1) == ">") p++
            else if (substr(s, p, 1) == "|") p++
            if (substr(s, p, 1) == "&") {            # >&2, >&- — дублирование fd
                p++
                while (substr(s, p, 1) ~ /[0-9]/) p++
                if (substr(s, p, 1) == "-") p++
                continue
            }
            PENDRED = 1; REDOUT = 1; continue
        }

        addstr(c); skel_add(c); p++
    }
    endword(); finish_cmd()
}

# внутри двойных кавычек
function dq(s, p,   n, c, nx, np) {
    n = length(s)
    while (p <= n) {
        c = substr(s, p, 1)
        if (index(SPECD, c) == 0) {
            np = fastcopy(s, p, RESPECD, 0)
            if (np > p) { p = np; continue }
            addstr(c); p++; continue
        }
        if (c == "\"") { skel_add(MQ); return p + 1 }
        if (c == "\\") {
            nx = substr(s, p + 1, 1)
            if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { addstr(nx); p += 2; continue }
            if (nx == "\n") { p += 2; continue }
            addstr(c); p++; continue
        }
        if (c == "$") { p = dollar(s, p, 1); continue }
        if (c == "`") { p = btick(s, p); continue }
    }
    skel_add(MQ)
    return p
}

# $... — подстановки; p указывает на '$'
function dollar(s, p, indq,   n, nx, k, name, e, inner, arith, c2) {
    n = length(s)
    nx = substr(s, p + 1, 1)

    if (nx == "(") {
        arith = (substr(s, p + 2, 1) == "(")
        e = findclose(s, p + 2)
        if (!arith) enqueue(substr(s, p + 2, e - p - 2))
        addstr(MU); skel_add(MQ)
        return e + 1
    }
    if (nx == "{") {
        e = findbrace(s, p + 2)
        inner = substr(s, p + 2, e - p - 2)
        if (inner == "HOME") addstr(MH); else addstr(MU)
        skel_add(MQ)
        return e + 1
    }
    if (nx ~ /[A-Za-z_]/) {
        k = p + 1
        while (k <= n && substr(s, k, 1) ~ /[A-Za-z0-9_]/) k++
        name = substr(s, p + 1, k - p - 1)
        if (name == "HOME") addstr(MH); else addstr(MU)
        skel_add(MQ)
        return k
    }
    if (nx == "'" && !indq) {                       # $'...' — ANSI-C
        INWORD = 1
        k = p + 2
        inner = ""
        while (k <= n) {
            c2 = substr(s, k, 1)
            if (c2 == "\\") { inner = inner c2 substr(s, k + 1, 1); k += 2; continue }
            if (c2 == "'") { k++; break }
            inner = inner c2; k++
        }
        addstr(ansic(inner)); skel_add(MQ)
        return k
    }
    if (nx == "\"" && !indq) { INWORD = 1; return dq(s, p + 2) }
    if (nx ~ /[0-9@*?!#-]/ || nx == "$") { addstr(MU); skel_add(MQ); return p + 2 }
    addstr("$"); skel_add("$")
    return p + 1
}

# минимальное раскрытие ANSI-C escape-последовательностей
function ansic(t,   out, i, c, h, o) {
    out = ""; i = 1
    while (i <= length(t)) {
        c = substr(t, i, 1)
        if (c != "\\") { out = out c; i++; continue }
        c = substr(t, i + 1, 1)
        i += 2
        if (c == "n") out = out "\n"
        else if (c == "t") out = out "\t"
        else if (c == "r") out = out "\r"
        else if (c == "\\") out = out "\\"
        else if (c == "'") out = out "'"
        else if (c == "\"") out = out "\""
        else if (c == "x") {
            h = ""
            while (length(h) < 2 && substr(t, i, 1) ~ /[0-9A-Fa-f]/) { h = h substr(t, i, 1); i++ }
            if (h != "") out = out chr(hex2dec(h))
        }
        else if (c ~ /[0-7]/) {
            o = c
            while (length(o) < 3 && substr(t, i, 1) ~ /[0-7]/) { o = o substr(t, i, 1); i++ }
            out = out chr(oct2dec(o))
        }
        else out = out c
    }
    return out
}
function hex2dec(h,   i, c, v, d) {
    v = 0
    for (i = 1; i <= length(h); i++) {
        c = tolower(substr(h, i, 1))
        d = index("0123456789abcdef", c) - 1
        v = v * 16 + d
    }
    return v
}
function oct2dec(o,   i, v) {
    v = 0
    for (i = 1; i <= length(o); i++) v = v * 8 + (substr(o, i, 1) + 0)
    return v
}
function chr(n) {
    if (n <= 0 || n > 255) return ""
    return sprintf("%c", n)
}

# `...`
function btick(s, p,   n, j, inner) {
    n = length(s)
    j = index(substr(s, p + 1), "`")
    if (j == 0) { addstr(MU); skel_add(MQ); return n + 1 }
    inner = substr(s, p + 1, j - 1)
    gsub(/\\/, "", inner)
    enqueue(inner)
    addstr(MU); skel_add(MQ)
    return p + j + 1
}

# p — сразу после открывающей '('; возвращает индекс парной ')'
function findclose(s, p,   n, c, d, j) {
    n = length(s); d = 1
    while (p <= n) {
        c = substr(s, p, 1)
        if (c == "\\") { p += 2; continue }
        if (c == "'") { j = index(substr(s, p + 1), "'"); if (j == 0) return n + 1; p += j + 1; continue }
        if (c == "\"") { p = skipdq(s, p + 1); continue }
        if (c == "(") { d++; p++; continue }
        if (c == ")") { d--; if (d == 0) return p; p++; continue }
        p++
    }
    return n + 1
}
function findbrace(s, p,   n, c, d, j) {
    n = length(s); d = 1
    while (p <= n) {
        c = substr(s, p, 1)
        if (c == "\\") { p += 2; continue }
        if (c == "'") { j = index(substr(s, p + 1), "'"); if (j == 0) return n + 1; p += j + 1; continue }
        if (c == "{") { d++; p++; continue }
        if (c == "}") { d--; if (d == 0) return p; p++; continue }
        p++
    }
    return n + 1
}
function skipdq(s, p,   n, c) {
    n = length(s)
    while (p <= n) {
        c = substr(s, p, 1)
        if (c == "\\") { p += 2; continue }
        if (c == "\"") return p + 1
        p++
    }
    return n + 1
}

# завершение слова: делимитр heredoc / цель редиректа / очередной аргумент
function endword(   a) {
    if (!INWORD) return
    a = WV; WV = ""; INWORD = 0
    if (PENDHD) { HDN++; HD[HDN] = a; HDS[HDN] = HDSTRIPNEXT; PENDHD = 0; return }
    if (PENDRED) {
        PENDRED = 0
        if (REDOUT && is_device(a)) BLOCK("запись потока прямо на блочное устройство: перенаправление вывода в " show(a))
        return
    }
    if (AN == 0 && a ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return       # префикс-присваивание
    A[++AN] = a
}

# Тела heredoc — данные, а не команды, и лексером не разбираются.
# Исключение: `bash <<EOF` без операндов — тело реально исполняется как скрипт.
function eat_hd(s, p,   n, i, j, line, t, body) {
    if (HDN == 0) { HDEXEC = 0; return p }
    n = length(s)
    for (i = 1; i <= HDN; i++) {
        body = ""
        while (p <= n) {
            j = index(substr(s, p), "\n")
            if (j == 0) { line = substr(s, p); p = n + 1 } else { line = substr(s, p, j - 1); p = p + j }
            t = line
            if (HDS[i]) sub(/^\t+/, "", t)
            if (t == HD[i]) break
            if (HDEXEC) body = body line "\n"
        }
        if (HDEXEC) enqueue(body)
    }
    HDN = 0; HDEXEC = 0
    return p
}

# ---------------------------------------------------------------- разбор команды
function finish_cmd() {
    if (AN > 0) analyze()
    AN = 0
    PENDRED = 0; PENDHD = 0
}

function analyze(   i, b, k, str) {
    i = 1
    while (i <= AN) {
        b = basename(A[i])
        if (b == "sudo" || b == "doas") {
            i++
            while (i <= AN && substr(A[i], 1, 1) == "-") {
                if (A[i] == "--") { i++; break }
                if (A[i] ~ /^-[ugCpUrtDh]$/) i += 2; else i++
            }
            continue
        }
        if (b == "env") {
            i++
            while (i <= AN && (substr(A[i], 1, 1) == "-" || A[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
            continue
        }
        if (b == "xargs") {
            i++
            while (i <= AN && substr(A[i], 1, 1) == "-") { if (A[i] ~ /^-[IidEnPsa]$/) i += 2; else i++ }
            continue
        }
        if (b == "nice" || b == "ionice" || b == "timeout") {
            i++
            while (i <= AN && substr(A[i], 1, 1) == "-") { if (A[i] ~ /^-[ncpstk]$/) i += 2; else i++ }
            if (b == "timeout" && i <= AN && A[i] ~ /^[0-9]/) i++
            continue
        }
        if (b == "command" || b == "builtin" || b == "exec" || b == "nohup" || b == "setsid" ||
            b == "stdbuf" || b == "unbuffer" || b == "time") {
            i++
            while (i <= AN && substr(A[i], 1, 1) == "-") i++
            continue
        }
        if (b == "if" || b == "then" || b == "else" || b == "elif" || b == "fi" || b == "do" ||
            b == "done" || b == "while" || b == "until" || b == "case" || b == "esac" ||
            b == "function" || b == "!" || b == "{" || b == "}") { i++; continue }
        break
    }
    if (i > AN) return

    b = basename(A[i])

    if (b == "rm") { check_rm(i + 1); return }
    if (b ~ /^mkfs/) { BLOCK("форматирование блочного устройства: " show(A[i]) target_of(i + 1)); return }
    if (b == "dd") {
        for (k = i + 1; k <= AN; k++)
            if (substr(A[k], 1, 3) == "of=" && is_device(substr(A[k], 4)))
                BLOCK("запись потока прямо на блочное устройство: dd " show(A[k]))
        return
    }
    if (b == "tee") {
        for (k = i + 1; k <= AN; k++)
            if (substr(A[k], 1, 1) != "-" && is_device(A[k]))
                BLOCK("запись потока прямо на блочное устройство: tee " show(A[k]))
        return
    }
    if (b == "cd" || b == "pushd") { do_cd(i + 1); return }
    if (b == "bash" || b == "sh" || b == "zsh" || b == "dash" || b == "ksh" || b == "ash") {
        # -c <script> — строка реально исполняется, разбираем её отдельно
        for (k = i + 1; k <= AN; k++) {
            if (A[k] == "--") { k++; break }
            if (substr(A[k], 1, 1) == "-" && length(A[k]) > 1) {
                if (index(A[k], "c") > 0 && k < AN) { enqueue(A[k + 1]); return }
                continue
            }
            break
        }
        # операндов нет — скрипт придёт со stdin, т.е. из тела heredoc этой строки
        if (k > AN) HDEXEC = 1
        return
    }
    if (b == "eval") {
        str = ""
        for (k = i + 1; k <= AN; k++) str = str " " A[k]
        enqueue(str); return
    }
    if (b == "su") {
        for (k = i + 1; k < AN; k++)
            if (A[k] == "-c" || A[k] == "--command") { enqueue(A[k + 1]); return }
        return
    }
}

function target_of(k) { return (k <= AN) ? " " show(A[k]) : "" }

function do_cd(k,   t) {
    while (k <= AN && substr(A[k], 1, 1) == "-" && A[k] != "-") k++
    if (k > AN) { CURCWD = HOMEDIR; return }
    t = A[k]
    if (t == "-" || index(t, MU) > 0 || t ~ /[*?[]/) { CURCWD = ""; return }
    t = subst_home(t)
    if (index(t, MH) > 0) { CURCWD = ""; return }
    CURCWD = normpath(t)
}

function check_rm(k,   j, a, rec, endo, tn, T, r) {
    rec = 0; endo = 0; tn = 0
    for (j = k; j <= AN; j++) {
        a = A[j]
        if (!endo) {
            if (a == "--") { endo = 1; continue }
            if (substr(a, 1, 2) == "--") {
                if (a == "--recursive") rec = 1
                else if (a == "--no-preserve-root") {
                    BLOCK("снятие защиты корня у rm: --no-preserve-root")
                    return
                }
                continue
            }
            if (substr(a, 1, 1) == "-" && length(a) > 1) {
                if (substr(a, 2) ~ /[rR]/) rec = 1
                continue
            }
        }
        T[++tn] = a
    }
    if (!rec) return
    for (j = 1; j <= tn; j++) {
        r = rm_target_verdict(T[j])
        if (r != "") { BLOCK(r); return }
    }
}

function subst_home(t,   i) {
    if (HOMEDIR == "") return t
    while ((i = index(t, MH)) > 0) t = substr(t, 1, i - 1) HOMEDIR substr(t, i + 1)
    return t
}

# "" — не резолвится (относительный путь при неизвестном cwd)
function normpath(path,   parts, out, i, k, n, res) {
    if (substr(path, 1, 1) != "/") {
        if (CURCWD == "") return ""
        path = CURCWD "/" path
    }
    n = split(path, parts, "/")
    k = 0
    for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (k > 0) k--; continue }
        out[++k] = parts[i]
    }
    res = ""
    for (i = 1; i <= k; i++) res = res "/" out[i]
    return (res == "") ? "/" : res
}

# вердикт по цели рекурсивного rm
function rm_target_verdict(t,   orig, glob, np, what) {
    if (t == "") return ""
    orig = t
    if (index(t, MU) > 0) return ""            # неизвестное раскрытие — не наше дело
    t = subst_home(t)
    if (index(t, MH) > 0) return ""            # $HOME неизвестен
    glob = 0
    if (t == "*" || t == "*/" || t == ".*" || t == "**") { t = "."; glob = 1 }
    else if (t ~ /\/(\*|\.\*|\*\*)\/*$/) {
        sub(/\/(\*|\.\*|\*\*)\/*$/, "", t)
        if (t == "") t = "/"
        glob = 1
    }
    if (t ~ /[*?[]/) return ""                 # прочие шаблоны — не резолвим
    np = normpath(t)
    if (np == "") return ""
    what = ""
    if (np == "/") what = "корня файловой системы"
    else if (HOMEDIR != "" && np == HOMEDIR) what = "домашнего каталога"
    else if (np ~ /^\/(home|Users)\/[^\/]+$/ || np == "/root") what = "домашнего каталога пользователя"
    else if (np == "/home" || np == "/Users") what = "домашних каталогов всех пользователей"
    if (what == "") return ""
    if (glob) return "рекурсивное удаление всего содержимого " what " (rm -r " show(orig) ")"
    return "рекурсивное удаление " what " (rm -r " show(orig) ")"
}

# блочное устройство? безопасные символьные /dev/* исключены
function is_device(v,   rest) {
    if (v == "" || index(v, MU) > 0 || index(v, MH) > 0) return 0
    if (substr(v, 1, 5) != "/dev/") return 0
    rest = substr(v, 6)
    if (rest ~ /^(null|zero|full|random|urandom|stdout|stderr|stdin|console|ptmx|log|tty.*|pts\/.*|fd\/.*|shm\/.*|char\/.*|net\/.*)$/) return 0
    return 1
}

# ---------------------------------------------------------------- fork-бомба
# Ищем по «скелету» (только неквотированный код): NAME(){ ... NAME ... NAME ... & }
function forkbomb(   s, i, p, e, pos, j, name, body) {
    s = ""
    for (i = 1; i <= SKN; i++) s = s SKA[i]
    s = s SB
    gsub(/[ \t\n]+/, "", s)
    p = 1
    while (1) {
        e = index(substr(s, p), "(){")
        if (e == 0) break
        pos = p + e - 1
        j = pos - 1
        while (j >= 1 && substr(s, j, 1) ~ /[A-Za-z0-9_:.-]/) j--
        name = substr(s, j + 1, pos - 1 - j)
        if (name != "") {
            body = brace_body(s, pos + 3)
            if (bomb_body(body, name)) {
                BLOCK("fork-бомба: функция " name "() рекурсивно порождает себя в фоне")
                return
            }
        }
        p = pos + 3
    }
}

function brace_body(s, p,   n, c, d, out) {
    n = length(s); d = 1; out = ""
    while (p <= n) {
        c = substr(s, p, 1)
        if (c == "{") d++
        else if (c == "}") { d--; if (d == 0) return out }
        out = out c
        p++
    }
    return out
}

function bomb_body(body, name,   q, e, pos, prev, nextc, cnt, L) {
    L = length(name)
    cnt = 0; q = 1
    while (1) {
        e = index(substr(body, q), name)
        if (e == 0) break
        pos = q + e - 1
        prev = (pos == 1) ? "" : substr(body, pos - 1, 1)
        nextc = substr(body, pos + L, 1)
        if ((pos == 1 || prev ~ /[;|&({]/) && (nextc == "" || nextc ~ /[;|&)}]/)) cnt++
        q = pos + L
    }
    return (cnt >= 2 && index(body, "&") > 0)
}
GUARD_AWK
)

if command -v timeout >/dev/null 2>&1; then TMO=(timeout -s KILL 4s); else TMO=(); fi

reason=$(printf '%s\n' "$cmd" \
    | GUARD_HOME="${HOME:-}" GUARD_CWD="$cwd" "${TMO[@]}" awk "$AWK_PROG" 2>/dev/null)

if [ -n "$reason" ]; then
    jq -cn --arg r "$reason" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
exit 0
