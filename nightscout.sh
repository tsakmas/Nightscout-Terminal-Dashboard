#!/usr/bin/env bash
#
# Nightscout Terminal Dashboard v2
# Live blood glucose from a Nightscout site, in the terminal.
#
#   ./nightscout.sh              full-screen dashboard
#   ./nightscout.sh --line       one line (for tmux / shell prompt)
#   ./nightscout.sh --swiftbar   output for the SwiftBar menu bar app
#   ./nightscout.sh --help       all options
#
# Works with the bash 3.2 that ships with macOS. Needs curl and jq.

VERSION="2.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- Defaults: change these in your config file, not here ----------
NIGHTSCOUT_URL=""
TOKEN=""
LANG_CODE="en"        # en | gr
UNITS="mgdl"          # mgdl | mmol
INTERVAL=30           # seconds between downloads
STALE_MIN=15          # data older than this many minutes is "stale"
URGENT_LOW=55         # thresholds are always in mg/dL
LOW=70
HIGH=180
URGENT_HIGH=250
ALERTS=1              # 1 = desktop notification + sound, 0 = off
ALERT_REPEAT_MIN=15   # repeat an ongoing alert every N minutes
SHOW_URL=0            # 1 = show the Nightscout address in the header

usage() {
    cat <<'EOF'
Nightscout Terminal Dashboard v2

Usage: ./nightscout.sh [options]

  --lang en|gr        language (default: en)
  --units mgdl|mmol   glucose units (default: mgdl)
  --interval SEC      seconds between downloads (default: 30)
  --no-alerts         turn off desktop notifications and sounds
  --config FILE       use this config file
  --line              print one line and exit (tmux, shell prompt)
  --swiftbar          print SwiftBar menu bar output and exit
  --once              draw the dashboard once and exit
  --version           show version
  -h, --help          show this help

Settings are read from (first found):
  $NS_CONFIG, ./nightscout.conf, ~/.config/nightscout-dash.conf
Environment variables NS_URL, NS_TOKEN, NS_LANG, NS_UNITS override them.

Keys in the dashboard: q quit, r refresh, u switch units, m mute alerts
EOF
}

# ---------- Config: file, then environment, then flags ----------
CONFIG_FILE="${NS_CONFIG:-}"
prev=""
for a in "$@"; do
    [ "$prev" = "--config" ] && CONFIG_FILE="$a"
    prev="$a"
done
if [ -z "$CONFIG_FILE" ]; then
    for f in "$SCRIPT_DIR/nightscout.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/nightscout-dash.conf"; do
        if [ -f "$f" ]; then CONFIG_FILE="$f"; break; fi
    done
fi
if [ -n "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file not found: $CONFIG_FILE" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi
[ -n "${NS_URL:-}" ] && NIGHTSCOUT_URL="$NS_URL"
[ -n "${NS_TOKEN:-}" ] && TOKEN="$NS_TOKEN"
[ -n "${NS_LANG:-}" ] && LANG_CODE="$NS_LANG"
[ -n "${NS_UNITS:-}" ] && UNITS="$NS_UNITS"

MODE="dashboard"
while [ $# -gt 0 ]; do
    case "$1" in
        --lang)      LANG_CODE="$2"; shift ;;
        --units)     UNITS="$2"; shift ;;
        --interval)  INTERVAL="$2"; shift ;;
        --config)    shift ;;
        --no-alerts) ALERTS=0 ;;
        --line)      MODE="line" ;;
        --swiftbar)  MODE="swiftbar" ;;
        --once)      MODE="once" ;;
        --version)   echo "nightscout.sh $VERSION"; exit 0 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done

case "$LANG_CODE" in gr|GR|el|EL|greek) LANG_CODE="gr" ;; *) LANG_CODE="en" ;; esac
case "$UNITS" in mmol*|MMOL*) UNITS="mmol" ;; *) UNITS="mgdl" ;; esac

for v in INTERVAL STALE_MIN URGENT_LOW LOW HIGH URGENT_HIGH ALERT_REPEAT_MIN; do
    case "${!v}" in
        ''|*[!0-9]*) echo "Setting $v must be a whole number (got '${!v}')" >&2; exit 2 ;;
    esac
done
[ "$INTERVAL" -lt 5 ] && INTERVAL=5

# Character counting below needs a UTF-8 locale.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
    *) if [ "$(uname)" = "Darwin" ]; then export LC_ALL="en_US.UTF-8"; else export LC_ALL="C.UTF-8"; fi ;;
esac

