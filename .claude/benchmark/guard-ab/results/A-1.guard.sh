#!/usr/bin/env bash
# guard.sh — PreToolUse-хук Claude Code: последний рубеж защиты от катастрофических команд.
#
# Блокируется ровно пять необратимых классов:
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. форматирование блочного устройства (mkfs*);
#   3. запись потока прямо на блочное устройство (dd of=, редирект, tee);
#   4. fork-бомба;
#   5. rm --no-preserve-root.
#
# Решение принимается по разобранной командной строке (лексер shell внутри awk),
# то есть по тому, что реально выполнит shell, а не по внешнему виду строки.
# Всё, что лишь упоминает опасную команду (аргумент, комментарий, heredoc,
# here-string, шаблон поиска), пропускается.

set -u
export LC_ALL=C

# Нет stdin — нечего проверять (защита от подвисания при ручном запуске).
[ -t 0 ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v awk >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
[ -n "$input" ] || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '(try .tool_input.command catch "") // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
case "$cwd" in /*) ;; *) cwd="$PWD" ;; esac

hm="${HOME:-}"
case "$hm" in /*) ;; *) hm=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6) ;; esac
case "$hm" in /*) ;; *) hm="/root" ;; esac

read -r -d '' AWK_PROG <<'AWK_SOURCE_END'
# ---------------------------------------------------------------------------
# Лексер shell + анализатор. На stdin — командная строка, на stdout — находки:
#   D<TAB>причина                — блокировать безусловно
#   Q<TAB>путь<TAB>причина       — блокировать, если путь окажется блочным устройством
# ---------------------------------------------------------------------------

BEGIN {
    SENT = sprintf("%c", 2)          # маркер «значение неизвестно» (подстановка)
    HOME = ENVIRON["GUARD_HOME"]
    CWD  = ENVIRON["GUARD_CWD"]
    if (HOME == "") HOME = "/root"
    if (CWD  == "") CWD  = HOME
    HOME = striptrail(HOME)
    CWD  = striptrail(CWD)
    if (HOME == "") HOME = "/root"
    if (CWD  == "") CWD  = "/"
    NC = 0; AN = 0; NT = 0; QH = 1; QT = 0; RUNID = 0; NL = 0
    seedvars()
}

{ LINES[++NL] = $0 }

END {
    s = ""; b = ""
    for (k = 1; k <= NL; k++) {
        b = b LINES[k] "\n"
        if (length(b) > 8192) { s = s b; b = "" }
    }
    s = s b
    push(s)
    mainloop()
}

function seedvars() {
    VARS["HOME"] = HOME
    VARS["PWD"]  = CWD
    if (ENVIRON["USER"]    != "") VARS["USER"]    = ENVIRON["USER"]
    if (ENVIRON["LOGNAME"] != "") VARS["LOGNAME"] = ENVIRON["LOGNAME"]
}

function push(s) {
    if (s == "" || QT > 40) return
    QS[++QT] = s
}

function mainloop(   guard) {
    guard = 0
    while (QH <= QT && guard++ < 60) {
        RUNID++
        lexstr(QS[QH]); QH++
        analyze()
    }
    detect_forkbomb()
}

# ===========================================================================
# Лексер
# ===========================================================================
# Состояние (глобальное — лексер не реентерабелен, повторные строки идут через очередь):
#   Q     0 вне кавычек, 1 '..', 2 "..", 3 $'..'
#   INW   слово начато
#   WL/WM литерал текущего слова и маска (u — вне кавычек, q — в кавычках, d — подстановка)
#   D     глубина вложенных $( ), `..`, <( )
# ---------------------------------------------------------------------------

function lexstr(s,   n, i, c, c2, nn) {
    Q = 0; INW = 0; WL = ""; WM = ""; WBUF = ""; WBUFM = ""
    D = 0; BN[0] = 0; BRN[0] = 0; PD[0] = 0
    PENDRED = ""; HDPEND = 0; HDSTRIP = 0; HN = 0
    toko("|SEP|")

    n = split(s, CH, "")
    nn = length(s)
    if (n != nn) { for (i = 1; i <= nn; i++) CH[i] = substr(s, i, 1); n = nn }

    i = 1
    while (i <= n) {
        c = CH[i]

        if (Q == 1) {                                    # '....'
            if (c == "'") Q = 0; else addch(c, "q")
            i++; continue
        }
        if (Q == 3) {                                    # $'....'
            if (c == "\\") { addch(ansic(CH[i+1]), "q"); i += 2; continue }
            if (c == "'") { Q = 0; i++; continue }
            addch(c, "q"); i++; continue
        }
        if (Q == 2) {                                    # "...."
            if (c == "\\") {
                c2 = CH[i+1]
                if (c2 == "$" || c2 == "`" || c2 == "\"" || c2 == "\\") { addch(c2, "q"); i += 2; continue }
                if (c2 == "\n") { i += 2; continue }
                addch(c, "q"); i++; continue
            }
            if (c == "\"") { Q = 0; i++; continue }
            if (c == "$")  { i = dodollar(i, n); continue }
            if (c == "`")  { i = dobacktick(i); continue }
            addch(c, "q"); i++; continue
        }

        # --- вне кавычек ---
        if (c == "\\") {
            c2 = CH[i+1]
            if (c2 == "\n") { i += 2; continue }         # перенос строки
            if (i + 1 <= n) { addch(c2, "q"); i += 2; continue }
            addch(c, "u"); i++; continue
        }
        if (c == "'")  { Q = 1; INW = 1; i++; continue }
        if (c == "\"") { Q = 2; INW = 1; i++; continue }
        if (c == "$") {
            c2 = CH[i+1]
            if (c2 == "'") { Q = 3; INW = 1; i += 2; continue }
            if (c2 == "\"") { Q = 2; INW = 1; i += 2; continue }
            i = dodollar(i, n); continue
        }
        if (c == "`") { i = dobacktick(i); continue }
        if (c == "#" && !INW) {                          # комментарий до конца строки
            while (i <= n && CH[i] != "\n") i++
            continue
        }
        if (c == " " || c == "\t" || c == "\r") { endword(); i++; continue }
        if (c == "\n") {
            emitcmd("\n"); i++
            if (HN > 0) i = do_heredocs(i, n)
            continue
        }
        if (c == ";") {
            emitcmd(";")
            i++
            while (i <= n && (CH[i] == ";" || CH[i] == "&")) i++   # ;; ;& ;;&
            continue
        }
        if (c == "&") {
            c2 = CH[i+1]
            if (c2 == ">") {                              # &> / &>>
                endword()
                if (CH[i+2] == ">") { setred("&>>"); i += 3 } else { setred("&>"); i += 2 }
                continue
            }
            if (c2 == "&") { emitcmd("&&"); i += 2; continue }
            emitcmd("&"); i++; continue
        }
        if (c == "|") {
            c2 = CH[i+1]
            if (c2 == "|") { emitcmd("||"); i += 2; continue }
            if (c2 == "&") { emitcmd("|&"); i += 2; continue }
            emitcmd("|"); i++; continue
        }
        if (c == "(") {
            endword(); PD[D]++; emitcmd("("); i++; continue
        }
        if (c == ")") {
            endword()
            if (PD[D] > 0) { PD[D]--; emitcmd(")"); i++; continue }
            if (D > 0 && (FT[D] == "cs" || FT[D] == "ps")) { closeframe(); i++; continue }
            emitcmd(")"); i++; continue
        }
        if (c == ">") {
            fdprefix()
            endword()
            c2 = CH[i+1]
            if (c2 == "(") { openframe("ps"); i += 2; continue }
            if (c2 == ">") { setred(">>"); i += 2; continue }
            if (c2 == "|") { setred(">|"); i += 2; continue }
            if (c2 == "&") { setred(">&"); i += 2; continue }
            setred(">"); i++; continue
        }
        if (c == "<") {
            fdprefix()
            endword()
            c2 = CH[i+1]
            if (c2 == "(") { openframe("ps"); i += 2; continue }
            if (c2 == "<") {
                if (CH[i+2] == "<") { setred("<<<"); i += 3; continue }        # here-string: данные
                HDPEND = 1
                if (CH[i+2] == "-") { HDSTRIP = 1; i += 3 } else { HDSTRIP = 0; i += 2 }
                continue
            }
            if (c2 == "&") { setred("<&"); i += 2; continue }
            setred("<"); i++; continue
        }
        addch(c, "u"); i++
    }
    emitcmd("")
    toko("|SEP|")
}

# «2>» / «10<» — цифровой префикс дескриптора не является аргументом
function fdprefix() {
    wflush()
    if (INW && WL ~ /^[0-9]+$/ && WM ~ /^u+$/) { WL = ""; WM = ""; INW = 0 }
}

function ansic(c) {
    if (c == "n") return "\n"
    if (c == "t") return "\t"
    if (c == "r") return "\r"
    if (c == "0") return " "
    return c
}

function addch(c, m) {
    WBUF = WBUF c; WBUFM = WBUFM m; INW = 1
    if (length(WBUF) >= 256) { WL = WL WBUF; WM = WM WBUFM; WBUF = ""; WBUFM = "" }
}

function wflush() {
    if (WBUF != "") { WL = WL WBUF; WM = WM WBUFM; WBUF = ""; WBUFM = "" }
}

function setred(op) {
    if (PENDRED == "") PENDRED = op
}

function endword(   lit, msk) {
    wflush()
    if (!INW) { WL = ""; WM = ""; return }
    lit = WL; msk = WM
    WL = ""; WM = ""; INW = 0

    if (HDPEND) {                                        # разделитель heredoc
        HN++
        HD[HN] = lit
        HQ[HN] = (msk ~ /q/) ? 1 : 0
        HS[HN] = HDSTRIP
        HDPEND = 0
        return
    }
    if (PENDRED != "") {
        if (PENDRED != "<" && PENDRED != "<&") {
            BRN[D]++; BRT[D, BRN[D]] = lit; BRO[D, BRN[D]] = PENDRED
        }
        PENDRED = ""
        return
    }
    BN[D]++; BW[D, BN[D]] = lit; BM[D, BN[D]] = msk
    tokw(lit)
}

function emitcmd(op,   i) {
    endword()
    if (BN[D] > 0 || BRN[D] > 0) {
        NC++
        CN[NC] = BN[D]; CRUN[NC] = RUNID; CTERM[NC] = op
        for (i = 1; i <= BN[D]; i++) { CW[NC, i] = BW[D, i]; CM[NC, i] = BM[D, i] }
        CRN[NC] = BRN[D]
        for (i = 1; i <= BRN[D]; i++) { CRT[NC, i] = BRT[D, i]; CRO[NC, i] = BRO[D, i] }
        record_assignments(NC)
    }
    BN[D] = 0; BRN[D] = 0
    if (op != "") toko(op)
}

function openframe(t) {
    wflush()
    D++
    FT[D] = t; FWL[D] = WL; FWM[D] = WM; FIN[D] = INW; FQ[D] = Q; FPR[D] = PENDRED
    WL = ""; WM = ""; WBUF = ""; WBUFM = ""; INW = 0; Q = 0; PENDRED = ""
    BN[D] = 0; BRN[D] = 0; PD[D] = 0
}

function closeframe() {
    emitcmd("")
    WL = FWL[D]; WM = FWM[D]; INW = FIN[D]; Q = FQ[D]; PENDRED = FPR[D]
    WBUF = ""; WBUFM = ""
    D--
    addch(SENT, "d")
}

function dobacktick(i) {
    if (D > 0 && FT[D] == "bq") { closeframe(); return i + 1 }
    openframe("bq"); return i + 1
}

# Обработка $... начиная с позиции i (CH[i] == "$"); возвращает новую позицию
function dodollar(i, n,   c2, j, depth, name, inner) {
    c2 = CH[i+1]
    if (c2 == "(") {
        if (CH[i+2] == "(") {                            # $(( арифметика ))
            j = i + 3; depth = 2
            while (j <= n && depth > 0) {
                if (CH[j] == "(") depth++
                else if (CH[j] == ")") depth--
                j++
            }
            addch(SENT, "d")
            return j
        }
        openframe("cs")
        return i + 2
    }
    if (c2 == "{") {
        j = i + 2; depth = 1; inner = ""
        while (j <= n && depth > 0) {
            if (CH[j] == "{") depth++
            else if (CH[j] == "}") { depth--; if (depth == 0) break }
            if (length(inner) < 4096) inner = inner CH[j]
            j++
        }
        if (inner ~ /^[A-Za-z_][A-Za-z0-9_]*$/) expandvar(inner)
        else {
            if (index(inner, "$(") || index(inner, "`")) extract_subs(inner)
            addch(SENT, "d")
        }
        return j + 1
    }
    if (c2 ~ /^[A-Za-z_]$/) {
        name = ""
        j = i + 1
        while (j <= n && CH[j] ~ /^[A-Za-z0-9_]$/) { name = name CH[j]; j++ }
        expandvar(name)
        return j
    }
    if (c2 ~ /^[0-9@*?$!#-]$/) { addch(SENT, "d"); return i + 2 }
    addch("$", (Q == 2) ? "q" : "u")
    return i + 1
}

function expandvar(name,   v, i, c, m, L) {
    if (!(name in VARS)) { addch(SENT, "d"); return }
    v = VARS[name]
    m = (Q == 2) ? "q" : "u"
    if (Q != 2) {
        L = length(v)
        for (i = 1; i <= L; i++) {
            c = substr(v, i, 1)
            if (c == " " || c == "\t" || c == "\n") endword()   # разбиение на слова
            else addch(c, m)
        }
    } else {
        L = length(v)
        for (i = 1; i <= L; i++) addch(substr(v, i, 1), m)
        INW = 1
    }
}

# Тело heredoc — это данные. Возвращает позицию после всех тел.
function do_heredocs(i, n,   k, line, cmp, body, bbuf) {
    for (k = 1; k <= HN; k++) {
        body = ""; bbuf = ""
        while (i <= n) {
            line = ""
            while (i <= n && CH[i] != "\n") { if (length(line) < 8192) line = line CH[i]; i++ }
            if (i <= n) i++
            cmp = line
            if (HS[k]) sub(/^\t+/, "", cmp)
            if (cmp == HD[k]) break
            if (length(body) < 65536) {
                bbuf = bbuf line "\n"
                if (length(bbuf) > 4096) { body = body bbuf; bbuf = "" }
            }
            if (i > n) break
        }
        body = body bbuf
        if (!HQ[k] && body != "" && (index(body, "$(") || index(body, "`"))) extract_subs(body)
        # `bash <<EOF ... EOF` — тело уходит интерпретатору и исполняется
        if (body != "" && cmd_is_shell(NC)) push(body)
    }
    HN = 0
    return i
}

function cmd_is_shell(c,   n, base) {
    if (c < 1 || CRUN[c] != RUNID) return 0
    n = build_argv(c)
    if (n <= 0) return 0
    base = basename(AV[0])
    return (base ~ /^(sh|bash|zsh|dash|ksh|ash|mksh|rbash)$/)
}

# Достаёт подстановки команд из текста-данных (тело heredoc, ${...}) — они исполняются
function extract_subs(b,   i, j, n, depth, inner, c) {
    n = length(b)
    if (n > 65536) n = 65536
    for (i = 1; i <= n; i++) {
        c = substr(b, i, 1)
        if (c == "$" && substr(b, i+1, 1) == "(") {
            depth = 1; j = i + 2
            while (j <= n && depth > 0) {
                c = substr(b, j, 1)
                if (c == "(") depth++
                else if (c == ")") { depth--; if (depth == 0) break }
                j++
            }
            inner = substr(b, i + 2, j - i - 2)
            if (inner != "" && index(inner, "((") != 1) push(inner)
            i = j
        } else if (c == "`") {
            j = i + 1
            while (j <= n && substr(b, j, 1) != "`") j++
            inner = substr(b, i + 1, j - i - 1)
            if (inner != "") push(inner)
            i = j
        }
    }
}

function tokw(v) { NT++; TT[NT] = "w"; TV[NT] = v }
function toko(v) { NT++; TT[NT] = (v == "|SEP|") ? "x" : "o"; TV[NT] = v }

# Запоминание присваиваний: VAR=..., export VAR=..., for VAR in ...
function record_assignments(c,   i, w, p, name, val, start, j, best) {
    start = 1
    if (CN[c] >= 1 && basename(CW[c,1]) ~ /^(export|declare|local|typeset|readonly)$/) start = 2

    if (CN[c] >= 3 && CW[c,1] == "for" && CW[c,3] == "in" && CW[c,2] ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
        best = ""
        for (j = 4; j <= CN[c]; j++) {
            if (CW[c,j] == "do" || CW[c,j] == ";") continue
            if (index(CW[c,j], SENT)) continue
            if (best == "") best = CW[c,j]
            if (is_root_target(CW[c,j], CM[c,j])) { best = CW[c,j]; break }
        }
        if (best != "") VARS[CW[c,2]] = best
        return
    }

    for (i = start; i <= CN[c]; i++) {
        w = CW[c,i]
        p = index(w, "=")
        if (p < 2) { if (i == start) return; else break }
        name = substr(w, 1, p - 1)
        if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) break
        val = substr(w, p + 1)
        if (index(val, SENT) == 0) VARS[name] = val
        if (start == 1 && i == CN[c]) return
    }
}

# ===========================================================================
# Анализ
# ===========================================================================

function analyze(   c) {
    for (c = AN + 1; c <= NC; c++) analyze_cmd(c)
    AN = NC
}

function analyze_cmd(c,   argc, base, i, s) {
    check_redirects(c)
    argc = build_argv(c)
    if (argc <= 0) return
    base = basename(AV[0])
    gsub(SENT, "", base)                  # `${BIN}rm` — имя команды всё равно rm

    if (base == "rm") check_rm(c, argc)
    else if (base ~ /^mkfs(\.[A-Za-z0-9_.+-]+)?$/ || base == "mke2fs") check_mkfs(c, argc)
    else if (base == "dd") check_dd(c, argc)
    else if (base == "tee") check_tee(c, argc)
    else if (base == "cd" || base == "pushd") track_cd(argc)
    else if (base == "eval" || base == "watch") {
        s = ""
        for (i = 1; i < argc; i++) {
            if (base == "watch" && substr(AV[i], 1, 1) == "-") { if (AV[i] ~ /^-[nd]$/) i++; continue }
            s = s (s == "" ? "" : " ") AV[i]
        }
        push(s)
    }
    else if (base == "trap") {                        # действие ловушки исполнит shell
        for (i = 1; i < argc; i++) {
            if (substr(AV[i], 1, 1) == "-") continue
            push(AV[i]); break
        }
    }
    else if (base ~ /^(sh|bash|zsh|dash|ksh|ash|mksh|rbash|su)$/) check_shell(c, argc)
    else if (base ~ /^(perl|python|python2|python3|ruby)$/) check_interp(c, argc)
}

# Раскрытие обёрток (sudo, env, timeout, xargs, …) до настоящей команды
function build_argv(c,   i, n, base, guard, j) {
    n = CN[c]; i = 1; guard = 0; VIAX = 0
    while (i <= n && guard++ < 80) {
        if (CW[c,i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
        # служебные слова: «then rm -rf /», «do rm -rf /», «{ rm -rf /; }»
        if (CW[c,i] ~ /^(if|then|else|elif|fi|do|done|while|until|for|select|case|esac|in|function|\{|\}|!)$/) { i++; continue }
        base = basename(CW[c,i])
        if (base == "sudo" || base == "doas")         { i = skipflags(c, i + 1, n, "ugpCTRU") ; continue }
        if (base == "env")                            { i = skipflags(c, i + 1, n, "uS") ; continue }
        if (base ~ /^(nohup|setsid|command|builtin|exec|time|eatmydata|proxychains|proxychains4|unbuffer|busybox|toybox)$/) { i++; continue }
        if (base == "nice")                           { i = skipflags(c, i + 1, n, "n") ; continue }
        if (base == "ionice")                         { i = skipflags(c, i + 1, n, "cnpPt") ; continue }
        if (base == "stdbuf")                         { i = skipflags(c, i + 1, n, "ioe") ; continue }
        if (base == "chrt")                           { i = skipflags(c, i + 1, n, "p") ; continue }
        if (base == "timeout") {
            i = skipflags(c, i + 1, n, "sk")
            if (i <= n && CW[c,i] ~ /^[0-9]+(\.[0-9]+)?[smhd]?$/) i++
            continue
        }
        if (base == "xargs")                          { VIAX = 1; i = skipflags(c, i + 1, n, "IiLnPsEeadDp") ; continue }
        if (base == "flock") {
            i = skipflags(c, i + 1, n, "wE")
            if (i <= n && substr(CW[c,i], 1, 1) != "-") i++
            continue
        }
        break
    }
    AC = 0
    for (j = i; j <= n; j++) { AV[AC] = CW[c,j]; AVM[AC] = CM[c,j]; AC++ }
    return AC
}

function skipflags(c, i, n, argtakers,   w, last) {
    while (i <= n) {
        w = CW[c,i]
        if (w == "--") return i + 1
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
        if (substr(w, 1, 1) != "-" || w == "-") return i
        if (substr(w, 1, 2) == "--") {
            if (index(w, "=") == 0 && w ~ /^--(user|group|prompt|chdir|other-user|close-from|delay|max-procs|replace|arg-file|delimiter|eof|max-args|max-chars|max-lines|kill-after|signal|classdata|priority)$/) i += 2
            else i++
            continue
        }
        last = substr(w, length(w), 1)
        if (index(argtakers, last) > 0) i += 2; else i++
    }
    return i
}

# `cd / && rm -rf *` — cd меняет точку отсчёта для относительных целей
function track_cd(argc,   i, w) {
    for (i = 1; i < argc; i++) {
        w = AV[i]
        if (w == "--") continue
        if (substr(w, 1, 1) == "-" && length(w) > 1) continue
        if (w == "-" || w == "" || index(w, SENT)) return
        tilde_expand(w, AVM[i])
        CWD = normalize(TX_LIT)
        return
    }
    CWD = HOME                                        # `cd` без аргументов
}

function firstword(c,   i) {
    for (i = 1; i <= CN[c]; i++) if (CW[c,i] !~ /^[A-Za-z_][A-Za-z0-9_]*=/) return CW[c,i]
    return ""
}

# --- 1 и 5: rm ---------------------------------------------------------------
function check_rm(c, argc,   i, w, rec, npr, endf, unk, nt, j, viax) {
    rec = 0; npr = 0; endf = 0; unk = 0; nt = 0; viax = VIAX
    for (i = 1; i < argc; i++) {
        w = AV[i]
        if (!endf && w == "--") { endf = 1; continue }
        if (!endf && substr(w, 1, 2) == "--") {
            if (w == "--recursive") rec = 1
            else if (w == "--no-preserve-root") npr = 1
            continue
        }
        if (!endf && substr(w, 1, 1) == "-" && length(w) > 1) {
            if (w ~ /[rR]/) rec = 1
            if (index(w, SENT)) unk = 1
            continue
        }
        if (index(w, SENT)) unk = 1
        nt++; TGV[nt] = w; TGM[nt] = AVM[i]
    }

    if (npr) {
        deny("отключение защиты корня у rm (--no-preserve-root): " excerpt(c))
        return
    }
    if (!rec && !unk) return
    # `echo / | xargs rm -rf` — цели приходят из предыдущего звена конвейера
    if (nt == 0 && viax && c > 1 && CRUN[c-1] == CRUN[c] && CTERM[c-1] == "|" &&
        basename(firstword(c-1)) ~ /^(echo|printf|ls)$/) {
        for (i = 2; i <= CN[c-1]; i++) {
            if (i == 2 && CW[c-1,i] ~ /^-[neE]+$/) continue
            nt++; TGV[nt] = CW[c-1,i]; TGM[nt] = CM[c-1,i]
        }
    }
    for (j = 1; j <= nt; j++) {
        if (is_root_target(TGV[j], TGM[j])) {
            deny("рекурсивное удаление корня файловой системы или домашнего каталога: " excerpt(c))
            return
        }
    }
}

# ~ и ~user; результат в TX_LIT / TX_MSK
function tilde_expand(lit, msk,   rest, seg, p) {
    TX_LIT = lit; TX_MSK = msk
    if (substr(lit, 1, 1) != "~" || substr(msk, 1, 1) != "u") return
    rest = substr(lit, 2)
    if (rest == "" || substr(rest, 1, 1) == "/") {
        TX_MSK = dupq(length(HOME)) substr(msk, 2)
        TX_LIT = HOME rest
        return
    }
    p = index(rest, "/")
    if (p == 0) { seg = rest; rest = "" } else { seg = substr(rest, 1, p - 1); rest = substr(rest, p) }
    if (seg !~ /^[A-Za-z_][A-Za-z0-9_.-]*$/) return
    TX_LIT = "/home/" seg rest
    TX_MSK = dupq(length("/home/" seg)) (p == 0 ? "" : substr(msk, p + 1))
}

# Цель — корень ФС или корень домашнего каталога?
# Неизвестные подстановки (SENT) считаются непустым непрозрачным сегментом:
# «$X» никогда не превращается в «/», зато «/home/$USER» остаётся домом.
function is_root_target(lit, msk,   i, c, gp, dir, rest, seg, p, L) {
    if (lit == "") return 0
    if (length(lit) > 4096) return 0

    while (length(lit) > 1 && substr(lit, length(lit), 1) == "/") {      # хвостовые слэши
        lit = substr(lit, 1, length(lit) - 1)
        msk = substr(msk, 1, length(msk) - 1)
    }

    tilde_expand(lit, msk)
    lit = TX_LIT; msk = TX_MSK

    gp = 0
    L = length(lit)
    for (i = 1; i <= L; i++) {
        c = substr(lit, i, 1)
        if (substr(msk, i, 1) == "u" && (c == "*" || c == "?" || c == "[")) { gp = i; break }
    }

    if (gp > 0) {
        p = lastslash(lit)
        if (gp < p) return 0                          # шаблон не в последнем сегменте: /ho*/user
        seg = substr(lit, p + 1)
        if (!wipeall(seg)) return 0                   # /*.log, ~/pro* — это не снос дерева
        dir = (p == 0) ? "." : substr(lit, 1, p)
        return is_root_dir(normalize(dir))
    }
    return is_root_dir(normalize(lit))
}

