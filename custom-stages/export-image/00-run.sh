#!/bin/bash -e

# Point to the final .img that was created/partitioned in prerun.sh
IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

# Attach the image to a loop device, scanning for partitions
cnt=0
until ensure_next_loopdev && LOOP_DEV="$(losetup --show --find --partscan "$IMG_FILE")"; do
  if [ "$cnt" -lt 5 ]; then
    cnt=$((cnt + 1))
    echo "Error in losetup. Retrying..."
    sleep 5
  else
    echo "ERROR: losetup failed; exiting"
    exit 1
  fi
done

# Identify the three partitions we created in prerun.sh
BOOT_DEV="${LOOP_DEV}p1"
ROOT_DEV="${LOOP_DEV}p2"
ROOTB_DEV="${LOOP_DEV}p3"

# Make filesystems (adjust labels to your preference)
mkfs.vfat -n bootfs -F 32 -s 4 -v "$BOOT_DEV"  # FAT32 for /boot
mkfs.ext4 -L rootfs  "$ROOT_DEV"              # Ext4 for rootfs A
mkfs.ext4 -L rootfsB "$ROOTB_DEV"            # Ext4 for rootfs B

# Mount rootfs (partition #2)
mkdir -p "${ROOTFS_DIR}"
mount -v "$ROOT_DEV" "${ROOTFS_DIR}"

# Mount boot partition (partition #1) inside rootfs
mkdir -p "${ROOTFS_DIR}/boot/firmware"
mount -v "$BOOT_DEV" "${ROOTFS_DIR}/boot/firmware"

# Copy the filesystem from previous stage (stage-3) into p2
EXPORT_ROOTFS_DIR="${WORK_DIR}/stage-3/rootfs"

# Exclude apt cache and /boot/firmware since we're mounting real firmware partition
rsync -aHAXx --exclude var/cache/apt/archives --exclude boot/firmware \
   "${EXPORT_ROOTFS_DIR}/" "${ROOTFS_DIR}/"

# Copy the boot files into the mounted firmware partition
rsync -rtx "${EXPORT_ROOTFS_DIR}/boot/firmware/" "${ROOTFS_DIR}/boot/firmware/"

# Cleanup: unmount and detach loop
umount -v "${ROOTFS_DIR}/boot/firmware"
umount -v "${ROOTFS_DIR}"
losetup -d "$LOOP_DEV"