# ---------- Text (English / Greek) ----------
load_strings() {
    if [ "$LANG_CODE" = "gr" ]; then
        S_TITLE="Nightscout · Γλυκόζη"
        S_UPDATED="ενημέρωση"
        S_LOADING="Σύνδεση με το Nightscout…"
        S_ERR_FETCH="Αδυναμία σύνδεσης με το Nightscout, νέα προσπάθεια σύντομα"
        S_NO_DATA="Δεν βρέθηκαν μετρήσεις γλυκόζης"
        S_STALE="ΧΩΡΙΣ ΠΡΟΣΦΑΤΑ ΔΕΔΟΜΕΝΑ"
        S_URGENT_LOW="ΕΠΙΚΙΝΔΥΝΑ ΧΑΜΗΛΑ"
        S_LOW="ΧΑΜΗΛΑ"
        S_OK="ΣΤΟ ΣΤΟΧΟ"
        S_HIGH="ΥΨΗΛΑ"
        S_URGENT_HIGH="ΠΟΛΥ ΥΨΗΛΑ"
        S_FALLING="ΠΕΦΤΕΙ ΓΡΗΓΟΡΑ"
        S_JUST_NOW="μόλις τώρα"
        S_MIN_AGO="πριν %d λεπ."
        S_H_AGO="πριν %d ώρ. %d λεπ."
        S_AT="στις"
        S_GRAPH="Τελευταίες %s"
        S_HOURS_FMT="%dω"
        S_MIN_FMT="%d λεπ."
        S_NOW="τώρα"
        S_TIR="Στο στόχο 24ω"
        S_LOW_SHORT="χαμηλά"
        S_HIGH_SHORT="υψηλά"
        S_AVG="μ.ό."
        S_KEYS="q έξοδος · r ανανέωση · u μονάδες · m σίγαση"
        S_MUTED="ειδοποιήσεις σε σίγαση"
        S_OPEN="Άνοιγμα Nightscout"
        S_REFRESH="Ανανέωση"
        S_NOT_CONFIGURED="Δεν έχει οριστεί το NIGHTSCOUT_URL.
Αντίγραψε το nightscout.conf.example σε nightscout.conf και συμπλήρωσε τη διεύθυνση και το token."
    else
        S_TITLE="Nightscout Dashboard"
        S_UPDATED="updated"
        S_LOADING="Connecting to Nightscout…"
        S_ERR_FETCH="Cannot reach Nightscout, retrying soon"
        S_NO_DATA="No glucose readings found"
        S_STALE="NO RECENT DATA"
        S_URGENT_LOW="URGENT LOW"
        S_LOW="LOW"
        S_OK="IN RANGE"
        S_HIGH="HIGH"
        S_URGENT_HIGH="URGENT HIGH"
        S_FALLING="FALLING FAST"
        S_JUST_NOW="just now"
        S_MIN_AGO="%d min ago"
        S_H_AGO="%d h %d min ago"
        S_AT="at"
        S_GRAPH="Last %s"
        S_HOURS_FMT="%dh"
        S_MIN_FMT="%d min"
        S_NOW="now"
        S_TIR="In range 24h"
        S_LOW_SHORT="low"
        S_HIGH_SHORT="high"
        S_AVG="avg"
        S_KEYS="q quit · r refresh · u units · m mute alerts"
        S_MUTED="alerts muted"
        S_OPEN="Open Nightscout"
        S_REFRESH="Refresh"
        S_NOT_CONFIGURED="NIGHTSCOUT_URL is not set.
Copy nightscout.conf.example to nightscout.conf and fill in your address and token."
    fi
}

# ---------- Colors (plain ANSI codes, so widths are easy to measure) ----------
setup_colors() {
    if [ "$1" = "1" ]; then
        local e=$'\033'
        RST="${e}[0m"; BOLD="${e}[1m"; DIM="${e}[2m"; REV="${e}[7m"
        RED="${e}[31m"; GREEN="${e}[32m"; YELLOW="${e}[33m"; BLUE="${e}[34m"
        CYAN="${e}[36m"; GREY="${e}[90m"
    else
        RST=""; BOLD=""; DIM=""; REV=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; GREY=""
    fi
}

# ---------- Small helpers ----------
if date -r 0 +%s >/dev/null 2>&1; then BSD_DATE=1; else BSD_DATE=0; fi

clock_of() {   # epoch seconds -> HH:MM
    if [ "$BSD_DATE" = "1" ]; then date -r "$1" +%H:%M; else date -d "@$1" +%H:%M; fi
}

repeat_char() {   # char count -> REP
    printf -v REP '%*s' "$2" ''
    REP="${REP// /$1}"
}

