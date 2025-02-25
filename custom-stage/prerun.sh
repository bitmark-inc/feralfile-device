#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}.img"

# Ensure the directory exists before creating the image file
mkdir -p "$(dirname "${IMG_FILE}")"

# Ensure the image exists
if [ ! -f "${IMG_FILE}" ]; then
  echo "Creating blank image: ${IMG_FILE}"
  dd if=/dev/zero of="${IMG_FILE}" bs=1M count=1200
fi

# Overwrite any existing partition table
parted --script "${IMG_FILE}" mklabel msdos

# Create partition #1 - boot (FAT32), 256MB
parted --script "${IMG_FILE}" mkpart primary fat32 0% 256MB

# Create partition #2 - rootfsA (ext4), from 256MB to ~1536MB
parted --script "${IMG_FILE}" mkpart primary ext4 256MB 1536MB

# Create partition #3 - rootfsB (ext4), from 1536MB to 100%
parted --script "${IMG_FILE}" mkpart primary ext4 1536MB 100%

# Optionally keep the existing check for ROOTFS_DIR:
if [ ! -d "${ROOTFS_DIR}" ]; then
  copy_previous
fi