# Шаблон сносит каталог целиком? «*» и «.*» — да, «*.log» и «pro*» — нет.
function wipeall(seg,   s) {
    if (index(seg, "*") == 0) return 0
    s = seg
    sub(/^\./, "", s)
    gsub(/\[[^]]*\]/, "", s)
    gsub(/[*?]/, "", s)
    return (s == "")
}

function is_root_dir(d) {
    if (d == "/") return 1
    if (d == HOME) return 1
    if (d == "/home" || d == "/Users" || d == "/root" || d == "/export/home") return 1
    if (d ~ /^\/home\/[^\/]+$/) return 1
    if (d ~ /^\/Users\/[^\/]+$/) return 1
    if (d ~ /^\/export\/home\/[^\/]+$/) return 1
    return 0
}

function normalize(p,   n, i, parts, out, cnt, res) {
    if (substr(p, 1, 1) != "/") p = CWD "/" p
    n = split(p, parts, "/")
    cnt = 0
    for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (cnt > 0) cnt--; continue }
        out[++cnt] = parts[i]
    }
    res = ""
    for (i = 1; i <= cnt; i++) res = res "/" out[i]
    return (res == "") ? "/" : res
}

function lastslash(s,   i) {
    for (i = length(s); i >= 1; i--) if (substr(s, i, 1) == "/") return i
    return 0
}

