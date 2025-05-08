#!/bin/bash
set -euo pipefail

cleanup() {
  echo
  echo "⚠️  Cleaning up..."
  if mountpoint -q /mnt; then
    echo "Unmounting /mnt..."
    fuser -km /mnt || true
    umount -R /mnt || true
  fi
  if mountpoint -q /live-efi; then
    echo "Unmounting /live-efi..."
    umount -l /live-efi || true
  fi
  echo "You may now reboot and remove the USB stick."
}
trap cleanup EXIT

echo "=== Feral File Arch Installer ==="
echo

# ─── List available target disks ───────────────────────────────────────
echo "Available disks:"
echo

PS3="Select the target disk to install to: "
options=()

while IFS= read -r line; do
    dev=$(awk '{print $1}' <<< "$line")
    size=$(awk '{print $2}' <<< "$line")
    model=$(lsblk -no MODEL "/dev/$dev")
    options+=("/dev/$dev ($size) $model")
done < <(lsblk -dno NAME,SIZE,TYPE | awk '$3 == "disk"')

select opt in "${options[@]}"; do
    if [[ -n "$opt" ]]; then
        TARGET_DISK=$(awk '{print $1}' <<< "$opt")
        echo
        echo "You selected: $TARGET_DISK"
        read -rp "⚠️  ALL DATA WILL BE ERASED. Proceed? [y/N]: " confirm
        [[ "$confirm" != [yY] ]] && echo "Aborted." && exit 1
        break
    fi
done

# ─── Partition and format ──────────────────────────────────────────────
echo
echo "Partitioning $TARGET_DISK..."

wipefs -a "$TARGET_DISK"
parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

sleep 1  # Wait for kernel to re-read partition table

if [[ "$TARGET_DISK" =~ [0-9]$ ]]; then
  PART_SUFFIX="p"
else
  PART_SUFFIX=""
fi

BOOT_PART="${TARGET_DISK}${PART_SUFFIX}1"
ROOT_PART="${TARGET_DISK}${PART_SUFFIX}2"

echo "Formatting EFI boot partition: $BOOT_PART"
mkfs.fat -F32 "$BOOT_PART"

echo "Formatting root partition: $ROOT_PART"
mkfs.ext4 -F "$ROOT_PART"

# ─── Mount target system ───────────────────────────────────────────────
echo
echo "Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# ─── Copy root filesystem ──────────────────────────────────────────────
echo
echo "Copying root filesystem..."
rsync -aAX --info=progress2 --exclude={"/dev/*","/proc/*","/root/*","/sys/*","/tmp/*","/run/*","/mnt/*","/live-efi/*","/media/*","/lost+found"} / /mnt
rm -rf /mnt/etc/systemd/system/getty@tty1.service.d/
# ─── Setup bootloader ──────────────────────────────────────────────────
echo
echo "Copying systemd-boot..."

for i in {1..5}; do
  if [ -e /dev/disk/by-label/ARCHISO_EFI ]; then
    break
  fi
  echo "Waiting for ARCHISO_EFI device..."
  sleep 1
done

mkdir -p /live-efi
mount /dev/disk/by-label/ARCHISO_EFI /live-efi
rsync -a /live-efi/arch/boot/x86_64/vmlinuz-linux /mnt/boot/vmlinuz-linux
rsync -a /live-efi/arch/boot/x86_64/initramfs-linux.img /mnt/boot/initramfs-linux.img
rsync -a /live-efi/arch/boot/intel-ucode.img /mnt/boot/intel-ucode.img
rsync -a /live-efi/loader /mnt/boot
rsync -a /live-efi/EFI /mnt/boot
umount /live-efi

PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PART")

cat > /mnt/boot/loader/loader.conf <<EOF
default arch
timeout 0
editor no
EOF

cat > /mnt/boot/loader/entries/arch.conf <<EOF
title   Feral File X1 Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
initrd  /intel-ucode.img
options root=PARTUUID=$PARTUUID rw
EOF

mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

arch-chroot /mnt /bin/bash <<EOF
echo "Overwriting mkinitcpio.conf HOOKS..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev modconf autodetect block filesystems)/' /etc/mkinitcpio.conf

echo "Generating initramfs..."
mkinitcpio -P

echo "Installing systemd-boot to disk..."
bootctl install
EOF

# ─── Post-install cleanup and prompt ───────────────────────────────────
echo
echo "Done! Arch Linux has been installed to $TARGET_DISK"
