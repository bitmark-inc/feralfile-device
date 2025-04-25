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

# Install packages from 00-packages
echo "Installing packages from 00-packages..."
apt-get update

# Read and install packages from 00-packages
if [ -f "$CUSTOM_STAGE_DIR/00-install-packages/00-packages" ]; then
    while read -r line; do
        if [ -n "$line" ]; then
            apt-get install -y $line
        fi
    done < "$CUSTOM_STAGE_DIR/00-install-packages/00-packages"
else
    echo "Warning: 00-packages file not found"
fi

# Read and install packages from 00-packages-nr
echo "Installing additional packages..."
if [ -f "$CUSTOM_STAGE_DIR/00-install-packages/00-packages-nr" ]; then
    while read -r line; do
        if [ -n "$line" ]; then
            apt-get install -y $line
        fi
    done < "$CUSTOM_STAGE_DIR/00-install-packages/00-packages-nr"
else
    echo "Warning: 00-packages-nr file not found"
fi

# Set up automatic login (equivalent to the raspi-config command)
echo "Setting up automatic login..."
# This is Ubuntu-specific and replaces the raspi-config command
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

# Run migration script
echo "Running migration script..."
sudo -u feralfile /home/feralfile/migrate.sh

# Set ownership of all copied files to feralfile user
chown -R feralfile:feralfile /home/feralfile

echo "Setup complete!"
