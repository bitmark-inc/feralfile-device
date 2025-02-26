#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

# 1) Set up loop device
cnt=0
until ensure_next_loopdev && LOOP_DEV="$(losetup --show --find --partscan "$IMG_FILE")"; do
  if [ $cnt -lt 5 ]; then
    cnt=$((cnt + 1))
    echo "Error in losetup. Retrying..."
    sleep 5
  else
    echo "ERROR: losetup failed; exiting"
    exit 1
  fi
done

# 2) Make filesystems
BOOT_DEV="${LOOP_DEV}p1"
ROOT_DEV="${LOOP_DEV}p2"
ROOTB_DEV="${LOOP_DEV}p3"

mkfs.vfat -n bootfs -F 32 -s 4 -v "$BOOT_DEV" > /dev/null
mkfs.ext4 -L rootfs "$ROOT_DEV" > /dev/null
mkfs.ext4 -L rootfsB "$ROOTB_DEV" > /dev/null

# 3) Mount partitions
mkdir -p "${ROOTFS_DIR}"
mount -v "$ROOT_DEV" "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}/boot/firmware"
mount -v "$BOOT_DEV" "${ROOTFS_DIR}/boot/firmware"

# 4) rsync from stage-3 rootfs
EXPORT_ROOTFS_DIR="${WORK_DIR}/stage-3/rootfs"
rsync -aHAXx --exclude var/cache/apt/archives --exclude boot/firmware \
   "${EXPORT_ROOTFS_DIR}/" "${ROOTFS_DIR}/"

rsync -rtx "${EXPORT_ROOTFS_DIR}/boot/firmware/" "${ROOTFS_DIR}/boot/firmware/"

# 5) Cleanup
umount -v "${ROOTFS_DIR}/boot/firmware"
umount -v "${ROOTFS_DIR}"
losetup -d "$LOOP_DEV"