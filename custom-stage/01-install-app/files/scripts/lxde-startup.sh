#!/bin/bash

# Append "quiet" to /boot/firmware/cmdline.txt if it's not already there
if ! grep -q "quiet" "/boot/firmware/cmdline.txt"; then
    sed -i 's/$/ quiet/' "/boot/firmware/cmdline.txt"
fi

# Disable screen saver, screen blanking, and power management
xset s off
xset s noblank
xset -dpms

# Enable and start necessary systemd services if not already enabled
for service in feralfile-launcher feralfile-chromium feralfile-watchdog; do
    if ! systemctl is-enabled "$service.service" >/dev/null 2>&1; then
        systemctl enable "$service.service"
        systemctl start "$service.service"
    fi
done

for timer in feralfile-updater@08:00 feralfile-updater@16:00 feralfile-updater@00:00; do
    if ! systemctl is-enabled "$timer.timer" >/dev/null 2>&1; then
        systemctl enable "$timer.timer"
        systemctl start "$timer.timer"
    fi
done

rm -rf /home/feralfile/.config/chromium/Default/Local\ Storage/leveldb