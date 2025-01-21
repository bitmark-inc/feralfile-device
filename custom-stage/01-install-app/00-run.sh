#!/bin/bash

mkdir -p "${ROOTFS_DIR}/home/feralfile/feralfile/"

# Copy from the stage directory to the ROOTFS
cp "feralfile-launcher_arm64.deb" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy feralfile-launcher_arm64.deb"
    exit 1
} 
cp "feralfile-launcher.conf" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy feralfile-launcher.conf"
    exit 1
} 
cp "files/feralfile-ota-update.sh" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy files/feralfile-ota-update.sh"
    exit 1
}
cp "files/feralfile-chromium.sh" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy files/feralfile-chromium.sh"
    exit 1
}
cp "files/feralfile-switcher.sh" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy files/feralfile-switcher.sh"
    exit 1
}