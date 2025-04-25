#!/bin/bash -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CUSTOM_STAGE_DIR="$PARENT_DIR/custom-stage"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exit 1
fi

# Create user if it doesn't exist
if ! id -u feralfile &>/dev/null; then
    echo "Creating feralfile user..."
    useradd -m -s /bin/bash feralfile
fi

# Install Ubuntu-compatible packages (from 00-packages)
echo "Installing packages equivalent to 00-packages..."
apt-get update
apt-get install -y \
    alsa-utils \
    policykit-1 \
    chromium-browser \
    fonts-droid-fallback \
    fonts-liberation2 \
    obconf \
    python3-pyqt5 \
    python3-opengl \
    python3-sentry-sdk \
    python3-websockets \
    vulkan-tools mesa-vulkan-drivers \
    ffmpeg

# Install Ubuntu-compatible packages (from 00-packages-nr)
echo "Installing Ubuntu equivalents to 00-packages-nr..."
apt-get install -y \
    xserver-xorg xinit xdotool \
    unclutter \
    mousepad \
    eom \
    lxde \
    zenity xdg-utils \
    lightdm \
    git

# Notes on package changes from Raspberry Pi OS to Ubuntu:
# - Removed: rpi-chromium-mods (Raspberry Pi specific)
# - Removed: libwidevinecdm0 (Raspberry Pi specific DRM)
# - Removed: gldriver-test (Raspberry Pi specific)
# - Changed: chromium -> chromium-browser (Ubuntu package name)

# Set up automatic login (equivalent to the raspi-config command)
echo "Setting up automatic login..."
# This is Ubuntu-specific
mkdir -p /etc/lightdm/lightdm.conf.d/
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf << EOF
[Seat:*]
autologin-user=feralfile
autologin-user-timeout=0
EOF

# Mark packages as auto-installed
echo "Marking packages as auto-installed..."
apt-mark auto python3-pyqt5 python3-opengl

# Create required directories
echo "Creating required directories..."
mkdir -p /home/feralfile/.config/feralfile
mkdir -p /etc/apt/trusted.gpg.d/

# Copy files to appropriate locations
echo "Copying files..."
# Copy from the custom-stage directory structure
cp -r "$CUSTOM_STAGE_DIR/01-install-app/files/scripts" /home/feralfile/scripts
chmod -R 755 /home/feralfile/scripts

cp -r "$CUSTOM_STAGE_DIR/01-install-app/files/migrations" /home/feralfile/migrations
chmod -R 755 /home/feralfile/migrations

cp -r "$CUSTOM_STAGE_DIR/01-install-app/files/services" /home/feralfile/services
chmod -R 755 /home/feralfile/services

cp "$CUSTOM_STAGE_DIR/01-install-app/files/migrate.sh" /home/feralfile/migrate.sh
chmod 755 /home/feralfile/migrate.sh

# Check for feralfile-launcher.conf in parent directory
if [ -f "$PARENT_DIR/feralfile-launcher.conf" ]; then
    cp "$PARENT_DIR/feralfile-launcher.conf" /home/feralfile/.config/feralfile/feralfile-launcher.conf
    chmod 644 /home/feralfile/.config/feralfile/feralfile-launcher.conf
else
    echo "Warning: feralfile-launcher.conf not found"
fi

cp "$CUSTOM_STAGE_DIR/01-install-app/files/apt-public-key.asc" /etc/apt/trusted.gpg.d/feralfile.asc
chmod 644 /etc/apt/trusted.gpg.d/feralfile.asc

# INSTALLATION FROM MIGRATION SCRIPTS

# Add user to required groups
echo "Setting up user permissions..."
usermod -a -G bluetooth,dialout feralfile

# Install BlueZ - Ubuntu version check
echo "Installing/upgrading BlueZ..."
DESIRED_BLUE_Z_VERSION="5.79"
if command -v bluetoothd >/dev/null 2>&1; then
  CURRENT_VERSION="$(bluetoothd -v)"
  echo "Current BlueZ version: $CURRENT_VERSION"
else
  CURRENT_VERSION="0.0"
  echo "BlueZ not installed."
fi

# Function to compare versions
version_lt() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]
}

if version_lt "$CURRENT_VERSION" "$DESIRED_BLUE_Z_VERSION"; then
  echo "Updating BlueZ to version $DESIRED_BLUE_Z_VERSION..."

  apt-get install -y libglib2.0-dev libdbus-1-dev libudev-dev libical-dev libreadline-dev python3-docutils

  cd /home/feralfile
  wget http://www.kernel.org/pub/linux/bluetooth/bluez-${DESIRED_BLUE_Z_VERSION}.tar.xz
  tar xvf bluez-${DESIRED_BLUE_Z_VERSION}.tar.xz
  cd bluez-${DESIRED_BLUE_Z_VERSION}/
  ./configure --prefix=/usr --mandir=/usr/share/man --sysconfdir=/etc --localstatedir=/var --with-systemdsystemunitdir=/lib/systemd/system --with-systemduserunitdir=/usr/lib/system --enable-experimental
  make -j4
  make install

  apt-get remove -y libglib2.0-dev libdbus-1-dev libudev-dev libical-dev libreadline-dev python3-docutils
  rm /home/feralfile/bluez-${DESIRED_BLUE_Z_VERSION}.tar.xz
  rm -rf /home/feralfile/bluez-${DESIRED_BLUE_Z_VERSION}
  cd /

  echo "BlueZ updated to $DESIRED_BLUE_Z_VERSION."
