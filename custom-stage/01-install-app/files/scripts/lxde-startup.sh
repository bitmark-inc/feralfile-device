#!/bin/bash

# Append "quiet" to /boot/firmware/cmdline.txt if it's not already there
if ! grep -q "quiet" "/boot/firmware/cmdline.txt"; then
    sudo sed -i 's/$/ quiet/' "/boot/firmware/cmdline.txt"
fi

# Disable screen saver, screen blanking, and power management
xset s off
xset s noblank
xset -dpms

# Try different GPIO numbers for power button
for gpio in 3 512 529 535 567 572; do
    echo $gpio > /sys/class/gpio/export 2>/dev/null || true
    echo "in" > /sys/class/gpio/gpio$gpio/direction 2>/dev/null || true
    echo "both" > /sys/class/gpio/gpio$gpio/edge 2>/dev/null || true
done

# Setup LED GPIO
echo 18 > /sys/class/gpio/export
echo "out" > /sys/class/gpio/gpio18/direction

# Install reset and power scripts
sudo cp /opt/feralfile/scripts/soft-reset.sh /usr/local/bin/
sudo cp /opt/feralfile/scripts/factory-reset.sh /usr/local/bin/
sudo cp /opt/feralfile/scripts/power-off.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/soft-reset.sh
sudo chmod +x /usr/local/bin/factory-reset.sh
sudo chmod +x /usr/local/bin/power-off.sh

# Install power button monitor script
sudo cp /opt/feralfile/scripts/power-button-monitor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/power-button-monitor.sh

# Install power button monitor service
sudo cp /opt/feralfile/services/feralfile-power-button.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable and start necessary systemd services if not already enabled
for service in feralfile-launcher feralfile-chromium feralfile-watchdog feralfile-power-button; do
    if ! sudo systemctl is-enabled "$service.service" >/dev/null 2>&1; then
        sudo systemctl enable "$service.service"
        sudo systemctl start "$service.service"
    fi
done

for timer in feralfile-updater@08:00 feralfile-updater@16:00 feralfile-updater@00:00; do
    if ! sudo systemctl is-enabled "$timer.timer" >/dev/null 2>&1; then
        sudo systemctl enable "$timer.timer"
        sudo systemctl start "$timer.timer"
    fi
done
