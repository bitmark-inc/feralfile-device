#!/bin/bash
# File: /home/feralfile/scripts/rotate-display

# Usage: rotate-display [0-3]
# 0 = normal (0°), 1 = right (90°), 2 = inverted (180°), 3 = left (270°)

set -e

ROTATE_VALUE="$1"

# Validate input
if [[ ! "$ROTATE_VALUE" =~ ^[0-3]$ ]]; then
  echo "Error: Invalid rotation value. Use 0 (normal), 1 (right), 2 (inverted), or 3 (left)."
  exit 1
fi

# Determine appropriate xrandr rotation parameter
case "$ROTATE_VALUE" in
  0) XRANDR_ROTATE="normal" ;;
  1) XRANDR_ROTATE="right" ;;
  2) XRANDR_ROTATE="inverted" ;;
  3) XRANDR_ROTATE="left" ;;
esac

# Detect primary display
PRIMARY_DISPLAY=$(xrandr --query | grep " connected primary" | cut -d " " -f1)
if [ -z "$PRIMARY_DISPLAY" ]; then
  # Fallback to first connected display if primary not found
  PRIMARY_DISPLAY=$(xrandr --query | grep " connected" | head -1 | cut -d " " -f1)
fi

# Apply rotation via xrandr for immediate effect
if [ -n "$PRIMARY_DISPLAY" ]; then
  xrandr --output "$PRIMARY_DISPLAY" --rotate "$XRANDR_ROTATE" || true
else
  xrandr -o "$XRANDR_ROTATE" || true
fi

# Update config.txt for persistent rotation across reboots
if [ -f /boot/config.txt ]; then
  # Backup config
  cp /boot/config.txt /boot/config.txt.bak
  
  # Remove existing display_rotate settings
  grep -v "display_rotate" /boot/config.txt > /tmp/config.txt.new
  
  # Add new display_rotate setting
  echo "display_rotate=$ROTATE_VALUE" >> /tmp/config.txt.new
  
  # Apply new config
  mv /tmp/config.txt.new /boot/config.txt
fi

# Apply performance optimizations based on rotation
if [ "$ROTATE_VALUE" != "0" ]; then
  # Increase GPU memory for rotated display
  if command -v raspi-config > /dev/null; then
    raspi-config nonint do_memory_split 128 || true
  fi
  
  # Optimize X11 settings
  xset s off || true
  xset -dpms || true
  
  # Kill compositors if running
  pkill -f "compton|picom" || true
else
  # For normal orientation, restore default memory split (optional)
  if command -v raspi-config > /dev/null; then
    raspi-config nonint do_memory_split 64 || true
  fi
fi

# Update orientation file for applications to know current state
echo "$ROTATE_VALUE" > /var/lib/display-orientation

echo "Display rotated to $XRANDR_ROTATE mode"
exit 0