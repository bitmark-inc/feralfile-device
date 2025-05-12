#!/bin/bash

mkdir -p /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-start.service /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-read-write.service /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-quit.service /etc/systemd/system/
ln -sf /usr/lib/systemd/system/plymouth-quit-wait.service /etc/systemd/system/

# Set the Plymouth theme
plymouth-set-default-theme -R feralfile-splash

# Regenerate initramfs with Plymouth support
mkinitcpio -P