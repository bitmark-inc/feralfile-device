#!/bin/bash

# Paths to applications
CHROMIUM="chromium"
FERALFILE="/opt/feralfile/feralfile"

# Environment setup
export DISPLAY=:0
export XAUTHORITY=/home/feralfile/.Xauthority

# Function to start Chromium in kiosk mode
start_chromium() {
    # Start Chromium if not already running
    if ! pgrep -f "$CHROMIUM" > /dev/null; then
        echo "Starting Chromium..."
        "$CHROMIUM" \
            --kiosk \
            --disable-extensions \
            --no-first-run \
            --disable-translate \
            --disable-infobars \
            --disable-session-crashed-bubble \
            --disable-features=TranslateUI \
            https://support-feralfile-device.feralfile-display-prod.pages.dev >/dev/null 2>&1 &
        sleep 2
    fi
}

# Function to start the FeralFile application
start_feralfile() {
    # Start the FeralFile application if not already running
    if ! pgrep -f "$FERALFILE" > /dev/null; then
        echo "Starting FeralFile application..."
        "$FERALFILE" &
        sleep 2
    fi
}

# Function to check internet connectivity
check_internet() {
    wget -q --spider https://www.google.com
    return $?
}

# Function to focus Chromium
focus_chromium() {
    WIN_ID=$(xdotool search --onlyvisible --class "chromium" | head -n 1)
    if [ -n "$WIN_ID" ]; then
        echo "Focusing Chromium..."
        xdotool windowactivate --sync "$WIN_ID"
    fi
}

# Function to focus FeralFile
focus_feralfile() {
    WIN_ID=$(xdotool search --onlyvisible --class "feralfile" | head -n 1)
    if [ -n "$WIN_ID" ]; then
        echo "Focusing FeralFile..."
        xdotool windowactivate --sync "$WIN_ID"
    fi
}

# Main loop to switch applications based on internet connectivity
while true; do
    # Ensure the FeralFile application is running
    start_feralfile
    if check_internet; then
        start_chromium
        focus_chromium
    else
        focus_feralfile
    fi
    sleep 5
done