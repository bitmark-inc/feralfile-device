#!/bin/bash

# Reset Wi-Fi settings
sudo rm -f /etc/wpa_supplicant/wpa_supplicant.conf

# Reset display settings
sudo rm -f /home/feralfile/.config/feralfile/display_settings.json

# Restart services
sudo systemctl restart feralfile-launcher
sudo systemctl restart feralfile-chromium

# Log the reset
logger "Feral File: Soft reset performed"

# Reboot the device
sudo reboot 