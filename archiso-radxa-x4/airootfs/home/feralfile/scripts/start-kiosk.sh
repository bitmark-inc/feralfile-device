#!/bin/bash

# Read saved rotation
ROTATION="normal"
if [ -f /home/feralfile/.config/screen-orientation ]; then
    ROTATION=$(cat /home/feralfile/.config/screen-orientation)
fi

# Start cage with a small delay script
# This script will keep cage running while we apply rotation
cage -- /bin/bash -c '
    # Let Cage initialize
    sleep 1
    
    # Apply rotation using wlr-randr
    OUTPUT=$(wlr-randr | grep Output | head -1 | awk "{print \$2}")
    if [ -n "$OUTPUT" ]; then
        wlr-randr --output "$OUTPUT" --rotate '"$ROTATION"'
    fi
    
    # Start Chromium
    exec /usr/bin/chromium \
    --kiosk \
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
'
