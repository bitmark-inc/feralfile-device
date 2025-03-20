#!/bin/bash

# Append "quiet" to /boot/firmware/cmdline.txt if it's not already there
if ! grep -q "quiet" "/boot/firmware/cmdline.txt"; then
    sudo sed -i 's/$/ quiet/' "/boot/firmware/cmdline.txt"
fi

# Disable screen saver, screen blanking, and power management
xset s off
xset s noblank
xset -dpms

# Start unclutter to hide the cursor after 5 seconds of inactivity
unclutter -idle 5 -root &

# Enable and start necessary systemd services if not already enabled
for service in feralfile-launcher feralfile-chromium feralfile-watchdog feralfile-install-deps; do
    if ! sudo systemctl is-enabled "$service.service" >/dev/null 2>&1; then
        sudo systemctl enable "$service.service"
        sudo systemctl start "$service.service"
    fi
done