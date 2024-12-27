#!/bin/bash
set -e

IMAGE="feralfile.img"           # Name of the base image file
MOUNT_DIR="/mnt/image"         # Temporary mount point for modifying the image

# Ensure the base image exists
if [[ ! -f $IMAGE ]]; then
    echo "Error: Base image '$IMAGE' not found. Please place it in the current directory."
    exit 1
fi

echo "Preparing to modify the image: $IMAGE"

# Create a loopback device for the image
echo "Mounting the image..."
LOOP_DEVICE=$(sudo losetup -Pf --show $IMAGE)
if [[ -z "$LOOP_DEVICE" ]]; then
    echo "Error: Failed to create loopback device for the image."
    exit 1
fi

# Mount the image's second partition
sudo mkdir -p $MOUNT_DIR
sudo mount "${LOOP_DEVICE}p2" $MOUNT_DIR

# Apply modifications
echo "Applying modifications to the image..."
sudo cp configs/wpa_supplicant.conf $MOUNT_DIR/etc/wpa_supplicant/
sudo cp configs/kiosk.desktop $MOUNT_DIR/home/pi/.config/autostart/
sudo cp scripts/dynamic_resize.sh $MOUNT_DIR/usr/local/bin/
sudo chmod +x $MOUNT_DIR/usr/local/bin/dynamic_resize.sh
sudo cp configs/99-display-hotplug.rules $MOUNT_DIR/etc/udev/rules.d/

# Clean up and unmount
echo "Unmounting and cleaning up..."
sudo umount $MOUNT_DIR
sudo rmdir $MOUNT_DIR
sudo losetup -d $LOOP_DEVICE

echo "Image modification complete. Your updated image is ready!"