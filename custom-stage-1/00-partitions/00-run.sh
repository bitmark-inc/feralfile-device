#!/bin/bash -e

# Calculate partition sizes in MB
BOOT_SIZE=256
UPDATE_SIZE=2048
BUSYBOX_SIZE=512

# Create a new partition table
cat > "${STAGE_WORK_DIR}/partition.txt" << EOF
label: dos
unit: sectors

1 : start=2048, size=$(($BOOT_SIZE * 2048)), type=c, bootable
2 : size=$(($UPDATE_SIZE * 2048)), type=83
3 : size=$(($BUSYBOX_SIZE * 2048)), type=83
4 : type=83
EOF

# Override the default partitioning in pi-gen
if [ -f "${BASE_DIR}/export-image/prerun.sh" ]; then
    mv "${BASE_DIR}/export-image/prerun.sh" "${BASE_DIR}/export-image/prerun.sh.bak"
fi

# Create custom prerun.sh for image creation
cat > "${BASE_DIR}/export-image/prerun.sh" << 'EOF'
#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}${IMG_SUFFIX}.img"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

BOOT_SIZE=$(grep -E "^1 :" "${STAGE_WORK_DIR}/partition.txt" | awk '{print $5}')
UPDATE_SIZE=$(grep -E "^2 :" "${STAGE_WORK_DIR}/partition.txt" | awk '{print $3}')
BUSYBOX_SIZE=$(grep -E "^3 :" "${STAGE_WORK_DIR}/partition.txt" | awk '{print $3}')
ROOT_SIZE=$(du --apparent-size -s "${EXPORT_ROOTFS_DIR}" --exclude var/cache/apt/archives --exclude boot --block-size=1 | cut -f 1)

# Calculate total image size
IMG_SIZE=$((BOOT_SIZE + UPDATE_SIZE + BUSYBOX_SIZE + ROOT_SIZE + (400 * 1024 * 1024)))

fallocate -l "${IMG_SIZE}" "${IMG_FILE}"
parted -s "${IMG_FILE}" mklabel msdos
sfdisk --force "${IMG_FILE}" < "${STAGE_WORK_DIR}/partition.txt"

PARTED_OUT=$(parted -s "${IMG_FILE}" unit b print)
BOOT_OFFSET=$(echo "${PARTED_OUT}" | grep -E "^ 1" | awk '{print $2}')
BOOT_LENGTH=$(echo "${PARTED_OUT}" | grep -E "^ 1" | awk '{print $4}')
UPDATE_OFFSET=$(echo "${PARTED_OUT}" | grep -E "^ 2" | awk '{print $2}')
UPDATE_LENGTH=$(echo "${PARTED_OUT}" | grep -E "^ 2" | awk '{print $4}')
BUSYBOX_OFFSET=$(echo "${PARTED_OUT}" | grep -E "^ 3" | awk '{print $2}')
BUSYBOX_LENGTH=$(echo "${PARTED_OUT}" | grep -E "^ 3" | awk '{print $4}')
ROOT_OFFSET=$(echo "${PARTED_OUT}" | grep -E "^ 4" | awk '{print $2}')
ROOT_LENGTH=$(echo "${PARTED_OUT}" | grep -E "^ 4" | awk '{print $4}')

BOOT_DEV=$(losetup --show -f -o "${BOOT_OFFSET}" --sizelimit "${BOOT_LENGTH}" "${IMG_FILE}")
UPDATE_DEV=$(losetup --show -f -o "${UPDATE_OFFSET}" --sizelimit "${UPDATE_LENGTH}" "${IMG_FILE}")
BUSYBOX_DEV=$(losetup --show -f -o "${BUSYBOX_OFFSET}" --sizelimit "${BUSYBOX_LENGTH}" "${IMG_FILE}")
ROOT_DEV=$(losetup --show -f -o "${ROOT_OFFSET}" --sizelimit "${ROOT_LENGTH}" "${IMG_FILE}")

mkdosfs -n boot -F 32 -v "${BOOT_DEV}"
mkfs.ext4 -L update "${UPDATE_DEV}"
mkfs.ext4 -L busybox "${BUSYBOX_DEV}"
mkfs.ext4 -L rootfs "${ROOT_DEV}"

mkdir -p "${STAGE_WORK_DIR}/rootfs"
mkdir -p "${STAGE_WORK_DIR}/boot"

mount "${ROOT_DEV}" "${STAGE_WORK_DIR}/rootfs"
mount "${BOOT_DEV}" "${STAGE_WORK_DIR}/boot"

rsync -aHAXx --exclude var/cache/apt/archives "${EXPORT_ROOTFS_DIR}/" "${STAGE_WORK_DIR}/rootfs/"
rsync -rtx "${EXPORT_ROOTFS_DIR}/boot/" "${STAGE_WORK_DIR}/boot/"
EOF

chmod +x "${BASE_DIR}/export-image/prerun.sh" 