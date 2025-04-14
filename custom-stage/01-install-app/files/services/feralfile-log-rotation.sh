#!/bin/bash
set -e

# Config
MAX_DAYS=7
TODAY=$(date +"%Y-%m-%d")

# 1. feralfile-watchdog.log
WATCHDOG_LOG="/var/log/feralfile-watchdog.log"
ROTATED_WATCHDOG_LOG="/var/log/feralfile-watchdog_$TODAY.log"

if [ -f "$WATCHDOG_LOG" ] && [ ! -f "$ROTATED_WATCHDOG_LOG" ]; then
    cp "$WATCHDOG_LOG" "$ROTATED_WATCHDOG_LOG"
    echo "" > "$WATCHDOG_LOG"
fi

# 2. chrome_debug.log
CHROME_LOG="/var/log/chromium/chrome_debug.log"
ROTATED_CHROME_LOG="/var/log/chromium/chrome_debug_$TODAY.log"

if [ -f "$CHROME_LOG" ] && [ ! -f "$ROTATED_CHROME_LOG" ]; then
    cp "$CHROME_LOG" "$ROTATED_CHROME_LOG"
    echo "" > "$CHROME_LOG"
fi

# 3. Rotate app.log
APP_LOG="/home/feralfile/Documents/app.log"
ROTATED_APP_LOG="/home/feralfile/Documents/app_$TODAY.log"

if [ -f "$APP_LOG" ] && [ ! -f "$ROTATED_APP_LOG" ]; then
    cp "$APP_LOG" "$ROTATED_APP_LOG"
    echo "" > "$APP_LOG"
fi

# 4. Rotate system.log
SYSTEM_LOG="/home/feralfile/Documents/system.log"
ROTATED_SYSTEM_LOG="/home/feralfile/Documents/system_$TODAY.log"

if [ -f "$SYSTEM_LOG" ] && [ ! -f "$ROTATED_SYSTEM_LOG" ]; then
    cp "$SYSTEM_LOG" "$ROTATED_SYSTEM_LOG"
    echo "" > "$SYSTEM_LOG"
fi

# 5. Cleanup old logs
find /var/log -name "feralfile-watchdog_*.log" -mtime +$MAX_DAYS -delete
find /var/log/chromium -name "chrome_debug_*.log" -mtime +$MAX_DAYS -delete
find /home/feralfile/Documents -type f -name "app_*.log" -mtime +$MAX_DAYS -delete
find /home/feralfile/Documents -type f -name "system_*.log" -mtime +$MAX_DAYS -delete