function dupq(n,   s) { s = ""; while (length(s) < n) s = s "qqqqqqqqqq"; return substr(s, 1, n) }

function striptrail(p) {
    while (length(p) > 1 && substr(p, length(p), 1) == "/") p = substr(p, 1, length(p) - 1)
    return p
}

function basename(p,   i) {
    i = lastslash(p)
    return (i == 0) ? p : substr(p, i + 1)
}

# --- 2: mkfs ----------------------------------------------------------------
function check_mkfs(c, argc,   i, w, k, dev, file, targets) {
    dev = 0; file = 0; targets = 0
    for (i = 1; i < argc; i++) {
        w = AV[i]
        if (substr(w, 1, 1) == "-") {
            if (w ~ /^-[tbLmOEINgijnc]$/) i++          # флаг со значением
            continue
        }
        targets++
        k = devkind(w)
        if (k == 1) { deny("форматирование блочного устройства: " excerpt(c)); return }
        if (k == 2) { devq(normalize(w), "форматирование блочного устройства: " excerpt(c)); dev = 1 }
        else if (index(w, SENT) == 0) file = 1        # образ-файл, не устройство
    }
    # цели нет вовсе (`mkfs.ext4 --help`) — ничего не форматируется;
    # цель есть, но неизвестна (`mkfs.ext4 $DISK`) — считаем устройством
    if (targets > 0 && !dev && !file) deny("форматирование блочного устройства: " excerpt(c))
}

