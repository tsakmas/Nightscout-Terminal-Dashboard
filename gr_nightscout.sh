#!/usr/bin/env bash

# --- ΡΥΘΜΙΣΕΙΣ ---
NIGHTSCOUT_URL="ΕΔΩ ΠΡΟΣΘΕΣΕ ΤΟ URL ΤΟΥ NIGHTSCOUT"
TOKEN="ΕΔΩ ΠΡΟΣΘΕΣΕ ΤΟ TOKEN ΠΟΥ ΔΗΜΙΟΥΡΓΗΣΕΣ"
API_ENDPOINT="/api/v1/entries.json?count=10&token=${TOKEN}" # Ανάκτηση περισσότερων για το ιστορικό
SLEEP_INTERVAL=30  # Έλεγχος κάθε 30 δευτερόλεπτ
# ---------------------

# Χρώματα/Χειριστήρια Τερματικού
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Μεταβλητές για την αποθήκευση της προηγούμενης τιμής γλυκόζης και του προηγούμενου χρόνου
PREV_BG=0
PREV_TIME=0
HISTORY_LOG="" # Αποθηκεύει τις τελευταίες γραμμές ιστορικού
DIFF_BG_FMT="" # Χρειάζεται να οριστεί πριν από τον βρόχο
DISPLAY_BG="N/A"

# --- ΒΟΗΘΗΤΙΚΕΣ ΣΥΝΑΡΤΗΣΕΙΣ ---

# Συνάρτηση για τον δυναμικό υπολογισμό της κεντρικής στήλης
get_center_col() {
    local COLS=$(tput cols 2>/dev/null || echo 80)
    local STRLEN=$1
    echo $(( (COLS - STRLEN) / 2 ))
}

# Συνάρτηση για τον προσδιορισμό του βέλους τάσης
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
        "TripleDown") echo "⤵️" ;;
        "NOT COMPUTABLE" | "NONE" | "null") echo "⚫" ;;
        *) echo "?" ;;
    esac
}

# Συνάρτηση για τον προσδιορισμό της διαφοράς ώρας
get_time_diff() {
    local ms_ago="$1"
    
    # ΠΡΟΣΤΑΣΙΑ: Βεβαιωθείτε ότι το ms_ago είναι αριθμός και θετικό
    if ! [[ "$ms_ago" =~ ^[0-9]+$ ]] || [ "$ms_ago" -lt 0 ]; then
        echo "--:--"
        return
    fi
    
    local seconds=$((ms_ago / 1000))

    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}δ"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))λ"
    else
        echo "$((seconds / 3600))ώ"
    fi
}

