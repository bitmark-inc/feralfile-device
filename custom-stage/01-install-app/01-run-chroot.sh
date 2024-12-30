#!/bin/bash

dpkg -i feralfile-launcher_arm64.deb

# Create autostart directory and desktop entry
mkdir -p /home/feralfile/.config/autostart
cat > /home/feralfile/.config/autostart/feralfile-launcher.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Feral File Launcher
Exec=/opt/feralfile/feralfile
X-GNOME-Autostart-enabled=true
DESKTOP

# Set correct ownership
chown -R feralfile:feralfile /home/feralfile/.config

# Configure auto-login for feralfile user
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf <<EOF
[Seat:*]
autologin-user=feralfile
autologin-user-timeout=0
EOF

# Create btautopair file to enable Bluetooth HID auto-pairing
touch /boot/firmware/btautopair