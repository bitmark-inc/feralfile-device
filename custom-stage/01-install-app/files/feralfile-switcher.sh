#!/bin/bash

# Environment setup
export DISPLAY=:0
export XAUTHORITY=/home/feralfile/.Xauthority

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

# Function to check internet connectivity
check_internet() {
    wget -q --spider https://www.google.com
    return $?
}

# Main loop to switch applications based on internet connectivity
while true; do
    if check_internet; then
        focus_chromium
    else
        focus_feralfile
    fi
    sleep 5
done