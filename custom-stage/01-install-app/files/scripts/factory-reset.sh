#!/bin/bash

# Remove all user data
sudo rm -rf /home/feralfile/.config/feralfile/*
sudo rm -rf /home/feralfile/.cache/feralfile/*

# Reset system settings
sudo rm -f /etc/wpa_supplicant/wpa_supplicant.conf
sudo rm -f /home/feralfile/.config/feralfile/display_settings.json

# Log the reset
logger "Feral File: Factory reset performed"

# Reboot the device
sudo reboot 