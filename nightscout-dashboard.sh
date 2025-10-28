#!/usr/bin/env bash

# Nightscout Terminal Dashboard launcher with language selection
# This script does not modify existing files. It only asks for language
# and then runs the existing dashboard script.

set -euo pipefail

# Default language
DEFAULT_LANG="en"

# Function to print prompt and read language
choose_language() {
  echo "Select language / Επιλέξτε γλώσσα:"
  echo "  [en] English"
  echo "  [gr] Ελληνικά"
  read -r -p "Enter choice (en/gr) [${DEFAULT_LANG}]: " choice
  choice=${choice:-$DEFAULT_LANG}
  # Normalize to lowercase
  choice=$(printf "%s" "$choice" | tr '[:upper:]' '[:lower:]')
  case "$choice" in
    en|gr)
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
# but do not override system LANG if already set.
if [ -z "${NS_LANG:-}" ]; then
  export NS_LANG="$LANG_CODE"
fi

# Determine which underlying script to call. Prefer nightscout.sh if present.
SCRIPT_CANDIDATES=(
  "./nightscout.sh"
  "./Nightscout.sh"
)

TARGET_SCRIPT=""
for s in "${SCRIPT_CANDIDATES[@]}"; do
  if [ -f "$s" ] && [ -x "$s" ]; then
    TARGET_SCRIPT="$s"
    break
  elif [ -f "$s" ]; then
    # Make it executable for this run
    chmod +x "$s" || true
    TARGET_SCRIPT="$s"
    break
  fi
done

if [ -z "$TARGET_SCRIPT" ]; then
  # Fallback: if there is a README instruction referencing a different script name,
  # we try the commonly referenced one in the README: nightscout-dashboard.sh
  # But to avoid recursion, ensure we don't call ourselves.
  if [ -f "./nightscout.sh" ]; then
    chmod +x ./nightscout.sh || true
    TARGET_SCRIPT="./nightscout.sh"
  fi
fi

if [ -z "$TARGET_SCRIPT" ]; then
  echo "Error: Could not find the main Nightscout script (expected ./nightscout.sh)." >&2
  echo "Please ensure the main script exists in this directory." >&2
  exit 1
fi

# Inform the user which language was selected
if [ "$LANG_CODE" = "gr" ]; then
  echo "Επιλέχθηκε γλώσσα: Ελληνικά"
else
  echo "Language selected: English"
fi

# Delegate to the main script. Pass through all arguments.
exec "$TARGET_SCRIPT" "$@"

# End of file
