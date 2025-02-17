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
        --use-angle=gles \
        --enable-gpu-rasterization \
        --force-renderer-accessibility \
        --media-router=0 \
        --enable-logging \
        --v=1 \
        --remote-debugging-port=9222 \
        --log-file=/var/log/chromium/chrome_debug.log \
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