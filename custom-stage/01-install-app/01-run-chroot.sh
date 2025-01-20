#!/bin/bash

chown -R feralfile:feralfile /home/feralfile/feralfile/
chmod 755 /home/feralfile/feralfile/feralfile-ota-update.sh
chmod 755 /home/feralfile/feralfile/feralfile-launcher.sh

dpkg -i /home/feralfile/feralfile/feralfile-launcher_arm64.deb

# Create autostart
mkdir -p /home/feralfile/.config/openbox
cat > /home/feralfile/.config/openbox/autostart <<EOF
xset s off
xset s noblank
xset -dpms

if ! systemctl --user is-enabled feralfile.service >/dev/null 2>&1; then
    systemctl --user enable feralfile.service
    systemctl --user start feralfile.service
fi
EOF

# Configure auto-login for feralfile user
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf <<EOF
[Seat:*]
autologin-user=feralfile
autologin-user-timeout=0
EOF

# Create btautopair file to enable Bluetooth HID auto-pairing
touch /boot/firmware/btautopair

# Create feralfile service 
mkdir -p /home/feralfile/.config/systemd/user
cat > /home/feralfile/.config/systemd/user/feralfile.service << EOF
[Unit]
Description=FeralFile Application
After=bluetooth.service

[Service]
ExecStart=/home/feralfile/feralfile/feralfile-launcher.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

chown -R feralfile:feralfile /home/feralfile/.config

loginctl enable-linger feralfile

# Add OTA cronjob update script
CRON_CMD="*/30 * * * * DISPLAY=:0 XAUTHORITY=/home/feralfile/.Xauthority sudo /home/feralfile/feralfile/feralfile-ota-update.sh"
crontab -u feralfile -l 2>/dev/null || true > /tmp/feralfile_cron
grep -F "$CRON_CMD" /tmp/feralfile_cron >/dev/null 2>&1 || echo "$CRON_CMD" >> /tmp/feralfile_cron
crontab -u feralfile /tmp/feralfile_cron
rm /tmp/feralfile_cron

# Create a custom configuration for unattended-upgrades
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Origins-Pattern {
    "origin=Raspbian,codename=bookworm,label=Raspbian";
    "origin=Raspberry Pi Foundation,codename=bookworm,label=Raspberry Pi Foundation";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Allow-downgrade "true";
Unattended-Upgrade::Keep-Debs-After-Install "true";
EOF
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "1";
EOF