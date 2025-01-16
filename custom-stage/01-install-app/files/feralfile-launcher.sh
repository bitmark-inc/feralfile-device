#!/bin/bash

# Paths to applications
CHROMIUM="/usr/bin/chromium"
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
            --remote-debugging-port=9222 \
            --no-first-run \
            --disable-translate \
            --disable-infobars \
            --disable-session-crashed-bubble \
            --disable-features=TranslateUI \
            https://display.feralfile.com >/dev/null 2>&1 &
    fi
}

# Function to start the FeralFile application
start_feralfile() {
    # Start the FeralFile application if not already running
    if ! pgrep -f "$FERALFILE" > /dev/null; then
        echo "Starting FeralFile application..."
        "$FERALFILE" &
    fi
}

# Function to check internet connectivity
check_internet() {
    wget -q --spider https://www.google.com
    return $?
}

# Main loop to switch applications based on internet connectivity
CURRENT_MODE=""
while true; do
    if check_internet; then
        if [ "$CURRENT_MODE" != "online" ]; then
            start_chromium
            CURRENT_MODE="online"
        fi
    else
        if [ "$CURRENT_MODE" != "offline" ]; then
            start_feralfile
            CURRENT_MODE="offline"
        fi
    fi
    sleep 5
done