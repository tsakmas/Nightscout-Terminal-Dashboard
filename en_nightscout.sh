#!/usr/bin/env bash

# --- SETTINGS ---
NIGHTSCOUT_URL="PUT YOUR NIGHTSCOUT URL HERE"
TOKEN="PUT THE TOKEN YOU GENERATED HERE"
API_ENDPOINT="/api/v1/entries.json?count=10&token=${TOKEN}" # Fetch more for the history
SLEEP_INTERVAL=30  # Check every 30 seconds
# -----------------

# Terminal colors/controls
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Variables to store previous BG value and previous timestamp
PREV_BG=0
PREV_TIME=0
HISTORY_LOG="" # Stores the last history lines
DIFF_BG_FMT="" # Must be set before the loop
DISPLAY_BG="N/A"

# --- HELPER FUNCTIONS ---

# Dynamically compute the center column for a given string length
get_center_col() {
    local COLS=$(tput cols 2>/dev/null || echo 80)
    local STRLEN=$1
    echo $(((COLS - STRLEN) / 2))
}

# Determine trend arrow emoji by direction
get_trend_arrow() {
    local direction="$1"
    case "$direction" in
        "TripleUp") echo "⬆️⬆️⬆️" ;;
        "DoubleUp") echo "⬆️⬆️" ;;
        "SingleUp") echo "⬆️" ;;
        "FortyFiveUp") echo "↗️" ;;
        "Flat") echo "➡️" ;;
        "FortyFiveDown") echo "↘️" ;;
        "SingleDown") echo "⬇️" ;;
        "DoubleDown") echo "⬇️⬇️" ;;
        "TripleDown") echo "⬇️⬇️⬇️" ;;
        "NOT COMPUTABLE" | "NONE" | "null") echo "⚫" ;;
        *) echo "?" ;;
    esac
}

# Compute human-readable time difference from milliseconds ago
get_time_diff() {
    local ms_ago="$1"

    # SAFETY: Ensure ms_ago is a non-negative number
    if ! [[ "$ms_ago" =~ ^[0-9]+$ ]] || [ "$ms_ago" -lt 0 ]; then
        echo "--:--"
        return
    fi

    local seconds=$((ms_ago / 1000))

    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m"
    else
        echo "$((seconds / 3600))h"
    fi
}

# Determine BG color (with built-in protection)
get_bg_color() {
    local bg="$1"

    # CHECK: If not a number or zero, return error/N/A color
    if ! [[ "$bg" =~ ^[0-9]+$ ]] || [ "$bg" -eq 0 ]; then
        echo "${MAGENTA}"
        return
    fi

    if [ "$bg" -gt 250 ]; then
        echo "${RED}"
    elif [ "$bg" -gt 180 ]; then
        echo "${YELLOW}"
    elif [ "$bg" -gt 80 ]; then
        echo "${GREEN}"
    else
        echo "${RED}"
    fi
}

# --- MAIN MONITORING LOOP ---

