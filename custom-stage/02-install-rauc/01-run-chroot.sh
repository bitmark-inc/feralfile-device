#!/bin/bash -e

# This script runs within the chroot environment

# 1. Generate RAUC keys (optional) 
#    Or copy them from files/ if you already have them
if [ ! -f /etc/rauc/key.pem ]; then
  mkdir -p /etc/rauc
  openssl req -x509 -newkey rsa:2048 -keyout /etc/rauc/key.pem \
      -out /etc/rauc/cert.pem -nodes -days 3650 \
      -subj "/CN=FeralFileDeviceRAUC"
  chmod 600 /etc/rauc/key.pem
  chmod 644 /etc/rauc/cert.pem
fi

# 2. Install a basic system.conf 
if [ ! -f /etc/rauc/system.conf ]; then
  cat > /etc/rauc/system.conf <<EOF
[system]
compatible = feralfile
key=/etc/rauc/key.pem
cert=/etc/rauc/cert.pem

[slot.rootfs.0]
device=/dev/mmcblk0p2
type=ext4
bootname=A

[slot.rootfs.1]
device=/dev/mmcblk0p3
type=ext4
bootname=B
EOF
fi