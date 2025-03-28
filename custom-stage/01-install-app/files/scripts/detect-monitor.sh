#!/bin/bash
# File: /home/feralfile/scripts/detect-monitor.sh
# Purpose: Detect monitor info and update /boot/cmdline.txt at LXDE startup, preserving rotation

set -e

# File paths
CMDLINE_FILE="/boot/firmware/cmdline.txt"
TEMP_FILE="/tmp/cmdline.txt.new"

# Detect connected display using xrandr
DISPLAY=$(DISPLAY=:0 XAUTHORITY="/home/feralfile/.Xauthority" xrandr --query | grep " connected" | cut -d " " -f1 | head -1)
if [ -z "$DISPLAY" ]; then
  echo "Error: No connected display found."
  exit 1
fi

# Get current resolution and frame rate
MODE_LINE=$(DISPLAY=:0 XAUTHORITY="/home/feralfile/.Xauthority" xrandr --query | grep " connected" -A 1 | grep "\*")
RESOLUTION=$(echo "$MODE_LINE" | awk '{print $1}')
FPS=$(echo "$MODE_LINE" | awk '{print $2}' | tr -d '*+')  # e.g., 59.95
FPS=$(printf "%.0f" "$FPS")  # Rounds 59.95 to 60

# Check existing video= parameter in cmdline.txt
EXISTING_VIDEO=$(grep -o "video=[^ ]*" "$CMDLINE_FILE" || echo "")
if echo "$EXISTING_VIDEO" | grep -q ",rotate=[0-9]*"; then
  # Preserve the rotate= option
  ROTATE_OPTION=$(echo "$EXISTING_VIDEO" | grep -o ",rotate=[0-9]*")
else
  ROTATE_OPTION=""
fi

# Construct new video parameter, e.g., video=HDMI-A-1:1920x1080@60,rotate=90
VIDEO_PARAM="video=${DISPLAY}:${RESOLUTION}@${FPS}${ROTATE_OPTION}"

# Update cmdline.txt: remove only the video= parameter and append new one
sed -E 's/(^| )video=[^ ]+//g' "$CMDLINE_FILE" > "$TEMP_FILE"
echo -n "$(cat $TEMP_FILE) $VIDEO_PARAM" > "$TEMP_FILE"
sudo sed 's/ \+/ /g; s/^ //; s/ $//' "$TEMP_FILE" | sudo tee "$CMDLINE_FILE" > /dev/null
#rm -f "$TEMP_FILE"

echo "HDMI event detected at $(date). Updated $CMDLINE_FILE with: $VIDEO_PARAM" >> /tmp/hdmi-log.txt
echo "HDMI event detected at $(date). Updated $CMDLINE_FILE with: $VIDEO_PARAM"