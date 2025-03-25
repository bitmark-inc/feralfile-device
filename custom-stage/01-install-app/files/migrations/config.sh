#!/bin/bash

function get_config_value() {
  local key="$1"
  grep "^$key" "/home/feralfile/.config/feralfile/feralfile-launcher.conf" | awk -F' = ' '{print $2}' | tr -d ' '
}

BASIC_AUTH_USER="$(get_config_value "distribution_auth_user")"
BASIC_AUTH_PASS="$(get_config_value "distribution_auth_password")"
LOCAL_BRANCH="$(get_config_value "app_branch")"

# Create LXDE autostart
mkdir -p /home/feralfile/.config/lxsession/LXDE
rm /home/feralfile/.config/lxsession/LXDE/autostart
cat > /home/feralfile/.config/lxsession/LXDE/autostart <<EOF
@env vblank_mode=1
@unclutter -idle 1
@/home/feralfile/scripts/lxde-startup.sh
EOF

chown -R feralfile:feralfile /home/feralfile/.config

# Don't use polkit to manage NetworkManager which will cause bugs
mkdir -p /etc/NetworkManager/conf.d
rm /etc/NetworkManager/conf.d/feralfile.conf
cat > /etc/NetworkManager/conf.d/feralfile.conf <<EOF
[main]
auth-polkit=false
EOF

# Enable Just Work bluetooth connection
mkdir -p /etc/bluetooth
rm /etc/bluetooth/main.conf
cat > /etc/bluetooth/main.conf <<EOF
[General]
JustWorksRepairing = always
EOF

# Set APT settings
mkdir -p "/etc/apt/auth.conf.d/"
rm /etc/apt/auth.conf.d/feralfile.conf
cat > /etc/apt/auth.conf.d/feralfile.conf << EOF
machine feralfile-device-distribution.bitmark-development.workers.dev
login $BASIC_AUTH_USER
password $BASIC_AUTH_PASS
EOF

mkdir -p "/etc/apt/sources.list.d/"
rm /etc/apt/sources.list.d/feralfile.list
cat > /etc/apt/sources.list.d/feralfile.list << EOF
deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/feralfile.asc] https://feralfile-device-distribution.bitmark-development.workers.dev/ $LOCAL_BRANCH main 
EOF
