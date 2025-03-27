#!/bin/bash

cp -r "files/migrations" "${ROOTFS_DIR}/home/feralfile/migrations" || {
    echo "Error: Failed to copy files/migrations"
    exit 1
}
chmod -R 755 "${ROOTFS_DIR}/home/feralfile/migrations"

cp -r "files/scripts" "${ROOTFS_DIR}/home/feralfile/scripts" || {
    echo "Error: Failed to copy files/scripts"
    exit 1
}
chmod -R 755 "${ROOTFS_DIR}/home/feralfile/scripts"

cp -r "files/services" "${ROOTFS_DIR}/home/feralfile/services" || {
    echo "Error: Failed to copy files/services"
    exit 1
}
chmod -R 755 "${ROOTFS_DIR}/home/feralfile/services"

cp "files/migrate.sh" "${ROOTFS_DIR}/home/feralfile/migrate.sh" || {
    echo "Error: Failed to copy files/migrate.sh"
    exit 1
}
chmod 755 "${ROOTFS_DIR}/home/feralfile/migrate.sh"

mkdir -p "${ROOTFS_DIR}/home/feralfile/.config/feralfile"
cp "feralfile-launcher.conf" "${ROOTFS_DIR}/home/feralfile/.config/feralfile/feralfile-launcher.conf" || {
    echo "Error: Failed to copy feralfile-launcher.conf"
    exit 1
} 

mkdir -p "${ROOTFS_DIR}/etc/apt/trusted.gpg.d/"
cp "files/apt-public-key.asc" "${ROOTFS_DIR}/etc/apt/trusted.gpg.d/feralfile.asc" || {
    echo "Error: Failed to copy files/apt-public-key.asc"
    exit 1
}
chmod 644 "${ROOTFS_DIR}/etc/apt/trusted.gpg.d/feralfile.asc"

cp "files/rotate-display.sh" "${ROOTFS_DIR}/usr/local/bin/rotate-display.sh" || {
    echo "Error: Failed to copy files/rotate-display.sh"
    exit 1
}
