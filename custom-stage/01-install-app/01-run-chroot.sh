#!/bin/bash

# Update BlueZ version
apt-get install libglib2.0-dev libdbus-1-dev libudev-dev libical-dev libreadline-dev python3-docutils -y
cd /home/feralfile
wget http://www.kernel.org/pub/linux/bluetooth/bluez-5.79.tar.xz 
tar xvf bluez-5.79.tar.xz
cd bluez-5.79/
./configure --prefix=/usr --mandir=/usr/share/man --sysconfdir=/etc --localstatedir=/var --with-systemdsystemunitdir=/lib/systemd/system --with-systemduserunitdir=/usr/lib/system --enable-experimental
make -j4
make install
apt-get remove libglib2.0-dev libdbus-1-dev libudev-dev libical-dev libreadline-dev python3-docutils -y
rm /home/feralfile/bluez-5.79.tar.xz
rm -rf /home/feralfile/bluez-5.79
cd /

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

# Start unclutter to hide cursor after 5 seconds of inactivity
unclutter -idle 5 -root &

if ! sudo systemctl is-enabled feralfile-launcher.service >/dev/null 2>&1; then
    sudo systemctl enable feralfile-launcher.service
    sudo systemctl start feralfile-launcher.service
fi
if ! sudo systemctl is-enabled feralfile-chromium.service >/dev/null 2>&1; then
    sudo systemctl enable feralfile-chromium.service
    sudo systemctl start feralfile-chromium.service
fi
if ! sudo systemctl is-enabled feralfile-switcher.service >/dev/null 2>&1; then
    sudo systemctl enable feralfile-switcher.service
    sudo systemctl start feralfile-switcher.service
fi
EOF

chown -R feralfile:feralfile /home/feralfile/.config

# Configure auto-login for feralfile user
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf <<EOF
[Seat:*]
autologin-user=feralfile
autologin-user-timeout=0
EOF

# Don't use polkit to manage NetworkManager which will cause bugs
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/feralfile.conf <<EOF
[main]
auth-polkit=false
EOF

# Enable Just Work bluetooth connection
mkdir -p /etc/bluetooth
cat > /etc/bluetooth/main.conf <<EOF
[General]
JustWorksRepairing = always
EOF

mkdir -p /etc/systemd/system

# Create feralfile service 
cat > /etc/systemd/system/feralfile-launcher.service << EOF
[Unit]
Description=FeralFile Launcher Application
After=bluetooth.target
Requires=bluetooth.service

[Service]
User=feralfile
Group=feralfile
ExecStartPre=/bin/sleep 1
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