# Συνάρτηση για τον προσδιορισμό του χρώματος BG (ΠΡΟΣΤΑΣΙΑ ΕΝΣΩΜΑΤΩΜΕΝΗ)
get_bg_color() {
    local bg="$1"
    
    # ΕΛΕΓΧΟΣ: Εάν δεν είναι αριθμός ή είναι μηδέν, επιστρέφουμε χρώμα σφάλματος/N/A
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

# --- ΚΥΡΙΟΣ ΒΡΟΧΟΣ ΠΑΡΑΚΟΛΟΥΘΗΣΗΣ ---

while true; do
    # 1. Καθαρισμός οθόνης και επαναφορά του δρομέα στο (0, 0)
    clear
    tput cup 0 0

    # Λήψη του τρέχοντος χρόνου συστήματος (ΧΡΗΣΗ gdate ή ./get_millis)
    # Χρησιμοποιήστε gdate σε Mac αν έχετε coreutils, αλλιώς date (σε Linux)
    LIVE_CLOCK=$(gdate +"%H:%M:%S" 2>/dev/null || date +"%H:%M:%S")

    # 2. Εκτύπωση Πληροφοριών Κεφαλίδας (Επάνω Αριστερά)
    echo "${CYAN}${BOLD}[ ${LIVE_CLOCK} ] Παρακολούθηση Nightscout | URL: ${NIGHTSCOUT_URL}${NORMAL}"
    COLS=$(tput cols 2>/dev/null || echo 80)
    printf "${BLUE}%.0s" $(seq 1 $COLS) # Εκτύπωση μπλε διαχωριστικής γραμμής
    tput cup 2 0

    # 3. Ανάκτηση και επικύρωση δεδομένων
    DATA=$(curl -s "${NIGHTSCOUT_URL}${API_ENDPOINT}")

    # Έλεγχος Σφάλματος Curl
    if [[ "$DATA" != "["* ]] || [[ -z "$DATA" ]]; then
        tput cup 4 $(get_center_col 40)
        echo "${RED}⚠️ ΣΦΑΛΜΑ: Δεν ήταν δυνατή η ανάκτηση των αναμενόμενων δεδομένων JSON. Επανάληψη...${NORMAL}"
        sleep 5
        continue
    fi

    # Επεξεργασία Δεδομένων (Παίρνουμε τις τιμές όπως είναι, συμπεριλαμβανομένου του "null")
    CURRENT_BG=$(echo "$DATA" | jq -r '.[0].sgv')
    CURRENT_TIME_MS=$(echo "$DATA" | jq -r '.[0].date') # Διορθώθηκε από '.gdate' σε '.date'
    CURRENT_DIR=$(echo "$DATA" | jq -r '.[0].direction')
    
    # ----------------------------------------------------
    # Υπολογισμοί και Προστασία Δεδομένων
    # ----------------------------------------------------
    
    # Χρήση του C προγράμματος για αξιόπιστο χρόνο (ΠΡΕΠΕΙ να υπάρχει το ./get_millis)
    NOW=$(./get_millis)
    
    # Προεπιλογή για την εμφάνιση
    TIME_AGO_FMT="--:--"
    ARROW=$(get_trend_arrow "$CURRENT_DIR")
    BG_COLOR=$(get_bg_color "$CURRENT_BG") # Ασφαλής κλήση

    # ΠΡΩΤΟΣ ΕΛΕΓΧΟΣ: Εάν το CURRENT_BG ΔΕΝ είναι αριθμός, τότε ρυθμίζουμε τις μεταβλητές εμφάνισης
    if ! [[ $CURRENT_BG =~ ^[0-9]+$ ]]; then
        DISPLAY_BG="N/A"
        DIFF_BG_FMT="${MAGENTA}--${NORMAL}"
        # Προχωράμε στην επανεμφάνιση με τα N/A
        
        tput cup 4 $(get_center_col 40)
        echo "${YELLOW}⏳ Δεν βρέθηκαν πρόσφατα δεδομένα BG. Επανάληψη σε ${SLEEP_INTERVAL}δ.${NORMAL}"
        sleep $SLEEP_INTERVAL
        continue
    fi
    
    # Εάν το CURRENT_BG ΕΙΝΑΙ αριθμός, προχωράμε στους υπολογισμούς χρόνου/διαφοράς
    
    # Υπολογισμός διαφοράς ώρας (Είναι ασφαλές, εφόσον το CURRENT_TIME_MS είναι αριθμός)
    TIME_AGO_MS=$((NOW - CURRENT_TIME_MS))
    TIME_AGO_FMT=$(get_time_diff "$TIME_AGO_MS")
    DISPLAY_BG="$CURRENT_BG" # Ορίζεται η τιμή εμφάνισης

    # --- Ενημέρωση και Εμφάνιση Κατάστασης (Κεντραρισμένα Κατακόρυφα) ---

    # Επαναϋπολογισμός Διαφοράς και Ιστορικού μόνο σε νέα δεδομένα (και εφόσον το BG είναι αριθμός)
    if [ "$CURRENT_TIME_MS" -ne "$PREV_TIME" ]; then
        
        # Υπολογισμός της διαφοράς από την προηγούμενη ανάγνωση (ΑΣΦΑΛΕΣ ΕΔΩ)
        DIFF_BG_RAW=$((CURRENT_BG - PREV_BG))
        
        # Διαμορφωμένη έκδοση με χρώμα
        if [ "$PREV_BG" -ne 0 ]; then
            if [ "$DIFF_BG_RAW" -gt 0 ]; then
                DIFF_BG_FMT="${GREEN}+${DIFF_BG_RAW}${NORMAL}"
            else
                DIFF_BG_FMT="${RED}${DIFF_BG_RAW}${NORMAL}"
            fi
        else
            DIFF_BG_FMT="${MAGENTA}N/A${NORMAL}"
        fi

        # Διαμόρφωση της πλήρους γραμμής κατάστασης για το ιστορικό (οριζόντια)
        HISTORY_STATUS_LINE="BG: ${BG_COLOR}${BOLD}${CURRENT_BG}${NORMAL} | Διαφ: ${DIFF_BG_RAW} | Τάση: ${ARROW} | Ενημ: ${TIME_AGO_FMT}"
        
        # gdate ή date για την ώρα στο ιστορικό (gdate αν υπάρχει, date αλλιώς)
        HISTORY_TIME=$(gdate -d @$((CURRENT_TIME_MS / 1000)) +%H:%M:%S 2>/dev/null || date -r $((CURRENT_TIME_MS / 1000)) +%H:%M:%S)
        HISTORY_LINE="Ώρα: ${HISTORY_TIME} | ${HISTORY_STATUS_LINE}"

        # Προσθήκη νέας γραμμής στην κορυφή του ιστορικού καταγραφής
        HISTORY_LOG=$(echo -e "${MAGENTA}>> ${NORMAL}${HISTORY_LINE}\n$HISTORY_LOG" | head -n 10)

        # Ενημέρωση των προηγούμενων τιμών
        PREV_BG=$CURRENT_BG
        PREV_TIME=$CURRENT_TIME_MS
    fi
    # ----------------------------------------------------
    
    # Εξασφάλιση ότι το DIFF_BG_FMT έχει τιμή ακόμα κι αν δεν ενημερώθηκε το ιστορικό (πρώτο τρέξιμο)
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

    # 4. Εμφάνιση των Γραμμών Τρέχουσας Κατάστασης (Κεντραρισμένα Κατακόρυφα)

    # Ορισμός των γραμμών προς εκτύπωση
    HEADER_LINE="${BOLD}--- ΤΡΕΧΟΥΣΑ ΚΑΤΑΣΤΑΣΗ ---${NORMAL}"
    BG_LINE="ΕΠΙΠΕΔΟ BG: ${BG_COLOR}${BOLD}${DISPLAY_BG}${NORMAL}" # Χρησιμοποιούμε DISPLAY_BG
    DIFF_LINE="ΑΛΛΑΓΗ: ${DIFF_BG_FMT}"
    TREND_LINE="ΤΑΣΗ: ${ARROW} (${CURRENT_DIR})"
    AGE_LINE="ΗΛΙΚΙΑ ΔΕΔΟΜΕΝΩΝ: ${TIME_AGO_FMT} πριν"

    # Χρησιμοποιούμε ένα σταθερό πλάτος 40 για ασφαλή κεντράρισμα
    MAX_TEXT_WIDTH=40

    # Εκτύπωση των γραμμών διαδοχικά με αύξηση των αριθμών γραμμών
    START_ROW=4 # Εκκίνηση κάτω από την κεφαλίδα

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


    # 5. Εμφάνιση Ιστορικού Καταγραφής (Κάτω, αριστερά στοιχισμένο)
    # Εκκίνηση εκτύπωσης του διαχωριστικού ιστορικού 6 γραμμές κάτω από την κεφαλίδα
    HISTORY_START_ROW=$((START_ROW + 6))

    tput cup $HISTORY_START_ROW 0
    printf "${BLUE}%.0s" $(seq 1 $COLS) # Εκτύπωση μπλε διαχωριστικής γραμμής

    tput cup $((HISTORY_START_ROW + 1)) 0
    echo "${BOLD}Ιστορικό Καταγραφής (Τελευταίες 10 Αναγνώσεις):${NORMAL}"

    tput cup $((HISTORY_START_ROW + 2)) 0
    echo -e "$HISTORY_LOG" # Χρήση echo -e για σωστή απόδοση των αλλαγών γραμμής

    # 6. Αναμονή για το επόμενο διάστημα ελέγχου
    sleep $SLEEP_INTERVAL

done

