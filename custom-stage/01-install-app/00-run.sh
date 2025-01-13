#!/bin/bash
# Copy from the stage directory to the ROOTFS
cp "feralfile-launcher_arm64.deb" "${ROOTFS_DIR}/" || {
    echo "Error: Failed to copy feralfile-launcher_arm64.deb"
    exit 1
} 
cp "feralfile-launcher.conf" "${ROOTFS_DIR}/" || {
    echo "Error: Failed to copy feralfile-launcher.conf"
    exit 1
} 
install -v -m 755 files/feralfile-ota-update.sh "${ROOTFS_DIR}/usr/local/bin/feralfile-ota-update.sh"