while true; do
    # 1. Clear screen and reset cursor to (0, 0)
    clear
    tput cup 0 0

    # Get current system time (use gdate if available, otherwise date)
    LIVE_CLOCK=$(gdate +"%H:%M:%S" 2>/dev/null || date +"%H:%M:%S")

    # 2. Header information (Top-left)
    echo "${CYAN}${BOLD}[ ${LIVE_CLOCK} ] Nightscout Monitor | URL: ${NIGHTSCOUT_URL}${NORMAL}"
    COLS=$(tput cols 2>/dev/null || echo 80)
    printf "${BLUE}%.0s" $(seq 1 $COLS) # Blue divider line
    tput cup 2 0

    # 3. Fetch and validate data
    DATA=$(curl -s "${NIGHTSCOUT_URL}${API_ENDPOINT}")

    # Curl error checking
    if [[ "$DATA" != "["* ]] || [[ -z "$DATA" ]]; then
        tput cup 4 $(get_center_col 40)
        echo "${RED}⚠️ ERROR: Could not retrieve the expected JSON data. Retrying...${NORMAL}"
        sleep 5
        continue
    fi

    # Process data (get values as-is, including possible null)
    CURRENT_BG=$(echo "$DATA" | jq -r '.[0].sgv')
    CURRENT_TIME_MS=$(echo "$DATA" | jq -r '.[0].date') # Correct field is .date
    CURRENT_DIR=$(echo "$DATA" | jq -r '.[0].direction')

    # ----------------------------------------------------
    # Calculations and data protection
    # ----------------------------------------------------

    # Use the helper C program for reliable time (MUST have ./get_millis)
    NOW=$(./get_millis)

    # Defaults for display
    TIME_AGO_FMT="--:--"
    ARROW=$(get_trend_arrow "$CURRENT_DIR")
    BG_COLOR=$(get_bg_color "$CURRENT_BG") # Safe call

    # FIRST CHECK: If CURRENT_BG is NOT a number, set display vars and retry later
    if ! [[ $CURRENT_BG =~ ^[0-9]+$ ]]; then
        DISPLAY_BG="N/A"
        DIFF_BG_FMT="${MAGENTA}--${NORMAL}"
        
        tput cup 4 $(get_center_col 40)
        echo "${YELLOW}⏳ No recent BG data found. Retrying in ${SLEEP_INTERVAL}s.${NORMAL}"
        sleep $SLEEP_INTERVAL
        continue
    fi

    # If CURRENT_BG IS a number, proceed with time/diff calculations

    # Compute time difference (safe if CURRENT_TIME_MS is numeric)
    TIME_AGO_MS=$((NOW - CURRENT_TIME_MS))
    TIME_AGO_FMT=$(get_time_diff "$TIME_AGO_MS")
    DISPLAY_BG="$CURRENT_BG" # Set displayed BG

    # --- Update and display status (vertically centered) ---

    # Recompute difference and history only on new data (and only when BG is numeric)
    if [ "$CURRENT_TIME_MS" -ne "$PREV_TIME" ]; then
        
        # Difference from last reading (safe here)
        DIFF_BG_RAW=$((CURRENT_BG - PREV_BG))
        
        # Color formatted version
        if [ "$PREV_BG" -ne 0 ]; then
            if [ "$DIFF_BG_RAW" -gt 0 ]; then
                DIFF_BG_FMT="${GREEN}+${DIFF_BG_RAW}${NORMAL}"
            else
                DIFF_BG_FMT="${RED}${DIFF_BG_RAW}${NORMAL}"
            fi
        else
            DIFF_BG_FMT="${MAGENTA}N/A${NORMAL}"
        fi

        # Build status line for the history (horizontal)
        HISTORY_STATUS_LINE="BG: ${BG_COLOR}${BOLD}${CURRENT_BG}${NORMAL} | Diff: ${DIFF_BG_RAW} | Trend: ${ARROW} | Age: ${TIME_AGO_FMT}"
        
        # gdate or date for history time (gdate if present, date otherwise)
        HISTORY_TIME=$(gdate -d @$((CURRENT_TIME_MS / 1000)) +%H:%M:%S 2>/dev/null || date -r $((CURRENT_TIME_MS / 1000)) +%H:%M:%S)
        HISTORY_LINE="Time: ${HISTORY_TIME} | ${HISTORY_STATUS_LINE}"

        # Prepend new line to history log (keep last 10)
        HISTORY_LOG=$(echo -e "${MAGENTA}>> ${NORMAL}${HISTORY_LINE}\n$HISTORY_LOG" | head -n 10)

        # Update previous values
        PREV_BG=$CURRENT_BG
        PREV_TIME=$CURRENT_TIME_MS
    fi
    # ----------------------------------------------------

    # Ensure DIFF_BG_FMT has a value even if history wasn't updated (first run)
    if [ -z "$DIFF_BG_FMT" ] && [ "$CURRENT_BG" != "null" ]; then
        if [ "$PREV_BG" -ne 0 ]; then
            DIFF_RAW=$((CURRENT_BG - PREV_BG))
            if [ "$DIFF_RAW" -gt 0 ]; then
                DIFF_BG_FMT="${GREEN}+${DIFF_RAW}${NORMAL}"
            else
                DIFF_BG_FMT="${RED}${DIFF_RAW}${NORMAL}"
            fi
        else
            DIFF_BG_FMT="${MAGENTA}N/A${NORMAL}"
        fi
    fi

    # 4. Display current status lines (roughly centered)

    # Lines to print
    HEADER_LINE="${BOLD}--- CURRENT STATUS ---${NORMAL}"
    BG_LINE="BG LEVEL: ${BG_COLOR}${BOLD}${DISPLAY_BG}${NORMAL}"
    DIFF_LINE="CHANGE: ${DIFF_BG_FMT}"
    TREND_LINE="TREND: ${ARROW} (${CURRENT_DIR})"
    AGE_LINE="DATA AGE: ${TIME_AGO_FMT} ago"

    # Use a fixed width 40 for safe centering
    MAX_TEXT_WIDTH=40

    # Print lines sequentially with increasing row numbers
    START_ROW=4 # Start below header

    tput cup $START_ROW $(get_center_col $MAX_TEXT_WIDTH)
    echo "$HEADER_LINE"

    tput cup $((START_ROW + 1)) $(get_center_col $MAX_TEXT_WIDTH)
    echo "$BG_LINE"

    tput cup $((START_ROW + 2)) $(get_center_col $MAX_TEXT_WIDTH)
    echo "$DIFF_LINE"

    tput cup $((START_ROW + 3)) $(get_center_col $MAX_TEXT_WIDTH)
    echo "$TREND_LINE"

    tput cup $((START_ROW + 4)) $(get_center_col $MAX_TEXT_WIDTH)
    echo "$AGE_LINE"

    # 5. Display history (bottom, left-aligned)
    # Start printing the history divider 6 rows below the header
    HISTORY_START_ROW=$((START_ROW + 6))

    tput cup $HISTORY_START_ROW 0
    printf "${BLUE}%.0s" $(seq 1 $COLS) # Blue divider line

    tput cup $((HISTORY_START_ROW + 1)) 0
    echo "${BOLD}History Log (Last 10 Readings):${NORMAL}"

    tput cup $((HISTORY_START_ROW + 2)) 0
    echo -e "$HISTORY_LOG" # echo -e for proper newlines

    # 6. Wait for the next check interval
    sleep $SLEEP_INTERVAL

done
