#!/usr/bin/env bash

# Nightscout Terminal Dashboard launcher with language selection
# This script does not modify existing files. It only asks for language
# and then runs the existing dashboard script.

set -euo pipefail

# Default language
DEFAULT_LANG="en"

# Function to print prompt to stderr and read language
choose_language() {
    # Send all informational prompts to standard error (>&2)
    echo "Select language / Επιλέξτε γλώσσα:" >&2
    echo "  [en] English" >&2
    echo "  [gr] Ελληνικά" >&2
    read -r -p "Enter choice (en/gr) [${DEFAULT_LANG}]: " choice
    choice=${choice:-$DEFAULT_LANG}
    # Normalize: strip CR, trim spaces, lowercase
    choice=$(printf '%s' "$choice" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
    case "$choice" in
        en|gr)
            # ONLY the final choice is printed to standard output (stdout)
            echo "$choice"
            ;;
        *)
            echo "Invalid choice. Defaulting to ${DEFAULT_LANG}." >&2
            echo "$DEFAULT_LANG"
            ;;
    esac
}

LANG_CODE=$(choose_language)
export LANG_CODE

# If callers prefer a different env var name, we also export a generic LANG-like var
if [ -z "${NS_LANG:-}" ]; then
    export NS_LANG="$LANG_CODE"
fi

# Determine which underlying script to call and set standard locale variables
if [ "$LANG_CODE" = "gr" ]; then
    TARGET_SCRIPT="./gr_nightscout.sh"
    # Set standard Greek locale for underlying programs
    export LANG="el_GR.UTF-8"
    export LC_ALL="el_GR.UTF-8"
else
    TARGET_SCRIPT="./en_nightscout.sh"
    # Set standard English locale
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"
fi

# Ensure the target script exists
if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "Error: Could not find $TARGET_SCRIPT." >&2
    echo "Please ensure the language-specific script exists in this directory." >&2
    exit 1
fi

# Ensure it's executable
if [ ! -x "$TARGET_SCRIPT" ]; then
    chmod +x "$TARGET_SCRIPT" || true
fi

# Inform the user which language was selected
if [ "$LANG_CODE" = "gr" ]; then
    echo "Επιλέχθηκε γλώσσα: Ελληνικά"
else
    echo "Language selected: English"
fi
sleep 3

echo "Launching: $TARGET_SCRIPT"
sleep 1

exec "$TARGET_SCRIPT" "$@"
