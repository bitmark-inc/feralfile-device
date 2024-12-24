#!/bin/bash
set -e

echo "Starting kiosk mode setup..."

# Install Chromium browser
echo "Installing Chromium..."
sudo apt update
sudo apt install -y chromium-browser

# Create autostart directory if it doesn't exist
AUTOSTART_DIR="/home/pi/.config/autostart"
if [[ ! -d "$AUTOSTART_DIR" ]]; then
    echo "Creating autostart directory..."
    mkdir -p "$AUTOSTART_DIR"
fi

# Copy kiosk autostart configuration
echo "Configuring Chromium to launch in kiosk mode..."
cp configs/kiosk.desktop "$AUTOSTART_DIR/"

# Ensure proper permissions
echo "Setting permissions..."
chmod +x "$AUTOSTART_DIR/kiosk.desktop"

# Disable screen blanking and power management
echo "Disabling screen blanking..."
AUTOSTART_GLOBAL="/etc/xdg/lxsession/LXDE-pi/autostart"
if ! grep -q "xset s off" "$AUTOSTART_GLOBAL"; then
    echo "@xset s off" >> "$AUTOSTART_GLOBAL"
    echo "@xset -dpms" >> "$AUTOSTART_GLOBAL"
    echo "@xset s noblank" >> "$AUTOSTART_GLOBAL"
fi

echo "Kiosk mode setup complete. Please reboot the system."