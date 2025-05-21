#!/bin/bash
set -euo pipefail

CONFIG_FILE="/home/feralfile/x1-config.json"
IMG_MOUNT="/mnt/ota-img"
SFS_MOUNT="/mnt/ota-sfs"
TMP_DIR="/tmp/ota"
ZIP_FILE="$TMP_DIR/image.zip"
ISO_FILE="$TMP_DIR/image.img"

cleanup() {
  umount "$SFS_MOUNT" 2>/dev/null || true
  umount "$IMG_MOUNT" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "=== OTA Update: Version-aware SquashFS Sync ==="

# --- Step 1: Load local config --------------------------------------------------
echo "📖 Loading config from $CONFIG_FILE"
branch=$(jq -r '.branch' "$CONFIG_FILE")
current_version=$(jq -r '.version' "$CONFIG_FILE")
auth_user=$(jq -r '.distribution_acc' "$CONFIG_FILE")
auth_pass=$(jq -r '.distribution_pass' "$CONFIG_FILE")

# --- Step 2: Query latest version from server -----------------------------------
API_URL="https://feralfile-device-distribution.bitmark-development.workers.dev/api/latest/$branch"
echo "🌐 Fetching latest version from: $API_URL"
response=$(curl -su "$auth_user:$auth_pass" -f "$API_URL")

latest_version=$(jq -r '.latest_version' <<< "$response")
image_url=$(jq -r '.image_url' <<< "$response")

echo "🆚 Current: $current_version  →  Remote: $latest_version"
if [[ "$latest_version" == "$current_version" ]]; then
  echo "✅ System is already up to date. Exiting."
  exit 0
fi

# --- Step 3: Download and extract new image -------------------------------------
echo "📦 New version found: $latest_version. Downloading image..."
mkdir -p "$TMP_DIR"
curl -u "$auth_user:$auth_pass" -f -L "https://feralfile-device-distribution.bitmark-development.workers.dev$image_url" -o "$ZIP_FILE"
unzip -o "$ZIP_FILE" -d "$TMP_DIR"
ISO_FILE=$(find "$TMP_DIR" -name '*.iso' | head -n1)

mkdir -p "$IMG_MOUNT"
mount -o loop "$ISO_FILE" "$IMG_MOUNT"

# --- Step 6: Mount airootfs.sfs -------------------------------------------------
SFS_PATH="$IMG_MOUNT/arch/x86_64/airootfs.sfs"
if [[ ! -f "$SFS_PATH" ]]; then
  echo "❌ airootfs.sfs not found in image."
  exit 1
fi

echo "📦 Mounting SquashFS: $SFS_PATH"
mkdir -p "$SFS_MOUNT"
mount -t squashfs -o loop "$SFS_PATH" "$SFS_MOUNT"

# --- Step 7: Rsync selective update from SquashFS -------------------------------
echo "🔁 Syncing filesystem (excluding persistent and sensitive paths)..."
rsync -aAX --delete --info=progress2 \
  --exclude={"/dev/*","/proc/*","/boot/*","/root/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/live-efi/*","/lost+found","/etc/machine-id","/etc/ssh/ssh_host_*","/etc/NetworkManager/system-connections/*","/var/lib/systemd/random-seed","/home/feralfile/.config/*","/home/feralfile/.logs/*","/home/feralfile/.state/*"} \
  "$SFS_MOUNT"/ /

echo -n > /etc/machine-id
rm -f /var/lib/systemd/random-seed

# Set up pacman
echo "Setting up pacman..."
pacman-key --init
pacman-key --populate archlinux
pacman -Syy

# --- Step 8: Clean up ------------------------------------------------------------
echo "🧹 Cleaning up..."
umount "$SFS_MOUNT"
umount "$IMG_MOUNT"
rm -rf "$TMP_DIR"

echo "✅ OTA update complete. Rebooting..."
reboot