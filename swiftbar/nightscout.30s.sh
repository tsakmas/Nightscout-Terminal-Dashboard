#!/usr/bin/env bash
# <xbar.title>Nightscout</xbar.title>
# <xbar.desc>Blood glucose from Nightscout in the menu bar</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# SwiftBar plugin. Copy this file into your SwiftBar plugin folder.
# The "30s" in the file name means it refreshes every 30 seconds.
# Change NS_DIR below if you cloned the project somewhere else.

NS_DIR="$HOME/Nightscout-Terminal-Dashboard"

# SwiftBar starts with a short PATH, so add Homebrew's folders for jq.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
exec "$NS_DIR/nightscout.sh" --swiftbar
