#!/bin/bash -e

# If ROOTFS_DIR doesn't exist, copy from previous stage
if [ ! -d "${ROOTFS_DIR}" ]; then
    if [ -d "${PREV_ROOTFS_DIR}" ]; then
        echo "Copying previous rootfs directory..."
        mkdir -p "${ROOTFS_DIR}"
        rsync -aHAXx --delete "${PREV_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
    else
        echo "Creating new rootfs directory..."
        mkdir -p "${ROOTFS_DIR}"
        # Initialize with debootstrap if needed
        if [ -x "$(command -v debootstrap)" ]; then
            debootstrap --arch=arm64 bookworm "${ROOTFS_DIR}" http://deb.debian.org/debian/
        fi
    fi
fi

# Ensure the directory exists and has proper permissions
mkdir -p "${ROOTFS_DIR}"
chmod 755 "${ROOTFS_DIR}" 