#!/bin/bash

mkdir -p /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-start.service /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-read-write.service /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-quit.service /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-quit-wait.service /etc/systemd/system/

# Register the theme with Plymouth
if command -v plymouth-set-default-theme &> /dev/null; then
  plymouth-set-default-theme -R feralfile-splash
fi

# Create boot directory if it doesn't exist
mkdir -p /boot/plymouth/themes/feralfile-splash

# Copy theme files to the boot location
cp -f /usr/share/plymouth/themes/feralfile-splash/* /boot/plymouth/themes/feralfile-splash/

# Make sure theme is set in config file
if [ -f /etc/plymouth/plymouthd.conf ]; then
  sed -i 's/^Theme=.*/Theme=feralfile-splash/' /etc/plymouth/plymouthd.conf
else
  mkdir -p /etc/plymouth
  echo "[Daemon]" > /etc/plymouth/plymouthd.conf
  echo "Theme=feralfile-splash" >> /etc/plymouth/plymouthd.conf
  echo "ShowDelay=0" >> /etc/plymouth/plymouthd.conf
  echo "DeviceTimeout=8" >> /etc/plymouth/plymouthd.conf
fi

# Regenerate initramfs with Plymouth support
mkinitcpio -P