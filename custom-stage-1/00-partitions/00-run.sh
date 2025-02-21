#!/bin/bash -e

# Create export-image directory if it doesn't exist
mkdir -p "${BASE_DIR}/export-image"

# Calculate partition sizes in MB
BOOT_SIZE=256
UPDATE_SIZE=2048
BUSYBOX_SIZE=512

# Create custom prerun.sh for image creation
cat > "${BASE_DIR}/export-image/prerun.sh" << 'EOF'
#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

# All partition sizes and starts will be aligned to this size
ALIGN="$((4 * 1024 * 1024))"

# Calculate partition sizes in bytes
BOOT_SIZE="$((256 * 1024 * 1024))"
UPDATE_SIZE="$((2048 * 1024 * 1024))"
BUSYBOX_SIZE="$((512 * 1024 * 1024))"
ROOT_SIZE=$(du -x --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot/firmware --block-size=1 | cut -f 1)
ROOT_MARGIN="$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)"

# Calculate partition starts and sizes with proper alignment
BOOT_START=$((ALIGN))
BOOT_END=$((BOOT_START + BOOT_SIZE))
BOOT_SIZE_ALIGNED=$(((BOOT_END + ALIGN - 1) / ALIGN * ALIGN))

UPDATE_START=$((BOOT_START + BOOT_SIZE_ALIGNED))
UPDATE_END=$((UPDATE_START + UPDATE_SIZE))
UPDATE_SIZE_ALIGNED=$(((UPDATE_END + ALIGN - 1) / ALIGN * ALIGN))

BUSYBOX_START=$((UPDATE_START + UPDATE_SIZE_ALIGNED))
BUSYBOX_END=$((BUSYBOX_START + BUSYBOX_SIZE))
BUSYBOX_SIZE_ALIGNED=$(((BUSYBOX_END + ALIGN - 1) / ALIGN * ALIGN))

ROOT_START=$((BUSYBOX_START + BUSYBOX_SIZE_ALIGNED))
ROOT_END=$((ROOT_START + ROOT_SIZE + ROOT_MARGIN))
ROOT_SIZE_ALIGNED=$(((ROOT_END + ALIGN - 1) / ALIGN * ALIGN))

IMG_SIZE=$((ROOT_START + ROOT_SIZE_ALIGNED))

truncate -s "${IMG_SIZE}" "${IMG_FILE}"

parted --script "${IMG_FILE}" mklabel msdos
parted --script "${IMG_FILE}" unit B mkpart primary fat32 "${BOOT_START}" "$((BOOT_START + BOOT_SIZE_ALIGNED - 1))"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${UPDATE_START}" "$((UPDATE_START + UPDATE_SIZE_ALIGNED - 1))"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${BUSYBOX_START}" "$((BUSYBOX_START + BUSYBOX_SIZE_ALIGNED - 1))"
parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${ROOT_START}" "$((ROOT_START + ROOT_SIZE_ALIGNED - 1))"
parted --script "${IMG_FILE}" set 1 boot on

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
EOF

chmod +x "${BASE_DIR}/export-image/prerun.sh" 