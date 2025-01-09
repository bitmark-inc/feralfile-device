#!/bin/bash
# Create the target directory first
mkdir -p "${ROOTFS_DIR}/opt/feralfile" || {
    echo "Error: Failed to create /opt/feralfile directory"
    exit 1
}

# Copy version info and update service files to the ROOTFS
cp "version.json" "${ROOTFS_DIR}/opt/feralfile/" || {
    echo "Error: Failed to copy version.json"
    exit 1
}

# Copy the update service script
cp "update-checker.sh" "${ROOTFS_DIR}/opt/feralfile/" || {
    echo "Error: Failed to copy update-checker.sh"
    exit 1
} 