#!/bin/bash

function get_config_value() {
  local key="$1"
  grep "^$key" "/home/feralfile/feralfile/feralfile-launcher.conf" | awk -F' = ' '{print $2}' | tr -d ' '
}

BASIC_AUTH_USER="$(get_config_value "distribution_auth_user")"
BASIC_AUTH_PASS="$(get_config_value "distribution_auth_password")"
SENTRY_DSN="$(get_config_value "sentry_dsn")"
LOCAL_BRANCH="$(get_config_value "app_branch")"

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
chmod 644 /etc/apt/trusted.gpg.d/feralfile.asc
chmod 755 /home/feralfile/feralfile/feralfile-chromium.sh
chmod 755 /home/feralfile/feralfile/feralfile-switcher.sh
chmod 755 /home/feralfile/feralfile/feralfile-watchdog.py
chmod 755 /home/feralfile/feralfile/feralfile-install-deps.sh

# Create autostart
mkdir -p /home/feralfile/.config/openbox
cat > /home/feralfile/.config/openbox/autostart <<EOF
if ! grep -q "quiet" "/boot/firmware/cmdline.txt"; then
    sudo sed -i 's/$/ quiet/' "/boot/firmware/cmdline.txt"
fi

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
if ! sudo systemctl is-enabled feralfile-watchdog.service >/dev/null 2>&1; then
    sudo systemctl enable feralfile-watchdog.service
    sudo systemctl start feralfile-watchdog.service
fi
if ! sudo systemctl is-enabled feralfile-install-deps.service >/dev/null 2>&1; then
    sudo systemctl enable feralfile-install-deps.service
    sudo systemctl start feralfile-install-deps.service
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

cat > /etc/systemd/system/feralfile-watchdog.service << EOF
Description=WebSocket Watchdog Service
After=feralfile-launcher.service
Wants=feralfile-launcher.service

[Service]
ExecStart=python3 /home/feralfile/feralfile/feralfile-watchdog.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

cat > /etc/systemd/system/feralfile-install-deps.service << EOF
[Unit]
Description=Install feralfile-launcher dependencies before daily upgrade
Before=apt-daily-upgrade.service

[Service]
Type=oneshot
ExecStart=/home/feralfile/feralfile/feralfile-install-deps.sh

[Install]
WantedBy=apt-daily-upgrade.service
EOF

mkdir -p /etc/systemd/system/apt-daily-upgrade.service.d
cat > /etc/systemd/system/apt-daily-upgrade.service.d/override.conf << EOF
[Unit]
# Require our dependency installation service before upgrading.
Requires=feralfile-install-deps.service
After=feralfile-install-deps.service
EOF

# Set settings
mkdir -p "/etc/apt/auth.conf.d/"
cat > /etc/apt/auth.conf.d/feralfile.conf << EOF
machine feralfile-device-distribution.bitmark-development.workers.dev
login $BASIC_AUTH_USER
password $BASIC_AUTH_PASS
EOF

sed -i "s|REPLACE_SENTRY_DSN|$SENTRY_DSN|g" "/home/feralfile/feralfile/feralfile-watchdog.py"

## Remove the config file since it's not used anymore
rm "/home/feralfile/feralfile/feralfile-launcher.conf"

mkdir -p "/etc/apt/sources.list.d/"
cat > /etc/apt/sources.list.d/feralfile.list << EOF
deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/feralfile.asc] https://feralfile-device-distribution.bitmark-development.workers.dev/ $LOCAL_BRANCH main 
EOF

apt-get update
apt-get install feralfile-launcher

# Create a custom configuration for unattended-upgrades
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Origins-Pattern {
    "origin=Raspbian,codename=bookworm,label=Raspbian";
    "origin=Raspberry Pi Foundation,codename=bookworm,label=Raspberry Pi Foundation";
    "origin=feralfile-launcher";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "1";
EOF
cat > /etc/apt/apt.conf.d/99auto-restart << EOF
DPkg::Post-Invoke { "systemctl restart feralfile-watchdog.service || true"; };
DPkg::Post-Invoke { "systemctl restart feralfile-launcher.service || true"; };
DPkg::Post-Invoke { "systemctl restart feralfile-chromium.service || true"; };
EOF