#!/bin/bash

# Set the Plymouth theme
plymouth-set-default-theme feralfile-splash

# Regenerate initramfs with Plymouth support
mkinitcpio -P

if [ -f /root/plymouth-setup.sh ]; then
  /root/plymouth-setup.sh
fi