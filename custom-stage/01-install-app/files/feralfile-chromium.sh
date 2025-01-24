#!/bin/bash

# Paths to applications
CHROMIUM="chromium"

# Environment setup
export DISPLAY=:0
export XAUTHORITY=/home/feralfile/.Xauthority

# Function to start Chromium in kiosk mode
start_chromium() {
    echo "Starting Chromium..."
    "$CHROMIUM" \
        --kiosk \
        --disable-extensions \
        --no-first-run \
        --autoplay-policy=no-user-gesture-required \
        --disable-translate \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-features=TranslateUI \
        https://support-feralfile-device.feralfile-display-prod.pages.dev?platform=ff-device >/dev/null 2>&1
}

# Function to check internet connectivity
check_internet() {
    wget -q --spider https://www.google.com
    return $?
}

if check_internet; then
    start_chromium
fi