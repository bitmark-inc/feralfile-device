#!/bin/bash

chown -R feralfile:feralfile /home/feralfile/feralfile/
chmod 755 /home/feralfile/feralfile/feralfile-ota-update.sh
chmod 755 /home/feralfile/feralfile/feralfile-chromium.sh
chmod 755 /home/feralfile/feralfile/feralfile-switcher.sh

dpkg -i /home/feralfile/feralfile/feralfile-launcher_arm64.deb

# Create autostart
mkdir -p /home/feralfile/.config/openbox
cat > /home/feralfile/.config/openbox/autostart <<EOF
xset s off
xset s noblank
xset -dpms

if ! systemctl --user is-enabled feralfile-launcher.service >/dev/null 2>&1; then
    systemctl --user enable feralfile-launcher.service
    systemctl --user start feralfile-launcher.service
fi
if ! systemctl --user is-enabled feralfile-chromium.service >/dev/null 2>&1; then
    systemctl --user enable feralfile-chromium.service
    systemctl --user start feralfile-chromium.service
fi
if ! systemctl --user is-enabled feralfile-switcher.service >/dev/null 2>&1; then
    systemctl --user enable feralfile-switcher.service
    systemctl --user start feralfile-switcher.service
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

# Don't use polkit to manage NetworkManager which will cause bugs
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/feralfile.conf <<EOF
[main]
auth-polkit=false
EOF

# Create feralfile service 
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/feralfile-launcher.service << EOF
[Unit]
Description=FeralFile Launcher Application
After=bluetooth.target
Requires=bluetooth.service

[Service]
User=feralfile
Group=feralfile
ExecStart=/opt/feralfile/feralfile
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/feralfile/.Xauthority
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
EOF

cat > /etc/systemd/system/feralfile-chromium.service << EOF
[Unit]
Description=FeralFile Chromium
After=feralfile-launcher.service
Wants=feralfile-launcher.service

[Service]
User=feralfile
Group=feralfile
ExecStart=/home/feralfile/feralfile/feralfile-chromium.sh
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
EOF

cat > /etc/systemd/system/feralfile-switcher.service << EOF
[Unit]
Description=FeralFile Switcher

[Service]
User=feralfile
Group=feralfile
ExecStart=/home/feralfile/feralfile/feralfile-switcher.sh
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
EOF

chown -R feralfile:feralfile /home/feralfile/.config

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