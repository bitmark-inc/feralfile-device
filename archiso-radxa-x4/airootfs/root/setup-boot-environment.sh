#!/bin/bash

# This script sets up the boot environment for FeralFile Launcher

# Ensure the seat group exists
groupadd -f seat

# Add feralfile user to the seat group if it's not already there
if ! groups feralfile | grep -q seat; then
  usermod -aG seat feralfile
fi

# Create seatd configuration directory
mkdir -p /etc/seatd/seatd.conf.d

# Create seatd configuration file
cat > /etc/seatd/seatd.conf.d/10-seat-group.conf << EOF
group = seat
EOF

# Create systemd override directory for seatd
mkdir -p /etc/systemd/system/seatd.service.d

# Create systemd override file for seatd
cat > /etc/systemd/system/seatd.service.d/override.conf << EOF
[Service]
ExecStartPost=/bin/chmod 660 /run/seatd.sock
ExecStartPost=/bin/chgrp seat /run/seatd.sock
EOF

# Set correct permissions
chmod 644 /etc/seatd/seatd.conf.d/10-seat-group.conf
chmod 644 /etc/systemd/system/seatd.service.d/override.conf

# Create i915 module configuration
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/i915.conf << EOF
# Intel graphics configuration for N100
options i915 enable_guc=3 enable_fbc=1 modeset=1
EOF

# Enable the seatd service
systemctl enable seatd.service
systemctl enable plymouth-start.service

# Regenerate initramfs with Plymouth support
/root/rebuild-plymouth.sh

# Make sure systemd refreshes
systemctl daemon-reload

# Log completion
echo "Boot environment setup completed on $(date)" > /var/log/boot-setup.log 