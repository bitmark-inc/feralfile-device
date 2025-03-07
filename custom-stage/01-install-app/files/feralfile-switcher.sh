#!/bin/bash

# Environment setup
export DISPLAY=:0
export XAUTHORITY=/home/feralfile/.Xauthority

# Counter for failed connectivity checks and threshold value
fail_count=0
FAIL_THRESHOLD=3

# Function to focus FeralFile
focus_feralfile() {
    ACTIVE_WIN=$(xdotool getactivewindow)
    WIN_ID=$(xdotool search --onlyvisible --class "feralfile" | head -n 1)

    if [ -n "$WIN_ID" ]; then
        if [ "$WIN_ID" != "$ACTIVE_WIN" ]; then
            xdotool windowactivate --sync "$WIN_ID"
        fi
    else
        echo "FeralFile window not found."
    fi
}

# Function to focus Chromium
focus_chromium() {
    ACTIVE_WIN=$(xdotool getactivewindow)
    WIN_ID=$(xdotool search --onlyvisible --class "chromium" | head -n 1)

    if [ -n "$WIN_ID" ]; then
        if [ "$WIN_ID" != "$ACTIVE_WIN" ]; then
            xdotool windowactivate --sync "$WIN_ID"
        fi
    else
        echo "Chromium window not found."
    fi
}

# Function to check internet connectivity by trying multiple websites
check_internet() {
    ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 && return 0
    ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 && return 0
    ping -c 1 -W 1 9.9.9.9 >/dev/null 2>&1 && return 0
    return 1
}

# Main loop to switch applications based on internet connectivity
while true; do
    if check_internet; then
        fail_count=0
        focus_chromium
    else
        ((fail_count++))
        echo "Connectivity check failed ($fail_count/$FAIL_THRESHOLD)"
        if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
            focus_feralfile
        fi
    fi
    sleep 5
done