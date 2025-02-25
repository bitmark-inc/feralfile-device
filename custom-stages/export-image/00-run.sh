#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"
LOOP_DEV="$(losetup -j "${IMG_FILE}" | cut -d: -f1)"

# Format partitions, mount them, copy rootfs...
mkfs.vfat -F 32 -n boot "${LOOP_DEV}p1"
mkfs.ext4 -F -L rootfs "${LOOP_DEV}p2"
# etc...

mount "${LOOP_DEV}p2" /mnt/root
# rsync rootfs stuff...

# Boot partition
mkdir -p /mnt/boot
mount "${LOOP_DEV}p1" /mnt/boot

install -m 644 "$(dirname "$0")/files/cmdlineA.txt" /mnt/boot/cmdline.txt
install -m 644 "$(dirname "$0")/files/cmdlineB.txt" /mnt/boot/cmdlineB.txt

umount /mnt/boot
umount /mnt/root