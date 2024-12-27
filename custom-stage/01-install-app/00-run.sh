#!/bin/bash
# Copy from the stage directory to the ROOTFS
cp "feralfile-launcher_arm64.deb" "${ROOTFS_DIR}/" || {
    echo "Error: Failed to copy feralfile-launcher_arm64.deb"
    exit 1
} 