vis_len() {   # visible width of a string with color codes -> VL
    local s
    s=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')
    VL=${#s}
}

to_units() {   # mg/dL integer (may be negative) -> U_TXT
    local v=$1 sign=""
    if [ "$v" -lt 0 ]; then sign="-"; v=$(( -v )); fi
    if [ "$UNITS" = "mmol" ]; then
        local q=$(( (v * 100000 + 90091) / 180182 ))   # mmol/L x10, rounded
        U_TXT="${sign}$((q / 10)).$((q % 10))"
    else
        U_TXT="${sign}${v}"
    fi
}

unit_label() { if [ "$UNITS" = "mmol" ]; then UNIT_TXT="mmol/L"; else UNIT_TXT="mg/dL"; fi; }

level_of() {   # mg/dL -> LVL
    local v=$1
    if   [ "$v" -lt "$URGENT_LOW" ];  then LVL="urgent_low"
    elif [ "$v" -lt "$LOW" ];         then LVL="low"
    elif [ "$v" -gt "$URGENT_HIGH" ]; then LVL="urgent_high"
    elif [ "$v" -gt "$HIGH" ];        then LVL="high"
    else LVL="ok"; fi
}

level_color() {   # level -> LC
    case "$1" in
        urgent_low|urgent_high) LC="${BOLD}${RED}" ;;
        low)  LC="$RED" ;;
        high) LC="$YELLOW" ;;
        *)    LC="$GREEN" ;;
    esac
}

level_text() {   # level -> LT
    case "$1" in
        urgent_low)  LT="$S_URGENT_LOW" ;;
        low)         LT="$S_LOW" ;;
        high)        LT="$S_HIGH" ;;
        urgent_high) LT="$S_URGENT_HIGH" ;;
        *)           LT="$S_OK" ;;
    esac
}

arrow_of() {   # Nightscout direction -> AR (all single-width characters)
    case "$1" in
        TripleUp)      AR="↑↑↑" ;;
        DoubleUp)      AR="↑↑" ;;
        SingleUp)      AR="↑" ;;
        FortyFiveUp)   AR="↗" ;;
        Flat)          AR="→" ;;
        FortyFiveDown) AR="↘" ;;
        SingleDown)    AR="↓" ;;
        DoubleDown)    AR="↓↓" ;;
        TripleDown)    AR="↓↓↓" ;;
        *)             AR="?" ;;
    esac
}

fmt_age() {   # seconds -> AGE_TXT (long) and AGE_SHORT
    local s=$1 m h
    [ "$s" -lt 0 ] && s=0
    m=$((s / 60))
    if [ "$s" -lt 60 ]; then
        AGE_TXT="$S_JUST_NOW"
    elif [ "$m" -lt 60 ]; then
        printf -v AGE_TXT "$S_MIN_AGO" "$m"
    else
        h=$((m / 60))
        printf -v AGE_TXT "$S_H_AGO" "$h" "$((m % 60))"
    fi
    if [ "$m" -lt 60 ]; then AGE_SHORT="${m}m"; else AGE_SHORT="$((m / 60))h"; fi
}

# ---------- Nightscout API ----------
api_get() {   # path -> JSON on stdout
    local path="$1" url sep='?'
    case "$path" in *\?*) sep='&' ;; esac
    url="${NIGHTSCOUT_URL%/}${path}"
    [ -n "$TOKEN" ] && url="${url}${sep}token=${TOKEN}"
    curl -sS -g --fail --max-time 10 "$url" 2>/dev/null
}

