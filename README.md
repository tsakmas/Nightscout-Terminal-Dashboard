🚀 Nightscout Terminal Dashboard

Backstory

Two years ago, my daughter was diagnosed with Type 1 Diabetes. From day one, I began searching for a way to monitor her blood glucose levels directly from my MacBook's terminal. I couldn't find a tool that truly fit my need for a quick, minimal, and constantly visible status, so I decided to create this project.

This dashboard is a lightweight, always-on utility designed to provide immediate peace of mind by showing the most critical Nightscout data right in the command line. Any suggestion for improvement is highly welcomed!

Short Description

The Nightscout Terminal Dashboard is a fast, command-line interface (CLI) tool designed for macOS and Linux users. It displays the current blood glucose (BG) value, trend, and recent history from your Nightscout site in real-time, right inside your Terminal. It's perfect for developers and anyone who frequently uses the command line and desires an immediate, minimal visual update without needing to open a web browser.

Features

    Real-Time Data: Configurable refresh interval (default is 30 seconds).

    Vertical Centering: Status information is centered vertically and horizontally for easy viewing.

    Color-Coded Status: BG values are color-coded based on target ranges (Red, Yellow, Green).

    Universal Compatibility: Uses a small C helper (get_millis) to ensure accurate millisecond-level time calculation on both macOS (BSD) and Linux (GNU) systems, preventing time-related script errors.

    Data Integrity Checks: Robust checks handle "null" and invalid data responses from the API to prevent terminal errors.

🛠️ Installation and Execution

A. Prerequisites

Ensure you have the following tools installed on your system:

    Git

    Curl

    jq (JSON processor)

    C Compiler (gcc or clang—usually available via XCode Command Line Tools on macOS).

(On macOS, you can install the dependencies easily via Homebrew: brew install jq)

B. Setup Steps
    Clone the Repository:
    Bash
    
    git clone https://github.com/tsakmas/Nightscout-Terminal-Dashboard.git
    cd nightscout-terminal-dashboard


Compile the C Helper (Crucial for time accuracy on macOS):
Bash

    gcc -o get_millis get_millis.c

Note: This must be done once after cloning.

Configure Parameters: Open the primary script file (nightscout.sh) using your preferred editor (e.g., nano nightscout.sh) and replace the placeholder values for your Nightscout URL and Read-Only Token:

NIGHTSCOUT_URL="https://your-nightscout-site.eu"

TOKEN="YOUR_READ_ONLY_TOKEN"

Execute the Dashboard:

    ./nightscout-dashboard.sh

Press Ctrl+C to terminate the program.


License
This project is licensed under the MIT License.
