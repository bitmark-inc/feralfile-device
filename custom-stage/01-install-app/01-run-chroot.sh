#!/bin/bash

chown -R feralfile:feralfile /home/feralfile/feralfile/

dpkg -i /home/feralfile/feralfile/feralfile-launcher_arm64.deb

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

# Add OTA cronjob update script
chmod 755 /home/feralfile/feralfile/feralfile-ota-update.sh
CRON_CMD="0 3 * * * DISPLAY=:0 XAUTHORITY=/home/feralfile/.Xauthority sudo /home/feralfile/feralfile/feralfile-ota-update.sh"
crontab -u feralfile -l 2>/dev/null || true > /tmp/feralfile_cron
grep -F "$CRON_CMD" /tmp/feralfile_cron >/dev/null 2>&1 || echo "$CRON_CMD" >> /tmp/feralfile_cron
crontab -u feralfile /tmp/feralfile_cron
rm /tmp/feralfile_cron
