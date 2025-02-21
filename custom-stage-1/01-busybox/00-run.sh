#!/bin/bash -e

mkdir -p "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/dev"
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

echo "Starting update check process..."

# Mount update partition
echo "Creating mount point directory at ${MOUNT_POINT}..."
mkdir -p "${MOUNT_POINT}" || echo "Failed to create mount point directory"

echo "Attempting to mount update partition ${UPDATE_PART}..."
mount "${UPDATE_PART}" "${MOUNT_POINT}" || echo "Failed to mount update partition"

# Check for update image
echo "Checking for update image..."
if [ -f "${MOUNT_POINT}/update.img" ]; then
    echo "Found update image, applying..."
    
    # Unmount OS partition if mounted
    echo "Unmounting OS partition ${OS_PART} if mounted..."
    umount "${OS_PART}" 2>/dev/null || true
    
    # Write image to OS partition
    echo "Writing update image to OS partition..."
    dd if="${MOUNT_POINT}/update.img" of="${OS_PART}" bs=4M || echo "Failed to write update image"
    sync || echo "Failed to sync after writing image"
    
    # Remove update image
    echo "Removing update image..."
    rm "${MOUNT_POINT}/update.img" || echo "Failed to remove update image"
    sync || echo "Failed to sync after removing image"
    
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

echo "
+------------------+
|                  |
|  ███████ ███████ |  ██   ██  ██ 
|  ██      ██      |   ██ ██   ██
|  ███████ ███████ |    ███    ██
|  ██      ██      |   ██ ██   ██
|  ██      ██      |  ██   ██  ██
|                  |
+------------------+
"

# Create essential directories
echo "Creating essential directories..."
mkdir -p /proc /sys /dev /root || echo "Failed to create essential directories"

echo "Mounting essential filesystems..."
mount -t proc proc /proc || echo "Failed to mount proc"
mount -t sysfs sysfs /sys || echo "Failed to mount sysfs"
mount -t devtmpfs devtmpfs /dev || echo "Failed to mount devtmpfs"

echo "Creating and mounting OS partition..."
mkdir -p /mnt/os || echo "Failed to create /mnt/os directory"
mount /dev/mmcblk0p4 /mnt/os || echo "Failed to mount OS partition"

echo "Running update checker..."
/usr/local/sbin/check_update.sh
EOF

chmod +x "${ROOTFS_DIR}/init" 