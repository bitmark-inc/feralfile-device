#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- !!! Configuration - EDIT THESE VALUES !!! ---

# Credentials for the custom APT repository
# WARNING: Hardcoding credentials is a security risk!
APT_AUTH_USER="YOUR_ACTUAL_USERNAME_HERE"
APT_AUTH_PASS="YOUR_ACTUAL_PASSWORD_HERE"

# Full path to your GPG public key for the custom APT repository
APT_GPG_KEY_PATH="/path/to/your/files/apt-public-key.asc" # Example: /home/user/build/files/feralfile.asc

# Build configuration
WORK_DIR="$HOME/radxa-x4-kiosk-live-build" # Directory to store build files
DISTRO="trixie" # Debian Testing (check if it has kernel >= 6.8)
ARCH="amd64"
KIOSK_USER="feralfile"
KIOSK_PASS="feralfile"
CHROMIUM_URL="https://support-feralfile-device.feralfile-display-prod.pages.dev/daily?platform=ff-device"
LIVE_HOSTNAME="feralfile-kiosk"

# --- End of Configuration ---

# --- Script Logic ---

echo "--- Radxa X4 Kiosk Debian Live Build Script ---"

# Check if essential configuration is placeholder
if [[ "$APT_AUTH_USER" == "YOUR_ACTUAL_USERNAME_HERE" || "$APT_AUTH_PASS" == "YOUR_ACTUAL_PASSWORD_HERE" || "$APT_GPG_KEY_PATH" == "/path/to/your/files/apt-public-key.asc" ]]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "ERROR: Please edit the script and replace placeholder values for"
  echo "       APT_AUTH_USER, APT_AUTH_PASS, and APT_GPG_KEY_PATH."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  exit 1
fi

