#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

# All partition sizes and starts will be aligned to this size (4MB in bytes)
ALIGN="$((4 * 1024 * 1024))"

# Calculate partition sizes in bytes
BOOT_SIZE="$((256 * 1024 * 1024))"    # 256MB
UPDATE_SIZE="$((2048 * 1024 * 1024))"  # 2048MB (update partition)
BUSYBOX_SIZE="$((1536 * 1024 * 1024))" # 1536MB (1.5GB standby partition)
ROOT_SIZE=$(du -x --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot/firmware --block-size=1 | cut -f 1)
ROOT_MARGIN="$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)"

# Debugging: Print sizes
echo "ROOT_SIZE: $ROOT_SIZE bytes (~$(($ROOT_SIZE / 1024 / 1024))MB)"
echo "ROOT_MARGIN: $ROOT_MARGIN bytes (~$(($ROOT_MARGIN / 1024 / 1024))MB)"

# Define partition starts and ends with proper alignment
BOOT_START="$ALIGN"  # Start at 4MB
BOOT_END=$(($BOOT_START + $BOOT_SIZE - 1))
BOOT_END_ALIGNED=$((($BOOT_END + $ALIGN - 1) / $ALIGN * $ALIGN - 1))

UPDATE_START=$(($BOOT_END_ALIGNED + 1))
UPDATE_END=$(($UPDATE_START + $UPDATE_SIZE - 1))
UPDATE_END_ALIGNED=$((($UPDATE_END + $ALIGN - 1) / $ALIGN * $ALIGN - 1))

BUSYBOX_START=$(($UPDATE_END_ALIGNED + 1))
BUSYBOX_END=$(($BUSYBOX_START + $BUSYBOX_SIZE - 1))
BUSYBOX_END_ALIGNED=$((($BUSYBOX_END + $ALIGN - 1) / $ALIGN * $ALIGN - 1))

ROOT_START=$(($BUSYBOX_END_ALIGNED + 1))
ROOT_END=$(($ROOT_START + $ROOT_SIZE + $ROOT_MARGIN - 1))
ROOT_END_ALIGNED=$((($ROOT_END + $ALIGN - 1) / $ALIGN * $ALIGN - 1))

# Total image size is the aligned end of the root partition plus padding
IMG_SIZE=$(($ROOT_END_ALIGNED + $ALIGN))

# Debugging: Print sizes and positions
echo "BOOT: $BOOT_START - $BOOT_END_ALIGNED (~$(($BOOT_SIZE / 1024 / 1024))MB)"
echo "UPDATE: $UPDATE_START - $UPDATE_END_ALIGNED (~$(($UPDATE_SIZE / 1024 / 1024))MB)"
echo "BUSYBOX: $BUSYBOX_START - $BUSYBOX_END_ALIGNED (~$(($BUSYBOX_SIZE / 1024 / 1024))MB)"
echo "ROOT: $ROOT_START - $ROOT_END_ALIGNED (~$((($ROOT_SIZE + $ROOT_MARGIN) / 1024 / 1024))MB)"
echo "IMG_SIZE: $IMG_SIZE bytes (~$(($IMG_SIZE / 1024 / 1024))MB)"

# Create the image file
truncate -s "${IMG_SIZE}" "${IMG_FILE}"

# Create partition table
parted --script "${IMG_FILE}" mklabel msdos
parted --script "${IMG_FILE}" unit B mkpart primary fat32 "${BOOT_START}" "${BOOT_END_ALIGNED}"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${UPDATE_START}" "${UPDATE_END_ALIGNED}"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${BUSYBOX_START}" "${BUSYBOX_END_ALIGNED}"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${ROOT_START}" "${ROOT_END_ALIGNED}"
parted --script "${IMG_FILE}" set 1 boot on

# Debugging: Print partition table
parted --script "${IMG_FILE}" unit B print

echo "Creating loop device..."
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

ensure_loopdev_partitions "$LOOP_DEV"
BOOT_DEV="${LOOP_DEV}p1"
UPDATE_DEV="${LOOP_DEV}p2"
BUSYBOX_DEV="${LOOP_DEV}p3"
ROOT_DEV="${LOOP_DEV}p4"

ROOT_FEATURES="^huge_file"
for FEATURE in 64bit; do
    if grep -q "$FEATURE" /etc/mke2fs.conf; then
        ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
    fi
done

mkdosfs -n bootfs -F 32 -s 4 -v "$BOOT_DEV" > /dev/null
mkfs.ext4 -L update -O "$ROOT_FEATURES" "$UPDATE_DEV" > /dev/null
mkfs.ext4 -L busybox -O "$ROOT_FEATURES" "$BUSYBOX_DEV" > /dev/null
mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$ROOT_DEV" > /dev/null

mount -v "$ROOT_DEV" "${ROOTFS_DIR}" -t ext4
mkdir -p "${ROOTFS_DIR}/boot/firmware"
mount -v "$BOOT_DEV" "${ROOTFS_DIR}/boot/firmware" -t vfat

rsync -aHAXx --exclude /var/cache/apt/archives --exclude /boot/firmware "${EXPORT_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
rsync -rtx "${EXPORT_ROOTFS_DIR}/boot/firmware/" "${ROOTFS_DIR}/boot/firmware/"