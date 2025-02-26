#!/bin/bash -e

# If your script calculates/assigns these:
IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}.img"
LOOP_DEV="$(losetup -j "${IMG_FILE}" | cut -d: -f1)"

# Format root partition (p2) as ext4
mkfs.ext4 -F -L rootfs "${LOOP_DEV}p2"

# Mount it so $ROOTFS_DIR points to an actual filesystem
mkdir -p "${ROOTFS_DIR}"
mount "${LOOP_DEV}p2" "${ROOTFS_DIR}"

# If you need the OS from the previous stage:
if [ ! -d "${ROOTFS_DIR}/bin" ]; then
  copy_previous  # or rsync from a prior rootfs
fi

# Now $ROOTFS_DIR/usr/bin definitely exists
mkdir -p "${ROOTFS_DIR}/usr/bin"
cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"