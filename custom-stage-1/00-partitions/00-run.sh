#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

# All partition sizes and starts will be aligned to this size (4MB in bytes)
ALIGN="$((4 * 1024 * 1024))"

# Define fixed partition sizes in bytes
BOOT_SIZE="$((256 * 1024 * 1024))"    # 256MB
UPDATE_SIZE="$((2048 * 1024 * 1024))"  # 2048MB
BUSYBOX_SIZE="$((1536 * 1024 * 1024))" # 1536MB (1.5GB as per your spec)
MIN_ROOT_SIZE="$((5 * 1024 * 1024 * 1024))"  # 5GB minimum for root

# Calculate ROOT_SIZE with fallback
ROOT_SIZE=$(du -x --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot/firmware --block-size=1 2>/dev/null | cut -f 1)
if [ -z "$ROOT_SIZE" ] || [ "$ROOT_SIZE" -eq 0 ]; then
    echo "Warning: Unable to calculate ROOT_SIZE from '${EXPORT_ROOTFS_DIR}'. Using minimum size of 5GB."
    ROOT_SIZE="$MIN_ROOT_SIZE"
elif [ "$ROOT_SIZE" -lt "$MIN_ROOT_SIZE" ]; then
    echo "Warning: ROOT_SIZE ($ROOT_SIZE bytes) is less than 5GB. Setting to minimum size."
    ROOT_SIZE="$MIN_ROOT_SIZE"
fi

# Calculate ROOT_MARGIN (20% of ROOT_SIZE + 200MB)
ROOT_MARGIN=$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)
if [ -z "$ROOT_MARGIN" ]; then
    echo "Error: Failed to calculate ROOT_MARGIN."
    exit 1
fi

# Calculate ROOT_PART_SIZE
ROOT_PART_SIZE=$(($ROOT_SIZE + $ROOT_MARGIN))
if [ -z "$ROOT_PART_SIZE" ] || [ "$ROOT_PART_SIZE" -le 0 ]; then
    echo "Error: ROOT_PART_SIZE is invalid or zero."
    exit 1
fi

# Debug output
echo "ROOT_SIZE: $ROOT_SIZE bytes (~$(($ROOT_SIZE / 1024 / 1024))MB)"
echo "ROOT_MARGIN: $ROOT_MARGIN bytes (~$(($ROOT_MARGIN / 1024 / 1024))MB)"
echo "ROOT_PART_SIZE: $ROOT_PART_SIZE bytes (~$(($ROOT_PART_SIZE / 1024 / 1024))MB)"

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
ROOT_END=$(($ROOT_START + $ROOT_PART_SIZE - 1))
ROOT_END_ALIGNED=$((($ROOT_END + $ALIGN - 1) / $ALIGN * $ALIGN - 1))

# Total image size
IMG_SIZE=$(($ROOT_END_ALIGNED + $ALIGN))

# Debug output for partitions
echo "BOOT: $BOOT_START - $BOOT_END_ALIGNED (~$(($BOOT_SIZE / 1024 / 1024))MB)"
echo "UPDATE: $UPDATE_START - $UPDATE_END_ALIGNED (~$(($UPDATE_SIZE / 1024 / 1024))MB)"
echo "BUSYBOX: $BUSYBOX_START - $BUSYBOX_END_ALIGNED (~$(($BUSYBOX_SIZE / 1024 / 1024))MB)"
echo "ROOT: $ROOT_START - $ROOT_END_ALIGNED (~$(($ROOT_PART_SIZE / 1024 / 1024))MB)"
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

# Rest of your script (loop device setup, filesystem creation, etc.)
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