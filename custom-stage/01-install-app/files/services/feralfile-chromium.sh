#!/bin/bash

# Paths to applications
CHROMIUM="chromium"

# Environment setup
export DISPLAY=:0
export XAUTHORITY=/home/feralfile/.Xauthority

# Function to start Chromium in kiosk mode
start_chromium() {
    # Create log directory if it doesn't exist and set permissions
    echo "Setting up log directory..."
    sudo mkdir -p /var/log/chromium
    sudo chown feralfile:feralfile /var/log/chromium
    sudo chmod 755 /var/log/chromium

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
        --show-fps-counter \
        --show-gpu-internals \
        --media-router=0 \
        --enable-logging \
        --log-level=0 \
        --log-time \
        --log-file="/var/log/chromium/chrome_debug.log" \
        --v=0 \
        --vmodule=console=0,*=-1 \
        --remote-debugging-port=9222 \
        https://support-feralfile-device.feralfile-display-prod.pages.dev/daily?platform=ff-device \
        2>&1 | tee -a /var/log/chromium/chrome_debug.log
}

# Function to check internet connectivity
check_internet() {
    wget -q --spider https://www.google.com
    return $?
}

if check_internet; then
    start_chromium
fi