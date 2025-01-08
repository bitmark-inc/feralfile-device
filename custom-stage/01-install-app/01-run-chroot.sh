#!/bin/bash

dpkg -i feralfile-launcher_arm64.deb

# Create autostart
mkdir -p /home/feralfile/.config/openbox
cat > /home/feralfile/.config/openbox/autostart <<EOF
xset s off
xset s noblank
xset -dpms

/opt/feralfile/feralfile &
EOF

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