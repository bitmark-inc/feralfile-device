#!/bin/bash
# File: /home/feralfile/scripts/rotate-display.sh
# Usage: rotate-display.sh [0-3]
# 0 = normal (0°), 1 = right (90°), 2 = inverted (180°), 3 = left (270°)

set -e

ROTATE_VALUE="$1"

# Validate input
if [[ ! "$ROTATE_VALUE" =~ ^[0-3]$ ]]; then
  echo "Error: Invalid rotation value. Use 0 (normal), 1 (right), 2 (inverted), or 3 (left)."
  exit 1
fi

# Map rotation value
case "$ROTATE_VALUE" in
  0) ROTATE_PARAM="" ;;
  1) ROTATE_PARAM=",rotate=90" ;;
  2) ROTATE_PARAM=",rotate=180" ;;
  3) ROTATE_PARAM=",rotate=270" ;;
esac

# File paths
CMDLINE_FILE="/boot/cmdline.txt"
TEMP_FILE="/tmp/cmdline.txt.new"

# Check for existing video= parameter
if [ ! -f "$CMDLINE_FILE" ]; then
  echo "Error: $CMDLINE_FILE not found."
  exit 1
fi
EXISTING_VIDEO=$(grep -o "video=[^ ]*" "$CMDLINE_FILE" || echo "")
if [ -z "$EXISTING_VIDEO" ]; then
  echo "Error: No video= parameter found. Run detect-monitor.sh first."
  exit 1
fi

# Remove old rotate= option, add new one
BASE_VIDEO_PARAM=$(echo "$EXISTING_VIDEO" | sed 's/,rotate=[0-9]*//')
NEW_VIDEO_PARAM="${BASE_VIDEO_PARAM}${ROTATE_PARAM}"

# Update cmdline.txt
grep -v "video=" "$CMDLINE_FILE" > "$TEMP_FILE"
echo -n "$(cat $TEMP_FILE) $NEW_VIDEO_PARAM" > "$TEMP_FILE"
sed 's/ \+/ /g; s/^ //; s/ $//' "$TEMP_FILE" > "$CMDLINE_FILE"
rm -f "$TEMP_FILE"

echo "Updated $CMDLINE_FILE with: $NEW_VIDEO_PARAM"
echo "Rebooting..."
reboot