#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

# 1) Ensure the parent directory exists
mkdir -p "$(dirname "${IMG_FILE}")"

# 2) Create a blank image (2GB here, adjust as needed)
dd if=/dev/zero of="${IMG_FILE}" bs=1M count=2048

# 3) Partition it
parted --script "${IMG_FILE}" mklabel msdos
parted --script "${IMG_FILE}" mkpart primary fat32 0% 256MB
parted --script "${IMG_FILE}" mkpart primary ext4 256MB 1536MB
parted --script "${IMG_FILE}" mkpart primary ext4 1536MB 100%

# (optional) copy_previous if you need the prior stage rootfs
if [ ! -d "${ROOTFS_DIR}" ]; then
  copy_previous
fi