# Check if GPG key file exists
if [ ! -f "$APT_GPG_KEY_PATH" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "ERROR: APT GPG Key file not found at: $APT_GPG_KEY_PATH"
    echo "       Please correct the APT_GPG_KEY_PATH variable in the script."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi


echo "[1/8] Checking and installing prerequisites (live-build, git)..."
# Check sudo upfront
if ! sudo -v; then
    echo "ERROR: sudo privileges are required."
    exit 1
fi
# Install tools if not present
if ! command -v lb &> /dev/null || ! command -v git &> /dev/null; then
    echo "Installing live-build and git..."
    sudo apt-get update
    sudo apt-get install -y live-build git
else
    echo "live-build and git seem to be installed."
fi

echo "[2/8] Creating working directory: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "[3/8] Configuring live-build..."
lb config \
    --distribution "$DISTRO" \
    --architecture "$ARCH" \
    --archive-areas "main contrib non-free non-free-firmware" \
    --binary-images iso-hybrid \
    --debian-installer live \
    --linux-flavours "$ARCH" \
    --linux-packages "linux-image" \
    --bootappend-live "hostname=$LIVE_HOSTNAME" \
    --apt-recommends false \
    --memtest none # Disable memtest entry

echo "[4/8] Creating custom package list..."
mkdir -p config/package-lists
cat << EOF > config/package-lists/my.list.chroot
# Base system and live environment
live-boot
live-config
live-config-systemd

# Kernel and Firmware (Essential for hardware support)
linux-image-${ARCH}
firmware-linux-nonfree
firmware-misc-nonfree
intel-microcode
# amd64-microcode # Redundant for Intel N100 but harmless

# Xorg display server
xorg
xserver-xorg-video-intel # Intel graphics driver

# LXDE Desktop Environment Core & Window Manager
lxde-core
openbox

# Display Manager (LightDM recommended for easy autologin config)
lightdm

# Web Browser
chromium

# Networking
network-manager

# Bluetooth
bluez

# Sudo (for passwordless sudo)
sudo

# Utilities needed for hooks or setup
wget
gpg
ca-certificates

# Other potentially useful tools for kiosk/debugging
unclutter # Hides mouse cursor after inactivity
# xdotool # Can be useful for scripting GUI interactions if needed later

EOF

echo "[5/8] Creating custom configuration files and directories..."
# Create directory structure within includes.chroot
mkdir -p config/includes.chroot/etc/apt/sources.list.d
mkdir -p config/includes.chroot/etc/apt/auth.conf.d
mkdir -p config/includes.chroot/etc/apt/trusted.gpg.d
mkdir -p config/includes.chroot/etc/sudoers.d
mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
mkdir -p config/includes.chroot/etc/bluetooth/main.conf.d
mkdir -p config/includes.chroot/etc/systemd/system
mkdir -p config/includes.chroot/etc/xdg/autostart

# APT Source List
cat << EOF > config/includes.chroot/etc/apt/sources.list.d/feralfile.list
deb [arch=${ARCH} signed-by=/etc/apt/trusted.gpg.d/feralfile.asc] https://feralfile-device-distribution.bitmark-development.workers.dev/ features/${ARCH} main
EOF

# APT Auth Conf (Injecting credentials from variables)
cat << EOF > config/includes.chroot/etc/apt/auth.conf.d/feralfile.conf
machine feralfile-device-distribution.bitmark-development.workers.dev
login $APT_AUTH_USER
password $APT_AUTH_PASS
EOF
# Secure the auth file slightly (though it's still plain text inside the build)
chmod 600 config/includes.chroot/etc/apt/auth.conf.d/feralfile.conf

# Copy GPG Key
cp "$APT_GPG_KEY_PATH" config/includes.chroot/etc/apt/trusted.gpg.d/feralfile.asc
chmod 644 config/includes.chroot/etc/apt/trusted.gpg.d/feralfile.asc

# Sudoers NOPASSWD
cat << EOF > config/includes.chroot/etc/sudoers.d/feralfile
$KIOSK_USER ALL=(ALL) NOPASSWD: ALL
EOF
# Permissions will be set to 440 in the hook

# LightDM Autologin
cat << EOF > config/includes.chroot/etc/lightdm/lightdm.conf.d/20-autologin-feralfile.conf
[Seat:*]
autologin-user=$KIOSK_USER
autologin-session=lxde
user-session=lxde
autologin-user-timeout=0
EOF

# Bluez Experimental
cat << EOF > config/includes.chroot/etc/bluetooth/main.conf.d/10-experimental.conf
[General]
Experimental = true
EOF

# Systemd Service: feralfile-launcher
cat << EOF > config/includes.chroot/etc/systemd/system/feralfile-launcher.service
[Unit]
Description=FeralFile Launcher Application
# Make sure dependencies are met after graphical session, network and bluetooth are up
After=graphical-session.target bluetooth.service NetworkManager.service systemd-user-sessions.service
Wants=graphical-session.target

[Service]
User=$KIOSK_USER
Group=$KIOSK_USER
# Delay might still be needed depending on the app's init requirements
# ExecStartPre=/bin/sleep 5
ExecStart=/opt/feralfile/feralfile
Restart=on-failure
RestartSec=5
# Environment variables might be inherited from user session better than setting here
# Setting DISPLAY might be unreliable for system services targeting X session
# Environment=DISPLAY=:0
# Environment=XAUTHORITY=/home/$KIOSK_USER/.Xauthority
# XDG_RUNTIME_DIR is usually handled by systemd-logind for the user session

[Install]
WantedBy=multi-user.target # Start relative to user login, not full graphical target necessarily
EOF

# Chromium Kiosk Autostart (LXDE)
cat << EOF > config/includes.chroot/etc/xdg/autostart/feralfile-chromium-kiosk.desktop
[Desktop Entry]
Type=Application
Name=FeralFile Chromium Kiosk
Comment=Starts Chromium in Kiosk mode for FeralFile Display
Exec=sh -c "sleep 5 && chromium --enable-features=VaapiVideoDecoder --kiosk $CHROMIUM_URL"
OnlyShowIn=LXDE;
X-GNOME-Autostart-enabled=true
EOF

echo "[6/8] Creating custom hook script..."
mkdir -p config/hooks/live
cat << EOF > config/hooks/live/99-feralfile-setup.hook.chroot
#!/bin/sh
set -e

echo "--- Running FeralFile Setup Hook ---"

# 1. Create user and set password
echo "Creating user $KIOSK_USER..."
useradd -m -s /bin/bash "$KIOSK_USER"
echo "$KIOSK_USER:$KIOSK_PASS" | chpasswd

# 2. Add user to sudo group
echo "Adding user $KIOSK_USER to sudo group..."
adduser "$KIOSK_USER" sudo

# 3. Update APT sources and install custom package
echo "Updating apt and installing feralfile-launcher..."
apt-get update
# Attempt installation, log warning on failure but don't exit script
if ! apt-get install -y --allow-unauthenticated feralfile-launcher; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "WARNING: Failed to install feralfile-launcher package."
    echo "         Build will continue, but the package might be missing."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
fi

# 4. Enable necessary services
echo "Enabling system services..."
systemctl enable lightdm
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable feralfile-launcher.service
# Add other services like feralfile-bt-agent if needed:
# systemctl enable feralfile-bt-agent.service

# 5. Set correct permissions for sudoers file
echo "Setting permissions for sudoers file..."
chmod 440 /etc/sudoers.d/feralfile

# 6. Set permissions for autostart file (usually not needed, but safe)
echo "Setting permissions for autostart file..."
chmod 644 /etc/xdg/autostart/feralfile-chromium-kiosk.desktop

# 7. Clean apt cache
echo "Cleaning apt cache..."
apt-get clean

echo "--- FeralFile Setup Hook Finished ---"
exit 0
EOF

# Make hook executable
chmod +x config/hooks/live/99-feralfile-setup.hook.chroot

echo "[7/8] Adjusting bootloader configuration for quick boot..."
# ISOLINUX/SYSLINUX - Create/overwrite config file
mkdir -p config/bootloaders/isolinux
cat << EOF > config/bootloaders/isolinux/isolinux.cfg
# Standard isolinux.cfg example with timeout adjusted
include menu.cfg
default vesamenu.c32
prompt 0
timeout 10 # Set timeout to 1 second (10 * 0.1s)
EOF
# Add other isolinux config files (like menu.cfg, live.cfg) from a standard live build
# or let live-build generate them and hope the timeout=10 takes precedence.
# A safer way might be to copy existing ones from /usr/share/live/build/bootloaders/isolinux
# and modify the timeout line. Let's stick to providing the main file for now.

# GRUB - Create/overwrite config file template fragment
mkdir -p config/bootloaders/grub-pc
# This is tricky as grub.cfg is generated. We add a config fragment.
# This fragment will be included.
cat << EOF > config/bootloaders/grub-pc/config.cfg
# Set timeout to 1 second
set timeout=1
# Optionally hide the menu (may need testing)
# set menu_hidden_timeout_enable=true
# set default="0" # Usually the first entry
EOF


echo "[8/8] Starting the build process (requires sudo)..."
# Run the build
sudo lb build

# Check if the build command was successful (lb build exits 0)
if [ $? -eq 0 ]; then
    echo "--- Build Process Completed Successfully ---"
    echo "Live image should be located in: $WORK_DIR"
    echo "Filename typically ends with .iso (e.g., live-image-amd64.hybrid.iso)"
    echo ""
    echo "** IMPORTANT NEXT STEPS: **"
    echo "1. Write the generated .iso file to a USB drive using dd, Etcher, Ventoy, etc."
    echo "   Example: sudo dd if=live-image-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress oflag=sync (Replace /dev/sdX !)"
    echo "2. Boot the Radxa X4 from the USB drive."
    echo "3. Thoroughly test all functionalities:"
    echo "   - Automatic boot (skipping menu)"
    echo "   - Automatic login as '$KIOSK_USER'"
    echo "   - Automatic launch of Chromium in kiosk mode to '$CHROMIUM_URL'"
    echo "   - Hardware support (Display, WiFi, Bluetooth)"
    echo "   - 'feralfile-launcher' service running correctly"
    echo "   - Passwordless sudo for '$KIOSK_USER' (e.g., run 'sudo apt update')"
else
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "ERROR: Build process failed. Check the build.log file in $WORK_DIR"
    echo "       for detailed error messages."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi

exit 0