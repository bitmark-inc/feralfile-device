#!/bin/bash -e

# Install required packages in the busybox partition
on_chroot << EOF
apt-get update
apt-get install -y busybox-static
EOF

# Create the update checker script
cat > "${ROOTFS_DIR}/usr/local/sbin/check_update.sh" << 'EOF'
#!/bin/busybox sh

UPDATE_PART="/dev/mmcblk0p2"
OS_PART="/dev/mmcblk0p4"
MOUNT_POINT="/mnt/update"

# Mount update partition
mkdir -p "${MOUNT_POINT}"
mount "${UPDATE_PART}" "${MOUNT_POINT}"

# Check for update image
if [ -f "${MOUNT_POINT}/update.img" ]; then
    echo "Found update image, applying..."
    
    # Unmount OS partition if mounted
    umount "${OS_PART}" 2>/dev/null || true
    
    # Write image to OS partition
    dd if="${MOUNT_POINT}/update.img" of="${OS_PART}" bs=4M
    sync
    
    # Remove update image
    rm "${MOUNT_POINT}/update.img"
    sync
    
    echo "Update complete, rebooting..."
    reboot
else
    echo "No update found, booting normal system..."
    exec switch_root /mnt/os /sbin/init
fi
EOF

chmod +x "${ROOTFS_DIR}/usr/local/sbin/check_update.sh"

# Create custom init script for busybox
cat > "${ROOTFS_DIR}/init" << 'EOF'
#!/bin/busybox sh

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Mount OS partition
mkdir -p /mnt/os
mount /dev/mmcblk0p4 /mnt/os

# Run update checker
/usr/local/sbin/check_update.sh
EOF

chmod +x "${ROOTFS_DIR}/init" 