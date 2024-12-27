#!/bin/bash
export DISPLAY=:0

LOGFILE="/var/log/display_adjust.log"

# Log the script execution
echo "$(date): Starting dynamic_resize.sh" >> $LOGFILE

# Get the connected display name (e.g., HDMI-A-1)
DISPLAY_NAME=$(xrandr | grep " connected" | awk '{print $1}')
if [[ -z "$DISPLAY_NAME" ]]; then
    echo "$(date): No display detected. Exiting." >> $LOGFILE
    exit 1
fi

# Detect the current resolution
RESOLUTION=$(xrandr | grep "$DISPLAY_NAME connected" | awk '{print $4}' | cut -d'+' -f1)
if [[ -z "$RESOLUTION" ]]; then
    echo "$(date): No resolution detected for $DISPLAY_NAME. Using fallback resolution 1920x1080." >> $LOGFILE
    xrandr --output $DISPLAY_NAME --mode 1920x1080
    RESOLUTION="1920x1080"
fi

# Split resolution into width and height
WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)
HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)

echo "$(date): Detected resolution: ${WIDTH}x${HEIGHT}" >> $LOGFILE

# Determine orientation
if [[ $WIDTH -lt $HEIGHT ]]; then
    # Portrait mode
    echo "$(date): Switching to Portrait Mode" >> $LOGFILE
    xrandr --output $DISPLAY_NAME --rotate right
else
    # Landscape mode
    echo "$(date): Switching to Landscape Mode" >> $LOGFILE
    xrandr --output $DISPLAY_NAME --rotate normal
fi

# Resize Chromium to fit the screen
echo "$(date): Resizing Chromium to fullscreen" >> $LOGFILE
wmctrl -r chromium-browser -b add,maximized_vert,maximized_horz

echo "$(date): dynamic_resize.sh completed successfully" >> $LOGFILE