JQ_ENTRIES='
if type != "array" then error("not an array") else . end
| [ .[] | { d: ((.date // .mills) | tonumber?),
            s: (.sgv | tonumber?),
            dir: (.direction // "NONE"),
            dl: ((.delta | tonumber?) // null) } ]
| map(select(.s > 0))
| sort_by(-.d)
| .[]
| "\(.d | floor) \(.s | round) \(.dir | tostring | gsub(" "; "_")) \(if .dl == null then "x" else (.dl | round) end)"
'

E_COUNT=0
fetch_entries() {   # last 3 hours of readings (or at least the newest one) -> E_* arrays
    local json lines since d s dir dl i=0
    since=$(( ($(date +%s) - 3 * 3600) * 1000 ))
    json=$(api_get "/api/v1/entries/sgv.json?count=400&find[date][\$gte]=${since}") || return 1
    lines=$(printf '%s' "$json" | jq -r "$JQ_ENTRIES" 2>/dev/null) || return 1
    if [ -z "$lines" ]; then
        # Nothing in 3 hours: get the newest reading anyway so we can show how old it is.
        json=$(api_get "/api/v1/entries/sgv.json?count=1") || return 1
        lines=$(printf '%s' "$json" | jq -r "$JQ_ENTRIES" 2>/dev/null) || return 1
    fi
    E_DATE=(); E_SGV=(); E_DIR=(); E_DELTA=()
    while read -r d s dir dl; do
        [ -z "$d" ] && continue
        E_DATE[$i]=$d; E_SGV[$i]=$s; E_DIR[$i]=$dir; E_DELTA[$i]=$dl
        i=$((i + 1))
    done <<EOF
$lines
EOF
    E_COUNT=$i
    return 0
}

TIR_N=0
fetch_tir() {   # time in range for the last 24 hours -> TIR_*
    local json since out
    since=$(( ($(date +%s) - 86400) * 1000 ))
    json=$(api_get "/api/v1/entries/sgv.json?count=2000&find[date][\$gte]=${since}") || return 1
    out=$(printf '%s' "$json" | jq -r --argjson lo "$LOW" --argjson hi "$HIGH" '
        [ .[] | (.sgv | tonumber?) | select(. > 0) ] as $a
        | ($a | length) as $n
        | if $n == 0 then "0 0 0 0"
          else "\($n) \(([ $a[] | select(. < $lo) ] | length) * 100 / $n | round) \(([ $a[] | select(. > $hi) ] | length) * 100 / $n | round) \($a | add / $n | round)"
          end' 2>/dev/null) || return 1
    read -r TIR_N TIR_LOW TIR_HIGH TIR_AVG <<EOF
$out
EOF
    TIR_IN=$((100 - TIR_LOW - TIR_HIGH))
    return 0
}

fetch_props() {   # insulin and carbs on board, if the site has them -> IOB, COB
    local json out i c
    IOB=""; COB=""
    json=$(api_get "/api/v2/properties/iob,cob") || return 1
    out=$(printf '%s' "$json" | jq -r '"\(.iob.iob // "x") \(.cob.cob // "x")"' 2>/dev/null) || return 1
    read -r i c <<EOF
$out
EOF
    case "$i" in x|null|"") ;; *) printf -v IOB '%.2f' "$i" 2>/dev/null || IOB="" ;; esac
    case "$c" in x|null|"") ;; *) printf -v COB '%.0f' "$c" 2>/dev/null || COB="" ;; esac
}

# ---------- Big digits ----------
glyph() {   # character -> G (5 rows, X = filled)
    case "$1" in
        0) G="XXX|X X|X X|X X|XXX" ;;
        1) G=" X |XX | X | X |XXX" ;;
        2) G="XXX|  X|XXX|X  |XXX" ;;
        3) G="XXX|  X|XXX|  X|XXX" ;;
        4) G="X X|X X|XXX|  X|  X" ;;
        5) G="XXX|X  |XXX|  X|XXX" ;;
        6) G="XXX|X  |XXX|X X|XXX" ;;
        7) G="XXX|  X|  X|  X|  X" ;;
        8) G="XXX|X X|XXX|X X|XXX" ;;
        9) G="XXX|X X|XXX|  X|XXX" ;;
        .) G=" | | | |X" ;;
        -) G="   |   |XXX|   |   " ;;
        *) G="XXX|  X| XX|   | X " ;;
    esac
}