else
  echo "BlueZ is already up to date (version $CURRENT_VERSION)."
fi

# For Mesa packages - use Ubuntu packages instead of Raspberry Pi specific ones
echo "Installing Mesa packages from Ubuntu repositories..."
apt-get install -y \
    libgbm1 \
    libglapi-mesa \
    libgl1-mesa-dri \
    libegl-mesa0 \
    libglx-mesa0

# Create system service files
echo "Setting up system services..."
# Create feralfile service 
mkdir -p /etc/systemd/system

rm -f /etc/systemd/system/feralfile-launcher.service
cat > /etc/systemd/system/feralfile-launcher.service << EOF
[Unit]
Description=FeralFile Launcher Application
After=bluetooth.target
Requires=bluetooth.service

[Service]
User=feralfile
Group=feralfile
ExecStartPre=/bin/sleep 1.5
ExecStart=/opt/feralfile/feralfile
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/feralfile/.Xauthority
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
EOF

rm -f /etc/systemd/system/feralfile-chromium.service
cat > /etc/systemd/system/feralfile-chromium.service << EOF
[Unit]
Description=FeralFile Chromium
After=feralfile-launcher.service
Wants=feralfile-launcher.service

[Service]
User=feralfile
Group=feralfile
ExecStart=/home/feralfile/services/feralfile-chromium.sh
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
EOF

rm -f /etc/systemd/system/feralfile-watchdog.service
cat > /etc/systemd/system/feralfile-watchdog.service << EOF
[Unit]
Description=WebSocket Watchdog Service
After=feralfile-launcher.service
Wants=feralfile-launcher.service

[Service]
ExecStart=python3 /home/feralfile/services/feralfile-watchdog.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

rm -f /etc/systemd/system/feralfile-updater@.service
cat > /etc/systemd/system/feralfile-updater@.service << EOF
[Unit]
Description=FeralFile Updater Instance - %i
After=network.target

[Service]
Type=simple
ExecStart=/home/feralfile/services/feralfile-updater.sh
EOF

rm -f /etc/systemd/system/feralfile-updater@.timer
cat > /etc/systemd/system/feralfile-updater@.timer << EOF
[Unit]
Description=FeralFile Updater - %i Run

[Timer]
Persistent=true
OnCalendar=%i
RandomizedDelaySec=7200  # Up to 2 hour random delay
Unit=feralfile-updater@%i.service

[Install]
WantedBy=timers.target
EOF

# Set up config files
echo "Setting up configuration files..."
function get_config_value() {
  local key="$1"
  grep "^$key" "/home/feralfile/.config/feralfile/feralfile-launcher.conf" | awk -F' = ' '{print $2}' | tr -d ' '
}

BASIC_AUTH_USER="$(get_config_value "distribution_auth_user" || echo "")"
BASIC_AUTH_PASS="$(get_config_value "distribution_auth_password" || echo "")"
LOCAL_BRANCH="$(get_config_value "app_branch" || echo "master")"

# Create LXDE autostart
mkdir -p /home/feralfile/.config/lxsession/LXDE
rm -f /home/feralfile/.config/lxsession/LXDE/autostart
cat > /home/feralfile/.config/lxsession/LXDE/autostart <<EOF
@env vblank_mode=1
@unclutter -idle 1
@/home/feralfile/scripts/lxde-startup.sh
EOF

# Don't use polkit to manage NetworkManager which will cause bugs
mkdir -p /etc/NetworkManager/conf.d
rm -f /etc/NetworkManager/conf.d/feralfile.conf
cat > /etc/NetworkManager/conf.d/feralfile.conf <<EOF
[main]
auth-polkit=false
EOF

# Enable Just Work bluetooth connection
mkdir -p /etc/bluetooth
rm -f /etc/bluetooth/main.conf
cat > /etc/bluetooth/main.conf <<EOF
[General]
JustWorksRepairing = always
EOF

# Set APT settings
mkdir -p "/etc/apt/auth.conf.d/"
rm -f /etc/apt/auth.conf.d/feralfile.conf
cat > /etc/apt/auth.conf.d/feralfile.conf << EOF
machine feralfile-device-distribution.bitmark-development.workers.dev
login $BASIC_AUTH_USER
password $BASIC_AUTH_PASS
EOF

mkdir -p "/etc/apt/sources.list.d/"
rm -f /etc/apt/sources.list.d/feralfile.list
cat > /etc/apt/sources.list.d/feralfile.list << EOF
deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/feralfile.asc] https://feralfile-device-distribution.bitmark-development.workers.dev/ $LOCAL_BRANCH main 
EOF

# Install Feralfile Launcher
echo "Installing Feralfile Launcher..."
apt update
apt -y install feralfile-launcher || {
    echo "Warning: Failed to install feralfile-launcher. Make sure the repository is correctly set up."
}

# Enable services
echo "Enabling services..."
systemctl enable feralfile-launcher.service
systemctl enable feralfile-chromium.service
systemctl enable feralfile-watchdog.service
systemctl enable feralfile-updater@daily.timer

# Set ownership of all copied files to feralfile user
chown -R feralfile:feralfile /home/feralfile

echo "Setup complete!"
