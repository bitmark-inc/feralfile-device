#!/bin/bash

set -e  # Exit on error

# List of packages to download and install
# DO NOT CHANGE THE ORDER HERE
packages=(
  libgbm1_23.2.1-1~bpo12+rpt3_arm64.deb
  libglapi-mesa_23.2.1-1~bpo12+rpt3_arm64.deb
  libgl1-mesa-dri_23.2.1-1~bpo12+rpt3_arm64.deb
  libegl-mesa0_23.2.1-1~bpo12+rpt3_arm64.deb
  libglx-mesa0_23.2.1-1~bpo12+rpt3_arm64.deb
)

base_url="https://archive.raspberrypi.com/debian/pool/main/m/mesa"

echo "Downloading .deb files..."
for pkg in "${packages[@]}"; do
  wget -nc "$base_url/$pkg"
done

apt-get install libdrm-nouveau2

echo "Installing packages..."
for pkg in "${packages[@]}"; do
    dpkg -i ./"$pkg"
done

echo "Holding packages to prevent upgrades..."
apt-mark hold libegl-mesa0 libgbm1 libgl1-mesa-dri libglapi-mesa libglx-mesa0

dpkg -r mesa-libgallium

echo "Verifying held packages..."
for pkg in libegl-mesa0 libgbm1 libgl1-mesa-dri libglapi-mesa libglx-mesa0; do
  status=$(apt-mark showhold | grep -w "$pkg" || true)
  if [ -n "$status" ]; then
    echo "✅ Package '$pkg' is held."
  else
    echo "❌ Package '$pkg' is NOT held!"
    exit 1
  fi
done

echo "Cleaning up .deb files..."
for pkg in "${packages[@]}"; do
  rm -f ./"$pkg"
done

echo "Done. Mesa packages installed, held, and temporary files removed."