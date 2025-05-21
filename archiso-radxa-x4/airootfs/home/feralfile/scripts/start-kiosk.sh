#!/bin/bash

# Read saved rotation
ROTATION="normal"
if [ -f /home/feralfile/.config/screen-orientation ]; then
    ROTATION=$(cat /home/feralfile/.config/screen-orientation)
fi

# Convert rotation to transform value
TRANSFORM="0"
if [ "$ROTATION" = "90" ]; then
    TRANSFORM="1"
elif [ "$ROTATION" = "180" ]; then
    TRANSFORM="2"
elif [ "$ROTATION" = "270" ]; then
    TRANSFORM="3"
fi

# Set Wayland/wlroots environment variables
export WLR_OUTPUT_HDMI-A-1_TRANSFORM="$TRANSFORM"
export WLR_NO_DIRECT_SCANOUT=1
export WLR_DRM_NO_MODIFIERS=0
export WLR_DRM_FORMATS="XR24/I915_FORMAT_MOD_Y_TILED;XR24/I915_FORMAT_MOD_Yf_TILED"

# Start cage with Chromium directly
exec cage -- /usr/bin/chromium \
    --kiosk \
    --ozone-platform=wayland \
    --enable-features=UseOzonePlatform \
    --remote-debugging-port=9222 \
    --show-fps-counter \
    --no-first-run \
    --disable-sync \
    --disable-translate \
    --disable-infobars \
    --disable-features=TranslateUI \
    --noerrdialogs \
    --disable-extensions \
    --autoplay-policy=no-user-gesture-required \
    --allow-file-access-from-files \
    --enable-logging=stderr \
    --v=1 \
    --disk-cache-size=1073741824 \
    file:///opt/feral/ui/launcher/index.html?step=logo