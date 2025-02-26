#!/bin/bash -e

if [ ! -d "${ROOTFS_DIR}" ]; then
    copy_previous
fi

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

EXPORT_ROOTFS_DIR="${WORK_DIR}/stage-3/rootfs"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

# 1) Just compute and create the .img
BOOT_SIZE="$((512 * 1024 * 1024))"
ROOT_SIZE=$(du -x --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot/firmware --block-size=1 | cut -f 1)

ALIGN="$((4 * 1024 * 1024))"
ROOT_MARGIN="$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)"

BOOT_PART_START=$((ALIGN))
BOOT_PART_SIZE=$(((BOOT_SIZE + ALIGN - 1) / ALIGN * ALIGN))
ROOT_PART_START=$((BOOT_PART_START + BOOT_PART_SIZE))
ROOT_PART_SIZE=$(((ROOT_SIZE + ROOT_MARGIN + ALIGN  - 1) / ALIGN * ALIGN))

# For two identical rootfs partitions, multiply root partition size by 2
IMG_SIZE=$((BOOT_PART_START + BOOT_PART_SIZE + 2 * ROOT_PART_SIZE))
truncate -s "${IMG_SIZE}" "${IMG_FILE}"

# 2) Partition it with parted
parted --script "${IMG_FILE}" mklabel msdos
parted --script "${IMG_FILE}" unit B mkpart primary fat32 \
  "${BOOT_PART_START}" "$((BOOT_PART_START + BOOT_PART_SIZE - 1))"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 \
  "${ROOT_PART_START}" "$((ROOT_PART_START + ROOT_PART_SIZE - 1))"
THIRD_PART_START=$((ROOT_PART_START + ROOT_PART_SIZE))
THIRD_PART_END=$((THIRD_PART_START + ROOT_PART_SIZE - 1))
parted --script "${IMG_FILE}" unit B mkpart primary ext4 \
  "${THIRD_PART_START}" "${THIRD_PART_END}"

# 3) (Optionally) set up loop device now, or do it in 00-run.sh
unmount_image "${IMG_FILE}"  # ensure we don't keep anything mounted