# --- 3: dd / редирект / tee на устройство ------------------------------------
function check_dd(c, argc,   i, w, p, k) {
    for (i = 1; i < argc; i++) {
        w = AV[i]
        if (substr(w, 1, 3) != "of=") continue
        p = substr(w, 4)
        k = devkind(p)
        if (k == 1) { deny("запись потока прямо на блочное устройство (dd): " excerpt(c)); return }
        if (k == 2) { devq(normalize(p), "запись потока прямо на блочное устройство (dd): " excerpt(c)); return }
    }
}

function check_tee(c, argc,   i, w, k) {
    for (i = 1; i < argc; i++) {
        w = AV[i]
        if (substr(w, 1, 1) == "-") continue
        k = devkind(w)
        if (k == 1) { deny("запись потока прямо на блочное устройство (tee): " excerpt(c)); return }
        if (k == 2) { devq(normalize(w), "запись потока прямо на блочное устройство (tee): " excerpt(c)); return }
    }
}

function check_redirects(c,   j, op, t, k) {
    for (j = 1; j <= CRN[c]; j++) {
        op = CRO[c,j]
        if (op != ">" && op != ">>" && op != ">|" && op != "&>" && op != "&>>" && op != ">&") continue
        t = CRT[c,j]
        if (op == ">&" && t ~ /^[0-9]+$|^-$/) continue
        k = devkind(t)
        if (k == 1) { deny("запись потока прямо на блочное устройство (редирект): " excerpt(c)); return }
        if (k == 2) { devq(normalize(t), "запись потока прямо на блочное устройство (редирект): " excerpt(c)); return }
    }
}

