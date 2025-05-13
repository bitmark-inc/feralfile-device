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

# Make sure theme files are in the correct location
mkdir -p /boot/plymouth/themes/feralfile-splash
cp -f /usr/share/plymouth/themes/feralfile-splash/* /boot/plymouth/themes/feralfile-splash/

# Regenerate initramfs with Plymouth support
mkinitcpio -P