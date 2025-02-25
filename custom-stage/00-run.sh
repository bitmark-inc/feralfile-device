#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}"
LOOP_DEV="$(losetup -j "${IMG_FILE}" | cut -d: -f1)"

# Format partitions
mkfs.vfat -F 32 -n boot "${LOOP_DEV}p1"
mkfs.ext4 -F -L rootfsA "${LOOP_DEV}p2"
mkfs.ext4 -F -L rootfsB "${LOOP_DEV}p3"

# Mount points
mkdir -p /mnt/rootfsA
mkdir -p /mnt/rootfsB
mkdir -p /mnt/boot

# Mount rootfsA and copy OS files from pi-gen's build
mount "${LOOP_DEV}p2" /mnt/rootfsA
rsync -aHAXx --exclude /boot --exclude /dev --exclude /proc --exclude /sys \
    "${ROOTFS_DIR}/" /mnt/rootfsA/

# Copy the boot files
mount "${LOOP_DEV}p1" /mnt/boot
rsync -aHAXx "${ROOTFS_DIR}/boot/" /mnt/boot/

# Copy custom cmdline file(s)
install -m 644 "${STAGE_DIR}/files/cmdlineA.txt" /mnt/boot/cmdline.txt
install -m 644 "${STAGE_DIR}/files/cmdlineB.txt" /mnt/boot/

umount /mnt/boot

# Clone rootfsA -> rootfsB
mount "${LOOP_DEV}p3" /mnt/rootfsB
rsync -aHAXx /mnt/rootfsA/ /mnt/rootfsB/
umount /mnt/rootfsB

umount /mnt/rootfsA