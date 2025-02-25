#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}.img"

# Ensure the directory exists before creating the image file
mkdir -p "$(dirname "${IMG_FILE}")"

# Create the blank image with at least 2GB (adjust as needed)
if [ ! -f "${IMG_FILE}" ]; then
  echo "Creating blank image: ${IMG_FILE}"
  dd if=/dev/zero of="${IMG_FILE}" bs=1M count=2048  # 2GB
fi

# Partition the image
parted --script "${IMG_FILE}" mklabel msdos
parted --script "${IMG_FILE}" mkpart primary fat32 0% 256MB
parted --script "${IMG_FILE}" mkpart primary ext4 256MB 1536MB
parted --script "${IMG_FILE}" mkpart primary ext4 1536MB 100%

# Ensure previous stage data is available
if [ ! -d "${ROOTFS_DIR}" ]; then
  copy_previous
fi