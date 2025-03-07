#!/bin/bash

mkdir -p "${ROOTFS_DIR}/home/feralfile/feralfile/"

# Copy from the stage directory to the ROOTFS
cp "feralfile-launcher.conf" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy feralfile-launcher.conf"
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
cp "files/feralfile-watchdog.py" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy files/feralfile-watchdog.py"
    exit 1
}
cp "files/feralfile-install-deps.sh" "${ROOTFS_DIR}/home/feralfile/feralfile/" || {
    echo "Error: Failed to copy files/feralfile-install-deps.sh"
    exit 1
}

mkdir -p "${ROOTFS_DIR}/etc/apt/trusted.gpg.d/"
cp "files/apt-public-key.asc" "${ROOTFS_DIR}/etc/apt/trusted.gpg.d/feralfile.asc" || {
    echo "Error: Failed to copy files/apt-public-key.asc"
    exit 1
}