build_big() {   # text -> BIG[0..4], BIG_W
    local txt="$1" i r p sep=""
    BIG=("" "" "" "" "")
    for ((i = 0; i < ${#txt}; i++)); do
        glyph "${txt:i:1}"
        IFS='|' read -r -a GA <<< "$G"
        for r in 0 1 2 3 4; do
            p="${GA[$r]}"
            p="${p// /  }"
            p="${p//X/██}"
            BIG[$r]="${BIG[$r]}${sep}${p}"
        done
        sep="  "
    done
    BIG_W=${#BIG[0]}
}

# ---------- Graph of the last hours ----------
GMIN=40
GMAX=300
graph_row() {   # mg/dL -> GR (0 = top row)
    local v=$1
    [ "$v" -gt "$GMAX" ] && v=$GMAX
    [ "$v" -lt "$GMIN" ] && v=$GMIN
    GR=$(( ((GMAX - v) * (GH - 1) * 2 + (GMAX - GMIN)) / ((GMAX - GMIN) * 2) ))
}

build_graph() {   # E_* + COLS + GH -> GRAPH[], GRAPH_N, GRAPH_TITLE
    GRAPH=(); GRAPH_N=0
    [ "$GH" -lt 4 ] && return
    local cw=2 slots now_ms i s r age_min slot rh rl label lbl axis body pad pos h
    [ "$COLS" -lt 82 ] && cw=1
    slots=$(( (COLS - 9) / cw ))
    [ "$slots" -gt 36 ] && slots=36
    [ "$slots" -lt 12 ] && return
    now_ms=$(( $(date +%s) * 1000 ))

    local -a SV SR SC
    for ((i = 0; i < E_COUNT; i++)); do
        age_min=$(( (now_ms - E_DATE[i]) / 60000 ))
        [ "$age_min" -lt 0 ] && age_min=0
        slot=$(( slots - 1 - age_min / 5 ))
        [ "$slot" -lt 0 ] && break
        if [ -z "${SV[$slot]}" ]; then
            SV[$slot]=${E_SGV[i]}
            graph_row "${E_SGV[i]}"; SR[$slot]=$GR
            level_of "${E_SGV[i]}"; level_color "$LVL"; SC[$slot]=$LC
        fi
    done

    graph_row "$HIGH"; rh=$GR
    graph_row "$LOW";  rl=$GR
    repeat_char "┈" "$cw"; local dash="$REP"
    printf -v pad '%*s' "$((cw - 1))" ''

    for ((r = 0; r < GH; r++)); do
        label=""
        if   [ "$r" -eq "$rh" ]; then to_units "$HIGH"; label=$U_TXT
        elif [ "$r" -eq "$rl" ]; then to_units "$LOW";  label=$U_TXT
        elif [ "$r" -eq 0 ];     then to_units "$GMAX"; label=$U_TXT
        elif [ "$r" -eq $((GH - 1)) ]; then to_units "$GMIN"; label=$U_TXT
        fi
        if [ -n "$label" ]; then printf -v lbl '%6s ┤' "$label"; else lbl="       │"; fi
        body=""
        for ((s = 0; s < slots; s++)); do
            if [ -n "${SV[$s]}" ] && [ "${SR[$s]}" -eq "$r" ]; then
                body="${body}${SC[$s]}●${RST}${pad}"
            elif [ "$r" -eq "$rh" ] || [ "$r" -eq "$rl" ]; then
                body="${body}${GREY}${dash}${RST}"
            else
                body="${body}${pad} "
            fi
        done
        GRAPH[$GRAPH_N]="${GREY}${lbl}${RST}${body}"
        GRAPH_N=$((GRAPH_N + 1))
    done

    repeat_char "─" "$((slots * cw))"
    GRAPH[$GRAPH_N]="${GREY}       └${REP}${RST}"
    GRAPH_N=$((GRAPH_N + 1))

    # Time labels under the axis
    printf -v axis '%*s' "$((8 + slots * cw))" ''
    for h in 3 2 1; do
        slot=$(( slots - 1 - h * 12 ))
        [ "$slot" -eq -1 ] && slot=0
        [ "$slot" -lt 0 ] && continue
        pos=$(( 8 + slot * cw ))
        lbl="-${h}h"
        axis="${axis:0:pos}${lbl}${axis:pos+${#lbl}}"
    done
    pos=$(( 8 + slots * cw - ${#S_NOW} ))
    axis="${axis:0:pos}${S_NOW}"
    GRAPH[$GRAPH_N]="${GREY}${axis}${RST}"
    GRAPH_N=$((GRAPH_N + 1))

    local win=$((slots * 5)) wtxt
    if [ $((win % 60)) -eq 0 ]; then printf -v wtxt "$S_HOURS_FMT" $((win / 60))
    else printf -v wtxt "$S_MIN_FMT" "$win"; fi
    printf -v GRAPH_TITLE "$S_GRAPH" "$wtxt"
}

# ---------- Work out everything that only changes when data changes ----------
compute_view() {
    [ "$E_COUNT" -gt 0 ] || return
    local i gap
    CUR_SGV=${E_SGV[0]}
    CUR_DATE=${E_DATE[0]}
    CUR_DIR=${E_DIR[0]}

    # Change vs. about 5 minutes ago: Nightscout's own value if it sent one.
    DELTA=""
    if [ "${E_DELTA[0]}" != "x" ]; then
        DELTA=${E_DELTA[0]}
    else
        for ((i = 1; i < E_COUNT && i < 20; i++)); do
            gap=$(( (E_DATE[0] - E_DATE[i]) / 1000 ))
            if [ "$gap" -ge 180 ] && [ "$gap" -le 420 ]; then
                DELTA=$(( E_SGV[0] - E_SGV[i] )); break
            fi
            [ "$gap" -gt 420 ] && break
        done
    fi
    if [ -z "$DELTA" ]; then DELTA_TXT="?"
    elif [ "$DELTA" -eq 0 ]; then DELTA_TXT="±0"
    else
        to_units "$DELTA"
        if [ "$DELTA" -gt 0 ]; then DELTA_TXT="+${U_TXT}"; else DELTA_TXT="$U_TXT"; fi
    fi

    level_of "$CUR_SGV"; CUR_LVL=$LVL
    level_text "$CUR_LVL"; CUR_LT=$LT
    arrow_of "$CUR_DIR"; CUR_AR=$AR
    to_units "$CUR_SGV"; CUR_TXT=$U_TXT
    unit_label
    READING_CLOCK=$(clock_of $((CUR_DATE / 1000)))
    build_big "$CUR_TXT"

    if [ "$MODE" = "dashboard" ] || [ "$MODE" = "once" ]; then
        COLS=$(tput cols 2>/dev/null || echo 80)
        ROWS=$(tput lines 2>/dev/null || echo 30)
        GH=$(( ROWS - 22 ))
        [ "$GH" -gt 10 ] && GH=10
        build_graph
    fi
}

# ---------- Alerts ----------
LAST_ALERT_STATE=""
LAST_ALERT_TIME=0

notify() {   # title message urgent(0/1)
    local sound="Glass"
    [ "$3" = "1" ] && sound="Sosumi"
    if [ "$(uname)" = "Darwin" ]; then
        osascript -e "display notification \"$2\" with title \"$1\" sound name \"$sound\"" >/dev/null 2>&1 &
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "$1" "$2" >/dev/null 2>&1 &
    fi
    [ "$MODE" = "dashboard" ] && printf '\a'
}

check_alerts() {
    [ "$ALERTS" = "1" ] || return
    [ "$E_COUNT" -gt 0 ] || return
    local now state="" msg urgent=0 age
    now=$(date +%s)
    age=$(( now - CUR_DATE / 1000 ))
    if [ "$age" -ge $((STALE_MIN * 60)) ]; then
        state="stale"; fmt_age "$age"; msg="${S_STALE} (${AGE_TXT})"; urgent=1
    elif [ "$CUR_LVL" != "ok" ]; then
        state="$CUR_LVL"; msg="${CUR_LT}: ${CUR_TXT} ${CUR_AR} ${DELTA_TXT} ${UNIT_TXT}"
        case "$CUR_LVL" in urgent_*) urgent=1 ;; esac
    else
        case "$CUR_DIR" in
            DoubleDown|TripleDown) state="falling"; msg="${S_FALLING}: ${CUR_TXT} ${CUR_AR} ${DELTA_TXT} ${UNIT_TXT}" ;;
        esac
    fi
    if [ -z "$state" ]; then
        LAST_ALERT_STATE=""
        return
    fi
    if [ "$state" != "$LAST_ALERT_STATE" ] || [ $((now - LAST_ALERT_TIME)) -ge $((ALERT_REPEAT_MIN * 60)) ]; then
        notify "Nightscout" "$msg" "$urgent"
        LAST_ALERT_STATE="$state"
        LAST_ALERT_TIME=$now
    fi
}

# ---------- Drawing ----------
EL=$'\033[K'
add_line() { OUT="${OUT}$1${EL}"$'\n'; OUT_N=$((OUT_N + 1)); }

add_center() {
    local pad=0
    vis_len "$1"
    [ "$VL" -lt "$COLS" ] && pad=$(( (COLS - VL) / 2 ))
    printf -v SP '%*s' "$pad" ''
    add_line "${SP}$1"
}

render() {
    local now clock left right gap hr i pad side color status
    COLS=$(tput cols 2>/dev/null || echo 80)
    now=$(date +%s)
    clock=$(date +%H:%M:%S)
    OUT=""; OUT_N=0

    # Header
    left=" ${clock}  ${S_TITLE}"
    if [ "$SHOW_URL" = "1" ]; then
        local host="${NIGHTSCOUT_URL#*://}"; host="${host%%/*}"
        left="${left} · ${host}"
    fi
    right=""
    [ -n "$LAST_FETCH_CLOCK" ] && right="${S_UPDATED} ${LAST_FETCH_CLOCK} "
    [ "$ALERTS" = "1" ] || right="${S_MUTED} · ${right}"
    gap=$(( COLS - ${#left} - ${#right} ))
    [ "$gap" -lt 1 ] && gap=1
    printf -v SP '%*s' "$gap" ''
    add_line "${BOLD}${CYAN}${left}${RST}${SP}${GREY}${right}${RST}"
    repeat_char "─" "$COLS"; hr="${BLUE}${REP}${RST}"
    add_line "$hr"

    if [ "$E_COUNT" -eq 0 ]; then
        add_line ""
        if [ -z "$LAST_FETCH_CLOCK" ] && [ "$FETCH_OK" != "0" ]; then add_center "$S_LOADING"
        elif [ "$FETCH_OK" = "0" ]; then add_center "${YELLOW}⚠ ${S_ERR_FETCH}${RST}"
        else add_center "${YELLOW}${S_NO_DATA}${RST}"; fi
        add_line ""
        add_line "$hr"
        add_line "${GREY} ${S_KEYS}${RST}"
        printf '%s' "${HOME_SEQ}${OUT}${CLEAR_REST}"
        return
    fi

    local age=$(( now - CUR_DATE / 1000 )) stale=0
    [ "$age" -ge $((STALE_MIN * 60)) ] && stale=1
    fmt_age "$age"
    if [ "$stale" = "1" ]; then color="$GREY"; else level_color "$CUR_LVL"; color="$LC"; fi

    # Big number with arrow, change and units beside it
    add_line ""
    local -a SIDE
    SIDE=("" "${BOLD}${CUR_AR}${RST}  ${BOLD}${DELTA_TXT}${RST}" "${GREY}${UNIT_TXT}${RST}" "" "")
    pad=$(( (COLS - BIG_W - 14) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf -v SP '%*s' "$pad" ''
    for i in 0 1 2 3 4; do
        add_line "${SP}${color}${BIG[$i]}${RST}    ${SIDE[$i]}"
    done
    add_line ""

    # Status line
    if [ "$stale" = "1" ]; then
        status="${REV}${RED} ⚠ ${S_STALE} · ${AGE_TXT} ${RST}"
    else
        level_color "$CUR_LVL"
        status="${LC}${BOLD}${CUR_LT}${RST}${GREY} · ${AGE_TXT} (${S_AT} ${READING_CLOCK})${RST}"
    fi
    add_center "$status"
    if [ -n "$IOB" ] || [ -n "$COB" ]; then
        local extra=""
        [ -n "$IOB" ] && extra="IOB ${BOLD}${IOB}${RST} U"
        [ -n "$IOB" ] && [ -n "$COB" ] && extra="${extra}${GREY}  ·  ${RST}"
        [ -n "$COB" ] && extra="${extra}COB ${BOLD}${COB}${RST} g"
        add_center "$extra"
    fi
    [ "$FETCH_OK" = "0" ] && add_center "${YELLOW}⚠ ${S_ERR_FETCH}${RST}"
    add_line "$hr"

    # Graph
    if [ "$GRAPH_N" -gt 0 ]; then
        add_line " ${BOLD}${GRAPH_TITLE}${RST}"
        for ((i = 0; i < GRAPH_N; i++)); do add_line "${GRAPH[$i]}"; done
    fi

    # Time in range
    if [ "$TIR_N" -gt 0 ]; then
        local bw=24 lw hw iw avg_txt gmi
        lw=$(( TIR_LOW * bw / 100 )); hw=$(( TIR_HIGH * bw / 100 ))
        [ "$TIR_LOW" -gt 0 ] && [ "$lw" -eq 0 ] && lw=1
        [ "$TIR_HIGH" -gt 0 ] && [ "$hw" -eq 0 ] && hw=1
        iw=$(( bw - lw - hw ))
        repeat_char "█" "$lw"; local bl="$REP"
        repeat_char "█" "$iw"; local bi="$REP"
        repeat_char "█" "$hw"; local bh="$REP"
        to_units "$TIR_AVG"; avg_txt=$U_TXT
        gmi=$(( (331000 + 2392 * TIR_AVG + 5000) / 10000 ))
        add_line ""
        add_line " ${BOLD}${S_TIR}${RST}  ${RED}${bl}${GREEN}${bi}${YELLOW}${bh}${RST}  ${GREEN}${BOLD}${TIR_IN}%${RST}${GREY}  ${S_LOW_SHORT} ${TIR_LOW}% · ${S_HIGH_SHORT} ${TIR_HIGH}% · ${S_AVG} ${avg_txt} · GMI $((gmi / 10)).$((gmi % 10))%${RST}"
    fi

    add_line ""
    add_line "${GREY} ${S_KEYS}${RST}"
    printf '%s' "${HOME_SEQ}${OUT}${CLEAR_REST}"
}

# ---------- Modes ----------
FETCH_OK=""
LAST_FETCH_CLOCK=""

do_fetch() {
    if fetch_entries; then
        FETCH_OK=1
        LAST_FETCH_CLOCK=$(date +%H:%M:%S)
        fetch_props
    else
        FETCH_OK=0
    fi
    compute_view
    check_alerts
}

cleanup() {
    printf '\033[?25h'          # show cursor
    tput rmcup 2>/dev/null      # leave the alternate screen
}

run_dashboard() {
    local now next_fetch=0 next_tir=0 key
    HOME_SEQ=$'\033[H'
    CLEAR_REST=$'\033[J'
    tput smcup 2>/dev/null
    printf '\033[?25l\033[2J'   # hide cursor, clear
    trap cleanup EXIT
    trap 'exit 0' INT TERM
    trap 'RESIZED=1' WINCH
    render
    while :; do
        now=$(date +%s)
        if [ "$now" -ge "$next_fetch" ]; then
            do_fetch
            next_fetch=$(( $(date +%s) + INTERVAL ))
        fi
        if [ "$now" -ge "$next_tir" ] && [ "$FETCH_OK" = "1" ]; then
            if fetch_tir; then next_tir=$((now + 300)); else next_tir=$((now + 60)); fi
        fi
        if [ "$RESIZED" = "1" ]; then
            RESIZED=0
            compute_view
            printf '\033[2J'
        fi
        render
        key=""
        if [ -t 0 ]; then read -rsn1 -t 1 key; else sleep 1; fi
        case "$key" in
            q|Q) exit 0 ;;
            r|R) next_fetch=0; next_tir=0 ;;
            u|U) if [ "$UNITS" = "mmol" ]; then UNITS="mgdl"; else UNITS="mmol"; fi; compute_view ;;
            m|M) if [ "$ALERTS" = "1" ]; then ALERTS=0; else ALERTS=1; LAST_ALERT_STATE=""; fi ;;
        esac
    done
}

run_once() {
    HOME_SEQ=""; CLEAR_REST=""
    do_fetch
    [ "$FETCH_OK" = "1" ] && fetch_tir
    render
}

run_line() {
    if ! fetch_entries; then echo "NS ⚠"; exit 1; fi
    if [ "$E_COUNT" -eq 0 ]; then echo "NS --"; exit 0; fi
    compute_view
    local age=$(( $(date +%s) - CUR_DATE / 1000 ))
    fmt_age "$age"
    if [ "$age" -ge $((STALE_MIN * 60)) ]; then
        echo "⚠ ${CUR_TXT} (${AGE_SHORT})"
    elif [ "$age" -ge 360 ]; then
        echo "${CUR_TXT} ${CUR_AR} ${DELTA_TXT} (${AGE_SHORT})"
    else
        echo "${CUR_TXT} ${CUR_AR} ${DELTA_TXT}"
    fi
}

run_swiftbar() {
    # SwiftBar runs this every few seconds; remember the last alert in a small file.
    local state_file="${TMPDIR:-/tmp}/nightscout-dash-alert"
    [ -f "$state_file" ] && read -r LAST_ALERT_STATE LAST_ALERT_TIME < "$state_file"
    [ -z "$LAST_ALERT_TIME" ] && LAST_ALERT_TIME=0

    if ! fetch_entries; then
        echo "NS ⚠ | color=#8e8e93"
        echo "---"
        echo "$S_ERR_FETCH"
        echo "${S_REFRESH} | refresh=true"
        exit 0
    fi
    if [ "$E_COUNT" -eq 0 ]; then
        echo "NS -- | color=#8e8e93"; echo "---"; echo "$S_NO_DATA"; exit 0
    fi
    compute_view
    fetch_props
    check_alerts
    printf '%s %s\n' "$LAST_ALERT_STATE" "$LAST_ALERT_TIME" > "$state_file"

    local age=$(( $(date +%s) - CUR_DATE / 1000 )) hex
    fmt_age "$age"
    case "$CUR_LVL" in
        ok) hex="#34c759" ;;
        high) hex="#ff9f0a" ;;
        *) hex="#ff3b30" ;;
    esac
    if [ "$age" -ge $((STALE_MIN * 60)) ]; then
        echo "⚠ ${CUR_TXT} (${AGE_SHORT}) | color=#8e8e93"
    else
        echo "${CUR_TXT} ${CUR_AR} ${DELTA_TXT} | color=${hex}"
    fi
    echo "---"
    echo "${CUR_LT} · ${AGE_TXT} (${S_AT} ${READING_CLOCK})"
    echo "${CUR_TXT} ${UNIT_TXT}  ${CUR_AR}  ${DELTA_TXT}"
    if [ -n "$IOB" ] || [ -n "$COB" ]; then
        local extra=""
        [ -n "$IOB" ] && extra="IOB ${IOB} U"
        [ -n "$IOB" ] && [ -n "$COB" ] && extra="${extra} · "
        [ -n "$COB" ] && extra="${extra}COB ${COB} g"
        echo "$extra"
    fi
    echo "---"
    echo "${S_OPEN} | href=${NIGHTSCOUT_URL}"
    echo "${S_REFRESH} | refresh=true"
}

# ---------- Start ----------
load_strings

for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing '$cmd'. On macOS: brew install $cmd" >&2
        exit 1
    fi
done

if [ -z "$NIGHTSCOUT_URL" ]; then
    echo "$S_NOT_CONFIGURED" >&2
    exit 1
fi

case "$MODE" in
    dashboard) setup_colors 1; run_dashboard ;;
    once)      if [ -t 1 ]; then setup_colors 1; else setup_colors 0; fi; run_once ;;
    line)      setup_colors 0; run_line ;;
    swiftbar)  setup_colors 0; run_swiftbar ;;
esac
