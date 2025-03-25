#!/bin/bash

set -e  # Exit on error

target_version="23.2.1-1~bpo12+rpt3"

packages=(
  libgbm1_23.2.1-1~bpo12+rpt3_arm64.deb
  libglapi-mesa_23.2.1-1~bpo12+rpt3_arm64.deb
  libgl1-mesa-dri_23.2.1-1~bpo12+rpt3_arm64.deb
  libegl-mesa0_23.2.1-1~bpo12+rpt3_arm64.deb
  libglx-mesa0_23.2.1-1~bpo12+rpt3_arm64.deb
)

packages_to_check=(
  libgbm1
  libglapi-mesa
  libgl1-mesa-dri
  libegl-mesa0
  libglx-mesa0
)

base_url="https://archive.raspberrypi.com/debian/pool/main/m/mesa"

# Check current installed versions
should_update=false
echo "Checking installed versions..."
for pkg in "${packages_to_check[@]}"; do
  current_version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo "none")

  if [ "$current_version" = "none" ]; then
    echo "🔄 $pkg not installed. Will install version $target_version."
    should_update=true
  else
    if [ "$current_version" = "$target_version" ]; then
      echo "✅ $pkg is correct version ($current_version)."
    else
      echo "🔄 $pkg has wrong version ($current_version != $target_version). Will reinstall exact version."
      should_update=true
    fi
  fi
done

if [ "$should_update" != true ]; then
  echo "All packages are up to date. No update needed."
  exit 0
fi

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

dpkg -r mesa-libgallium || echo "mesa-libgallium not installed or already removed"

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

echo "✅ Done. Mesa packages installed, held, and temporary files removed."