# 0 — не устройство, 1 — точно блочное, 2 — путь в /dev, нужна проверка -b
function devkind(p) {
    if (p == "" || index(p, SENT)) return 0
    if (substr(p, 1, 1) != "/") {
        if (index(p, "/dev/") == 0) return 0
        p = normalize(p)
    } else p = normalize(p)
    if (p ~ /^\/dev\/(sd[a-z]+[0-9]*|hd[a-z]+[0-9]*|vd[a-z]+[0-9]*|xvd[a-z]+[0-9]*)$/) return 1
    if (p ~ /^\/dev\/nvme[0-9]+n[0-9]+(p[0-9]+)?$/) return 1
    if (p ~ /^\/dev\/mmcblk[0-9]+(p[0-9]+)?$/) return 1
    if (p ~ /^\/dev\/(loop[0-9]+(p[0-9]+)?|md[0-9]+|dm-[0-9]+|sr[0-9]+|nbd[0-9]+(p[0-9]+)?|ram[0-9]+)$/) return 1
    if (p ~ /^\/dev\/(mapper|disk|block|md|vg[^\/]*)\/.+$/) return 1
    if (p ~ /^\/dev\/r?disk[0-9]+(s[0-9]+)*$/) return 1
    if (p ~ /^\/dev\//) return 2
    return 0
}

# --- строка передаётся интерпретатору: разбираем её как команду ---------------
function check_shell(c, argc,   i, s, pb, j) {
    for (j = 1; j <= CRN[c]; j++) {                     # `bash <<< "rm -rf /"`
        if (CRO[c,j] == "<<<") push(CRT[c,j])
    }
    for (i = 1; i < argc; i++) {
        if (AV[i] == "--") break
        if (AV[i] == "-c" || AV[i] ~ /^-[a-zA-Z]*c$/) {
            if (i + 1 < argc) push(AV[i+1])
            return
        }
        if (substr(AV[i], 1, 1) != "-") return          # это файл скрипта — содержимое неизвестно
    }
    # `echo '...' | sh` — строка тоже исполнится
    if (c > 1 && CRUN[c-1] == CRUN[c] && (CTERM[c-1] == "|" || CTERM[c-1] == "|&")) {
        pb = basename(firstword(c - 1))
        if (pb == "echo" || pb == "printf") {
            s = ""
            for (j = 2; j <= CN[c-1]; j++) {
                if (j == 2 && CW[c-1,j] ~ /^-[neE]+$/) continue
                s = s (s == "" ? "" : " ") CW[c-1,j]
            }
            push(s)
        }
    }
}

function check_interp(c, argc,   i, w) {
    for (i = 1; i < argc; i++) {
        w = AV[i]
        if (w ~ /fork[ \t]*while[ \t]*fork/) { deny("fork-бомба: " excerpt(c)); return }
        if (w ~ /while[ \t]*\([ \t]*1[ \t]*\)[^;]*fork/) { deny("fork-бомба: " excerpt(c)); return }
        if (w ~ /while[ \t]*(True|1)[ \t]*:[^\n]*fork\(\)/) { deny("fork-бомба: " excerpt(c)); return }
    }
}

# --- 4: fork-бомба ----------------------------------------------------------
function detect_forkbomb(   k, j, name, depth, started, cnt, sawamp, sawpipe, lim) {
    for (k = 1; k <= NT; k++) {
        name = ""
        if (TT[k] == "w" && TT[k+1] == "o" && TV[k+1] == "(" && TT[k+2] == "o" && TV[k+2] == ")") {
            name = TV[k]; j = k + 3
        } else if (TT[k] == "w" && TV[k] == "function" && TT[k+1] == "w") {
            name = TV[k+1]; j = k + 2
            if (TT[j] == "o" && TV[j] == "(") j++
            if (TT[j] == "o" && TV[j] == ")") j++
        }
        if (name == "" || name == "{" || name == "}") continue

        cnt = 0; sawamp = 0; sawpipe = 0; depth = 0; started = 0
        lim = k + 500
        if (lim > NT) lim = NT
        for (; j <= lim; j++) {
            if (TT[j] == "x") break
            if (TT[j] == "w" && TV[j] == "{") { depth++; started = 1; continue }
            if (TT[j] == "o" && TV[j] == "(") { depth++; started = 1; continue }
            if ((TT[j] == "w" && TV[j] == "}") || (TT[j] == "o" && TV[j] == ")")) {
                depth--
                if (started && depth <= 0) break
                continue
            }
            if (TT[j] == "w" && TV[j] == name) {
                cnt++
                if (TT[j+1] == "o") {
                    if (TV[j+1] == "&") sawamp = 1
                    else if (TV[j+1] == "|" || TV[j+1] == "|&") sawpipe = 1
                }
            }
        }
        if (cnt >= 1 && (sawamp || (cnt >= 2 && sawpipe))) {
            deny("fork-бомба: рекурсивная функция " sanitize(name) "(), порождающая себя в фоне")
            return
        }
    }
}

# --- вывод ------------------------------------------------------------------
function excerpt(c,   i, s) {
    s = ""
    for (i = 1; i <= CN[c] && i <= 24; i++) s = s (s == "" ? "" : " ") CW[c,i]
    return sanitize(s)
}

function sanitize(s) {
    gsub(/[^ -~]/, ".", s)
    gsub(/"/, "'", s)
    if (length(s) > 160) s = substr(s, 1, 157) "..."
    return s
}

function deny(reason) {
    if (DENIED) return
    DENIED = 1
    print "D\t" reason
}

function devq(path, reason) {
    if (DENIED || path ~ /[[:cntrl:]]/) return
    print "Q\t" path "\t" reason
}
AWK_SOURCE_END

# Жёсткий предел исполнения — 5 с; свой лимит ставим с запасом.
if command -v timeout >/dev/null 2>&1; then TMO="timeout 4"; else TMO=""; fi

out=$(
    printf '%s\n' "$cmd" |
    GUARD_HOME="$hm" GUARD_CWD="$cwd" $TMO awk "$AWK_PROG" 2>/dev/null
) || out=""

reason=""
if [ -n "$out" ]; then
    while IFS=$'\t' read -r kind f1 f2; do
        case "$kind" in
            D) reason="$f1"; break ;;
            Q) if [ -b "$f1" ]; then reason="$f2"; break; fi ;;
        esac
    done <<EOF
$out
EOF
fi

[ -n "$reason" ] || exit 0

jq -cn --arg r "Заблокировано guard.sh: $reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
