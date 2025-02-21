#!/bin/bash -e

# Update boot configuration to load busybox first
cat > "${ROOTFS_DIR}/boot/cmdline.txt" << 'EOF'
console=serial0,115200 console=tty1 root=/dev/mmcblk0p3 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait init=/init
EOF

# Create and set permissions for proc directory
mkdir -p "${ROOTFS_DIR}/proc"
chmod 755 "${ROOTFS_DIR}/proc" 