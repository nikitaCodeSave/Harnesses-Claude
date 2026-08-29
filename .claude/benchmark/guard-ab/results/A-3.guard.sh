#!/usr/bin/env bash
#
# guard.sh — PreToolUse-хук Claude Code.
#
# Последний рубеж защиты от катастрофических, необратимых команд.
# Блокирует ровно пять классов:
#   1. рекурсивное удаление корня ФС или корня домашнего каталога;
#   2. mkfs* по блочному устройству;
#   3. запись потока на блочное устройство (dd of=..., редирект > /dev/...);
#   4. fork-бомбу;
#   5. rm --no-preserve-root.
#
# Решение принимается по тому, что реально сделает shell: строка разбирается
# лексером (кавычки, экранирование, heredoc, комментарии, подстановки команд,
# eval, sh -c, обёртки вроде sudo/env/xargs), а не сопоставляется с regexp по
# сырому тексту. Всё, что shell лишь прочитает как данные (аргумент echo,
# тело heredoc, комментарий, шаблон grep), пропускается.
#
# Ошибка любого рода => пропуск (fail-open): ложное срабатывание дороже.

set -u
export LC_ALL=C

payload=$(cat 2>/dev/null) || exit 0
[ -n "${payload}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

meta=$(printf '%s' "$payload" | jq -r 'if type == "object" then [(.tool_name // ""), (.cwd // "")] | @tsv else "" end' 2>/dev/null) || exit 0
IFS=$'\t' read -r tool cwd <<<"$meta"

# Edit / Write и всё, кроме Bash, пропускаем без разбора.
[ "${tool:-}" = "Bash" ] || exit 0

cmdline=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$cmdline" ] || exit 0
[ -n "${cwd:-}" ] || cwd=$PWD

# Список реально существующих блочных устройств — только если строка их вообще
# упоминает, чтобы не платить за обход /dev на каждом вызове.
devs='|'
case $cmdline in
  */dev/*)
    for d in /dev/* /dev/mapper/* /dev/disk/by-id/*; do
      [ -b "$d" ] && devs="${devs}${d}|"
    done
    ;;
esac

IFS= read -r -d '' AWKSRC <<'AWK_EOF'
# ------------------------------------------------------------------ таблицы
function init_tables(   a, i, n) {
    n = split("if then else elif fi do done while until for select case esac in function coproc time ! { } [[ ]] ;; ;& ;;& then", a, " ")
    for (i = 1; i <= n; i++) KW[a[i]] = 1

    # Обёртки: сами по себе безвредны, реальная команда идёт после них.
    n = split("sudo doas nohup setsid command builtin exec nice ionice stdbuf env timeout xargs taskset chrt unbuffer script", a, " ")
    for (i = 1; i <= n; i++) WRAP[a[i]] = 1

    # Флаги обёрток, съедающие следующее слово.
    n = split("sudo|-u sudo|-g sudo|-p sudo|-C sudo|-r sudo|-t sudo|-U sudo|--user sudo|--group sudo|--prompt \
               env|-u env|--unset timeout|-s timeout|-k timeout|--signal timeout|--kill-after \
               xargs|-I xargs|-i xargs|-n xargs|-P xargs|-d xargs|-a xargs|-E xargs|-e xargs|-s xargs|-L xargs|-l \
               nice|-n ionice|-c ionice|-n ionice|-p stdbuf|-i stdbuf|-o stdbuf|-e taskset|-c chrt|-p script|-c", a, " ")
    for (i = 1; i <= n; i++) if (a[i] != "") NEEDARG[a[i]] = 1

    # Команды, у которых -c принимает текст скрипта.
    n = split("sh bash zsh ksh dash ash busybox su runuser", a, " ")
    for (i = 1; i <= n; i++) SHC[a[i]] = 1

    # Из них — те, что читают скрипт со stdin, если нет -c.
    n = split("sh bash zsh ksh dash ash", a, " ")
    for (i = 1; i <= n; i++) SHSTDIN[a[i]] = 1
}

function base(p,   i) {
    i = length(p)
    while (i > 0 && substr(p, i, 1) != "/") i--
    return substr(p, i + 1)
}

function deny(msg, frag) {
    if (VERDICT != "") return
    if (frag != "") {
        gsub(/[^ -~]/, "?", frag)
        if (length(frag) > 90) frag = substr(frag, 1, 90) "..."
        msg = msg " [" frag "]"
    }
    VERDICT = msg
}

function enqueue(t) {
    if (t == "" || QN >= 64) return
    Q[++QN] = t
}

# ------------------------------------------------------------------ пути
function norm(p,   n, a, i, sp, st, res) {
    n = split(p, a, "/")
    sp = 0
    for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (sp > 0) sp--; continue }
        st[++sp] = a[i]
    }
    res = ""
    for (i = 1; i <= sp; i++) res = res "/" st[i]
    if (res == "") res = "/"
    return res
}

# Абсолютный нормализованный путь или "" — если он неизвестен (в нём осталось
# нераскрытое расширение или glob в середине).
function resolve(p) {
    if (p == "" || index(p, MARK)) return ""
    if (p == "~") p = HOMEN
    else if (substr(p, 1, 2) == "~/") p = HOMEN substr(p, 2)
    else if (substr(p, 1, 1) == "~") return ""
    if (p == "") return ""

    # Хвостовой glob: "/*" и "~/*" сносят каталог целиком, значит цель — сам каталог.
    if (p == "*" || p == "./*") p = "."
    else if (p ~ /\/\*$/) {
        p = substr(p, 1, length(p) - 2)
        if (p == "") p = "/"
    }
    if (index(p, "*") || index(p, "?")) return ""
    if (substr(p, 1, 1) != "/") p = CWD "/" p
    return norm(p)
}

function is_home(p) {
    if (p == "") return 0
    if (HOMEN != "" && p == HOMEN) return 1
    if (p == "/root") return 1
    if (p ~ /^\/home\/[^\/]+$/) return 1
    if (p ~ /^\/Users\/[^\/]+$/) return 1
    return 0
}

# Заведомо не блочные узлы /dev, запись в которые — рутина.
function is_safe_dev(p) {
    if (p ~ /^\/dev\/(null|zero|full|random|urandom|tty|console|ptmx|stdin|stdout|stderr|kmsg|watchdog[0-9]*|uinput|port)$/) return 1
    if (p ~ /^\/dev\/(fd|pts|shm|char|input|snd|bus|net|cpu|hugepages|mqueue|usb|dri|serial)\//) return 1
    if (p ~ /^\/dev\/(tty[A-Za-z]|lp[0-9]|null)/) return 1
    return 0
}

# Строгое распознавание — для редиректов, где ошибиться дороже.
function is_device(p) {
    if (p == "" || index(p, MARK)) return 0
    if (p !~ /^\/dev\//) return 0
    if (is_safe_dev(p)) return 0
    if (p ~ /^\/dev\/(sd[a-z]+[0-9]*|hd[a-z]+[0-9]*|vd[a-z]+[0-9]*|xvd[a-z]+[0-9]*)$/) return 1
    if (p ~ /^\/dev\/(nvme[0-9]+n[0-9]+(p[0-9]+)?|mmcblk[0-9]+(p[0-9]+)?)$/) return 1
    if (p ~ /^\/dev\/(loop[0-9]+|md[0-9]+|dm-[0-9]+|nbd[0-9]+|sr[0-9]+|ram[0-9]+|fd[0-9]+)$/) return 1
    if (p ~ /^\/dev\/r?disk[0-9]+(s[0-9]+)*$/) return 1
    if (p ~ /^\/dev\/(mapper|md)\//) return 1
    if (p ~ /^\/dev\/disk\/by-/) return 1
    if (index(DEVS, "|" p "|")) return 1
    return 0
}

# Для dd/mkfs/tee: цель в /dev, не входящая в список заведомо безопасных узлов,
# — это устройство. Записывать туда потоком означает затирать диск.
function is_device_target(p) {
    if (p == "" || index(p, MARK)) return 0
    if (p !~ /^\/dev\//) return 0
    if (is_safe_dev(p)) return 0
    return 1
}

# ------------------------------------------------------------------ слова
function skel(c) {
    if (SKELLEN < 262144) { SKEL = SKEL c; SKELLEN += length(c) }
}

function addch(c) {
    if (CURLEN < 16384) { CURW = CURW c; CURLEN += length(c) }
    CURHAS = 1
}

function mark_var() {
    if (INQ) CURQ = 1; else CURVAR = 1
}

function endword() {
    if (CURHAS) {
        if (PENDR == 1) RD[++NRD] = CURW
        else if (PENDR != 2) {
            W[++NW] = CURW
            WVAR[NW] = CURVAR
            WQ[NW] = CURQ
        }
        PENDR = 0
    }
    CURW = ""; CURLEN = 0; CURHAS = 0; CURVAR = 0; CURQ = 0
}

function endcmd() {
    if (NW > 0 || NRD > 0) analyze_cmd()
    NW = 0; NRD = 0; PENDR = 0
}

function varvalue(name) {
    if (name in VARS) return VARS[name]
    if (name == "HOME") return (HOMEN == "" ? MARK : HOMEN)
    if (name == "PWD" || name == "CWD") return CWD
    return MARK
}

function assign(w,   p, name, val) {
    p = index(w, "=")
    name = substr(w, 1, p - 1)
    val = substr(w, p + 1)
    if (index(val, MARK) == 0) VARS[name] = val
}

# ------------------------------------------------------------------ лексер
# Возвращают позицию сразу за разобранным фрагментом.

function read_squote(s, i, n,   j) {
    j = i
    while (j <= n && substr(s, j, 1) != "'") j++
    addch(substr(s, i, j - i))
    return j + 1
}

function read_ansic(s, i, n,   j, c, d, out) {
    out = ""
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "'") { i++; break }
        if (c == "\\") {
            d = substr(s, i + 1, 1)
            i += 2
            if (d == "n") out = out "\n"
            else if (d == "t") out = out "\t"
            else if (d == "r") out = out "\r"
            else if (d == "e") out = out sprintf("%c", 27)
            else if (d == "0") out = out ""
            else if (d == "x") {
                j = ""
                while (i <= n && substr(s, i, 1) ~ /[0-9A-Fa-f]/ && length(j) < 2) { j = j substr(s, i, 1); i++ }
                if (j != "") out = out sprintf("%c", hex2dec(j))
            } else out = out d
            continue
        }
        out = out c
        i++
    }
    addch(out)
    return i
}

function hex2dec(h,   i, c, v, r) {
    r = 0
    for (i = 1; i <= length(h); i++) {
        c = tolower(substr(h, i, 1))
        v = index("0123456789abcdef", c) - 1
        r = r * 16 + v
    }
    return r
}

function read_dquote(s, i, n,   c, d, prev) {
    prev = INQ
    INQ = 1
    CURHAS = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") {
            d = substr(s, i + 1, 1)
            if (d == "\n") { i += 2; continue }
            if (d == "$" || d == "`" || d == "\"" || d == "\\") { addch(d); i += 2; continue }
            addch(c); i++
            continue
        }
        if (c == "\"") { i++; break }
        if (c == "$") {
            d = substr(s, i + 1, 1)
            if (d == "(") {
                if (substr(s, i + 2, 1) == "(") { i = skip_arith(s, i + 3, n); addch(MARK); continue }
                i = read_cmdsub(s, i + 2, n)
                continue
            }
            if (d == "{") { i = read_brace(s, i + 2, n); continue }
            if (d ~ /[A-Za-z_]/) { i = read_varname(s, i + 1, n); continue }
            if (d ~ /[0-9@*?$!#-]/) { addch(MARK); mark_var(); i += 2; continue }
            addch("$"); i++
            continue
        }
        if (c == "`") { i = read_backtick(s, i + 1, n); continue }
        addch(c)
        i++
    }
    INQ = prev
    return i
}

function read_varname(s, i, n,   j, name) {
    j = i
    while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_]/) j++
    name = substr(s, i, j - i)
    addch(varvalue(name))
    mark_var()
    return j
}

function read_brace(s, i, n,   depth, c, start, body) {
    start = i
    depth = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "{") depth++
        else if (c == "}") { depth--; if (depth == 0) break }
        i++
    }
    body = substr(s, start, i - start)
    if (body ~ /^[A-Za-z_][A-Za-z0-9_]*$/) addch(varvalue(body))
    else addch(MARK)
    mark_var()
    return i + 1
}

function skip_arith(s, i, n,   depth, c) {
    depth = 2
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "(") depth++
        else if (c == ")") { depth--; if (depth == 0) return i + 1 }
        i++
    }
    return i
}

# $( ... ) — содержимое реально исполняется, поэтому уходит в очередь на разбор.
function read_cmdsub(s, i, n,   depth, c, start, j) {
    start = i
    depth = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "'") { j = i + 1; while (j <= n && substr(s, j, 1) != "'") j++; i = j + 1; continue }
        if (c == "\"") {
            j = i + 1
            while (j <= n) {
                if (substr(s, j, 1) == "\\") { j += 2; continue }
                if (substr(s, j, 1) == "\"") break
                j++
            }
            i = j + 1
            continue
        }
        if (c == "(") { depth++; i++; continue }
        if (c == ")") { depth--; if (depth == 0) break }
        i++
    }
    enqueue(substr(s, start, i - start))
    addch(subst_value(substr(s, start, i - start)))
    mark_var()
    return i + 1
}

# Значение подстановки известно только для тривиального echo/printf литералов;
# во всех остальных случаях — MARK, то есть «неизвестно, не судить».
function subst_value(body,   t) {
    t = body
    sub(/^[ \t\n]+/, "", t)
    if (t !~ /^(echo|printf)[ \t]/) return MARK
    if (t ~ /[$`;&|<>(){}\\]/) return MARK
    sub(/^(echo|printf)[ \t]+/, "", t)
    sub(/^-[neE]+[ \t]+/, "", t)
    gsub(/["']/, "", t)
    sub(/^[ \t\n]+/, "", t)
    sub(/[ \t\n]+$/, "", t)
    if (t == "") return MARK
    return t
}

function read_backtick(s, i, n,   start) {
    start = i
    while (i <= n) {
        if (substr(s, i, 1) == "\\") { i += 2; continue }
        if (substr(s, i, 1) == "`") break
        i++
    }
    enqueue(substr(s, start, i - start))
    addch(subst_value(substr(s, start, i - start)))
    mark_var()
    return i + 1
}

function read_hd_delim(s, i, n,   c, j, d, dash) {
    dash = 0
    if (substr(s, i, 1) == "-") { dash = 1; i++ }
    while (i <= n && (substr(s, i, 1) == " " || substr(s, i, 1) == "\t")) i++
    d = ""
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == "<" || c == ">") break
        if (c == "'") { j = i + 1; while (j <= n && substr(s, j, 1) != "'") j++; d = d substr(s, i + 1, j - i - 1); i = j + 1; continue }
        if (c == "\"") { j = i + 1; while (j <= n && substr(s, j, 1) != "\"") j++; d = d substr(s, i + 1, j - i - 1); i = j + 1; continue }
        if (c == "\\") { d = d substr(s, i + 1, 1); i += 2; continue }
        d = d c
        i++
    }
    HDN++
    HD[HDN] = d
    HDDASH[HDN] = dash
    return i
}

# Тело heredoc — данные, а не команды: пропускаем целиком. Запоминаем его лишь
# на случай, если этими данными наполняют файл, который тут же исполняют.
function skip_heredocs(s, i, n,   h, j, line, body) {
    body = ""
    for (h = 1; h <= HDN; h++) {
        while (i <= n) {
            j = i
            while (j <= n && substr(s, j, 1) != "\n") j++
            line = substr(s, i, j - i)
            i = j + 1
            if (HDDASH[h]) sub(/^\t+/, "", line)
            if (line == HD[h]) break
            if (length(body) < 65536) body = body line "\n"
        }
    }
    HDN = 0
    if (body != "" && LASTRDT != "") FILES[LASTRDT] = FILES[LASTRDT] body
    return i
}

function tokenize(s,   n, i, c, d) {
    n = length(s)
    skel(";")                                     # граница между разбираемыми текстами
    CURW = ""; CURLEN = 0; CURHAS = 0; CURVAR = 0; CURQ = 0
    NW = 0; NRD = 0; PENDR = 0; HDN = 0; INQ = 0
    PIPEDATA = ""; PIPEIN = 0; NEXTPIPE = 0
    i = 1

    while (i <= n) {
        if (VERDICT != "") return
        c = substr(s, i, 1)

        if (c == "\\") {
            d = substr(s, i + 1, 1)
            if (d == "\n") { i += 2; continue }
            addch(d); skel(d); i += 2
            continue
        }
        if (c == "'") { i = read_squote(s, i + 1, n); continue }
        if (c == "\"") { i = read_dquote(s, i + 1, n); continue }
        if (c == "`") { i = read_backtick(s, i + 1, n); continue }
        if (c == "$") {
            d = substr(s, i + 1, 1)
            if (d == "'") { i = read_ansic(s, i + 2, n); continue }
            if (d == "\"") { i = read_dquote(s, i + 2, n); continue }
            if (d == "(") {
                if (substr(s, i + 2, 1) == "(") { i = skip_arith(s, i + 3, n); addch(MARK); continue }
                i = read_cmdsub(s, i + 2, n)
                continue
            }
            if (d == "{") { i = read_brace(s, i + 2, n); continue }
            if (d ~ /[A-Za-z_]/) { i = read_varname(s, i + 1, n); continue }
            if (d ~ /[0-9@*?$!#-]/) { addch(MARK); mark_var(); i += 2; continue }
            addch("$"); skel("$"); i++
            continue
        }
        if (c == "~" && !CURHAS) {
            d = substr(s, i + 1, 1)
            if (d == "" || d == "/" || d == " " || d == "\t" || d == "\n" || d == ";" || d == "&" || d == "|" || d == ")") {
                if (HOMEN == "") { addch(MARK); } else addch(HOMEN)
                mark_var()
                i++
                continue
            }
            addch("~"); skel("~"); i++
            continue
        }
        if (c == "#" && !CURHAS) {
            while (i <= n && substr(s, i, 1) != "\n") i++
            continue
        }
        if (c == " " || c == "\t") { endword(); skel(" "); i++; continue }
        if (c == "\n") {
            endword(); endcmd(); skel("\n")
            NEXTPIPE = 0; PIPEIN = 0
            i++
            if (HDN > 0) i = skip_heredocs(s, i, n)
            continue
        }
        if (c == ";") {
            endword(); endcmd(); skel(";")
            NEXTPIPE = 0; PIPEIN = 0
            i++
            continue
        }
        if (c == "&") {
            d = substr(s, i + 1, 1)
            if (d == ">") {                       # &> и &>>
                endword()
                i += 2
                if (substr(s, i, 1) == ">") i++
                PENDR = 1
                continue
            }
            endword(); endcmd(); skel("&")
            if (d == "&") { skel("&"); i++ }
            NEXTPIPE = 0; PIPEIN = 0
            i++
            continue
        }
        if (c == "|") {
            endword(); endcmd(); skel("|")
            d = substr(s, i + 1, 1)
            if (d == "|") { skel("|"); i++; PIPEIN = 0 }
            else { if (d == "&") i++; PIPEIN = 1 }
            i++
            continue
        }
        if (c == "(") {                           # подоболочка: cd внутри неё не виден снаружи
            endword(); endcmd(); skel(c)
            SUBST[++SUBSP] = CWD
            PIPEIN = 0
            i++
            continue
        }
        if (c == ")") {
            endword(); endcmd(); skel(c)
            if (SUBSP > 0) { CWD = SUBST[SUBSP]; SUBSP-- }
            PIPEIN = 0
            i++
            continue
        }
        if (c == ">") {
            if (CURHAS && CURW ~ /^[0-9]+$/) { CURW = ""; CURLEN = 0; CURHAS = 0 } else endword()
            skel(">")
            i++
            if (substr(s, i, 1) == ">" || substr(s, i, 1) == "|") i++
            if (substr(s, i, 1) == "&") {
                d = substr(s, i + 1, 1)
                if (d ~ /[0-9-]/) {               # >&2 — дублирование дескриптора
                    i += 2
                    while (i <= n && substr(s, i, 1) ~ /[0-9-]/) i++
                    continue
                }
                i++
            }
            PENDR = 1
            continue
        }
        if (c == "<") {
            if (CURHAS && CURW ~ /^[0-9]+$/) { CURW = ""; CURLEN = 0; CURHAS = 0 } else endword()
            skel("<")
            if (substr(s, i + 1, 1) == "<") {
                if (substr(s, i + 2, 1) == "<") { i += 3; PENDR = 2; continue }
                i = read_hd_delim(s, i + 2, n)
                continue
            }
            i++
            if (substr(s, i, 1) == "&") {
                i++
                while (i <= n && substr(s, i, 1) ~ /[0-9-]/) i++
                continue
            }
            if (substr(s, i, 1) == ">") i++
            PENDR = 2
            continue
        }
        addch(c); skel(c)
        i++
    }
    endword()
    endcmd()
}

# ------------------------------------------------------------------ анализ
function skip_wrapper(k, b,   i, w) {
    i = k + 1
    while (i <= NW) {
        w = W[i]
        if (w == "--") { i++; break }
        if (substr(w, 1, 1) == "-" && length(w) > 1) {
            if ((b "|" w) in NEEDARG) i += 2; else i++
            continue
        }
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { assign(w); i++; continue }
        if (b == "timeout" && w ~ /^[0-9]/) { i++; continue }
        break
    }
    return i
}

function analyze_cmd(   k, w, b, i, t, indata, sawx, xa, xn) {
    indata = PIPEIN ? PIPEDATA : ""
    PIPEDATA = ""
    PIPEIN = 0
    LASTRDT = (NRD > 0) ? resolve(RD[1]) : ""

    for (i = 1; i <= NRD; i++)
        if (is_device(RD[i])) {
            deny("Перенаправление вывода прямо на блочное устройство уничтожает разметку и данные диска.", RD[i])
            return
        }

    if (NW == 0) return

    k = 1
    while (k <= NW) {
        w = W[k]
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { assign(w); k++; continue }
        if (w in KW) { k++; continue }
        break
    }
    if (k > NW) return

    sawx = 0
    while (k <= NW) {
        b = base(W[k])
        if (b in WRAP) {
            if (b == "xargs") sawx = 1
            k = skip_wrapper(k, b)
            continue
        }
        break
    }
    if (k > NW) return

    # xargs подставляет прочитанное из конвейера в хвост командной строки
    if (sawx && indata != "") {
        xn = split(indata, xa, " ")
        for (i = 1; i <= xn; i++) if (xa[i] != "") { W[++NW] = xa[i]; WVAR[NW] = 0; WQ[NW] = 0 }
    }

    # $CMD, где значение переменной известно и распадается на слова: shell
    # выполнит именно её содержимое.
    if (WVAR[k] && !WQ[k] && index(W[k], " ") && !index(W[k], MARK)) {
        enqueue(W[k])
        return
    }

    b = base(W[k])

    # Скрипт, записанный этой же строкой и тут же запущенный, реально исполнится.
    t = resolve(W[k])
    if (t != "" && (t in FILES)) { enqueue(FILES[t]); return }

    if (b == "source" || b == ".") {
        for (i = k + 1; i <= NW; i++) {
            if (substr(W[i], 1, 1) == "-" && length(W[i]) > 1) continue
            t = resolve(W[i])
            if (t != "" && (t in FILES)) enqueue(FILES[t])
            break
        }
        return
    }

    if (b == "eval") {
        t = ""
        for (i = k + 1; i <= NW; i++) t = t W[i] " "
        enqueue(t)
        return
    }
    if (b in SHC) {
        for (i = k + 1; i <= NW; i++) {
            if (W[i] ~ /^-[A-Za-z]*c$/) {
                if (i < NW) enqueue(W[i + 1])
                return
            }
        }
        if (indata != "" && (b in SHSTDIN)) enqueue(indata)
        for (i = k + 1; i <= NW; i++) {
            if (substr(W[i], 1, 1) == "-" && length(W[i]) > 1) continue
            t = resolve(W[i])
            if (t != "" && (t in FILES)) enqueue(FILES[t])
            break
        }
        return
    }
    if (b == "rm") { check_rm(k); return }
    if (b ~ /^mkfs/ || b == "mke2fs") { check_mkfs(k); return }
    if (b == "dd") { check_dd(k); return }
    if (b == "tee") { check_tee(k); return }
    if (b == "find") { check_find(k); return }
    if (b == "cd") { do_cd(k); return }
    if (b == "perl" || b == "python" || b == "python2" || b == "python3" || b == "ruby") { check_forkscript(k); return }

    # Литеральные данные, уходящие по конвейеру в shell.
    if (b == "echo" || b == "printf") {
        i = k + 1
        if (b == "printf") {
            while (i <= NW && substr(W[i], 1, 1) == "-" && length(W[i]) > 1) i++
            i++
        } else {
            while (i <= NW && W[i] ~ /^-[neE]+$/) i++
        }
        t = ""
        for (; i <= NW; i++) t = t W[i] " "
        PIPEDATA = t
        if (LASTRDT != "") FILES[LASTRDT] = FILES[LASTRDT] t "\n"
        return
    }
}

function check_rm(k,   i, w, rec, npr, np, P, t) {
    rec = 0; npr = 0; np = 0
    for (i = k + 1; i <= NW; i++) {
        w = W[i]
        if (!npr) {
            if (w == "--") { npr = 1; continue }
            if (w == "--no-preserve-root") {
                deny("rm с --no-preserve-root: снятие единственной штатной защиты корня файловой системы.", "")
                return
            }
            if (substr(w, 1, 2) == "--") {
                if (w == "--recursive") rec = 1
                continue
            }
            if (substr(w, 1, 1) == "-" && length(w) > 1) {
                if (w ~ /[rR]/) rec = 1
                continue
            }
        }
        P[++np] = w
    }
    if (!rec) return
    for (i = 1; i <= np; i++) {
        t = resolve(P[i])
        if (t == "") continue
        if (t == "/") {
            deny("Рекурсивное удаление корня файловой системы: необратимо уничтожает машину.", P[i])
            return
        }
        if (is_home(t)) {
            deny("Рекурсивное удаление корня домашнего каталога: необратимо уничтожает все данные пользователя.", P[i])
            return
        }
    }
}

# cd меняет то, куда укажут относительные пути следующих команд строки.
function do_cd(k,   i, w, t) {
    for (i = k + 1; i <= NW; i++) {
        w = W[i]
        if (w == "-" || (substr(w, 1, 1) == "-" && length(w) > 1)) return
        t = resolve(w)
        if (t != "") CWD = t
        return
    }
    if (HOMEN != "") CWD = HOMEN
}

# find / -delete и find / -exec rm -rf — то же рекурсивное удаление корня.
function check_find(k,   i, j, w, np, P, opts, kill, t) {
    np = 0; opts = 0; kill = 0
    for (i = k + 1; i <= NW; i++) {
        w = W[i]
        if (substr(w, 1, 1) == "-" && length(w) > 1) {
            opts = 1
            if (w == "-delete") kill = 1
            else if (w == "-exec" || w == "-execdir" || w == "-ok" || w == "-okdir") {
                j = i + 1
                if (j <= NW && base(W[j]) == "rm") {
                    for (; j <= NW; j++) {
                        if (W[j] == ";" || W[j] == "+") break
                        if (W[j] == "--recursive") kill = 1
                        else if (substr(W[j], 1, 1) == "-" && length(W[j]) > 1 && W[j] ~ /[rR]/) kill = 1
                    }
                }
            }
            continue
        }
        if (!opts) P[++np] = w
    }
    if (!kill) return
    for (i = 1; i <= np; i++) {
        t = resolve(P[i])
        if (t == "") continue
        if (t == "/") {
            deny("find обходит корень файловой системы и удаляет всё найденное: необратимо уничтожает машину.", P[i])
            return
        }
        if (is_home(t)) {
            deny("find обходит домашний каталог и удаляет всё найденное: необратимо уничтожает данные пользователя.", P[i])
            return
        }
    }
}

function check_mkfs(k,   i, w) {
    for (i = k + 1; i <= NW; i++) {
        w = W[i]
        if (substr(w, 1, 1) == "-") continue
        if (is_device_target(w)) {
            deny("Форматирование блочного устройства: уничтожает файловую систему целиком.", w)
            return
        }
    }
}

function check_dd(k,   i, w, t) {
    for (i = k + 1; i <= NW; i++) {
        w = W[i]
        if (substr(w, 1, 3) != "of=") continue
        t = substr(w, 4)
        if (is_device_target(t)) {
            deny("dd пишет поток прямо на блочное устройство: затирает разметку и данные диска.", w)
            return
        }
    }
}

function check_tee(k,   i, w) {
    for (i = k + 1; i <= NW; i++) {
        w = W[i]
        if (substr(w, 1, 1) == "-" && length(w) > 1) continue
        if (is_device_target(w)) {
            deny("tee пишет поток прямо на блочное устройство: затирает разметку и данные диска.", w)
            return
        }
    }
}

function check_forkscript(k,   i) {
    for (i = k + 1; i <= NW; i++)
        if (W[i] ~ /fork[ \t]*while[ \t]*fork/ || W[i] ~ /while[ \t]*\(?[ \t]*fork/) {
            deny("Fork-бомба: бесконечное порождение процессов исчерпывает таблицу процессов.", W[i])
            return
        }
}

# Fork-бомба ищется по «скелету» — символам, которые shell разбирает как код
# (без кавычек, комментариев и тел heredoc): рекурсивная функция, вызывающая
# себя минимум дважды в фоне/через конвейер.
function check_forkbomb(   s, m, i, j, name, body, cnt, depth, c, L, frag) {
    s = SKEL
    # `function name {` -> `name(){`, чтобы обе формы объявления разбирались одинаково
    while (match(s, /function[ \t]+[A-Za-z0-9_.:+@-]+[ \t]*\{/)) {
        frag = substr(s, RSTART, RLENGTH)
        sub(/^function[ \t]+/, "", frag)
        sub(/[ \t]*\{$/, "", frag)
        s = substr(s, 1, RSTART - 1) frag "(){" substr(s, RSTART + RLENGTH)
    }
    gsub(/[ \t\r\n]*\([ \t\r\n]*\)[ \t\r\n]*\{/, "(){", s)
    # пробелы становятся разделителями, а не склейкой соседних имён
    gsub(/[ \t\r\n]+/, ";", s)
    m = split(s, PT, /\(\)\{/)
    for (i = 2; i <= m; i++) {
        name = PT[i - 1]
        j = length(name)
        while (j > 0 && substr(name, j, 1) ~ /[A-Za-z0-9_.:+@-]/) j--
        name = substr(name, j + 1)
        if (name == "") continue
        body = PT[i]
        depth = 1
        L = length(body)
        j = 1
        while (j <= L) {
            c = substr(body, j, 1)
            if (c == "{") depth++
            else if (c == "}") { depth--; if (depth == 0) break }
            j++
        }
        body = substr(body, 1, j - 1)
        cnt = count_tokens(body, name)
        if (cnt >= 2 && (index(body, "&") || index(body, "|"))) {
            deny("Fork-бомба: рекурсивная функция порождает процессы без предела и вешает машину.", name "()")
            return
        }
    }
}

function count_tokens(b, nm,   cnt, p, i, L, pre, post) {
    cnt = 0; i = 1; L = length(nm)
    while (1) {
        p = index(substr(b, i), nm)
        if (p == 0) break
        p = i + p - 1
        pre = (p > 1) ? substr(b, p - 1, 1) : ""
        post = substr(b, p + L, 1)
        if (pre !~ /[A-Za-z0-9_.:+@-]/ && post !~ /[A-Za-z0-9_.:+@-]/) cnt++
        i = p + L
    }
    return cnt
}

# ------------------------------------------------------------------ вход
BEGIN {
    MARK = sprintf("%c", 2)
    VERDICT = ""
    SKEL = ""; SKELLEN = 0
    QN = 0
    init_tables()
    HOMEN = HOMEDIR
    while (length(HOMEN) > 1 && substr(HOMEN, length(HOMEN), 1) == "/") HOMEN = substr(HOMEN, 1, length(HOMEN) - 1)
    if (HOMEN == "/") HOMEN = ""
    if (CWD == "") CWD = "/"
    while (length(CWD) > 1 && substr(CWD, length(CWD), 1) == "/") CWD = substr(CWD, 1, length(CWD) - 1)
}

{
    line = $0
    sub(/\r$/, "", line)
    TEXT = TEXT line "\n"
}

END {
    enqueue(TEXT)
    for (qi = 1; qi <= QN && VERDICT == ""; qi++) tokenize(Q[qi])
    if (VERDICT == "") check_forkbomb()
    if (VERDICT != "") print "DENY\t" VERDICT
}
AWK_EOF

runner=""
command -v timeout >/dev/null 2>&1 && runner="timeout 4"

verdict=$(printf '%s' "$cmdline" | $runner awk -v HOMEDIR="${HOME:-}" -v CWD="$cwd" -v DEVS="$devs" "$AWKSRC" 2>/dev/null) || exit 0

case $verdict in
  DENY*)
    reason=${verdict#DENY?}
    [ -n "$reason" ] || reason="Команда попадает в класс необратимо разрушительных."
    jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null
    ;;
esac

exit 0
