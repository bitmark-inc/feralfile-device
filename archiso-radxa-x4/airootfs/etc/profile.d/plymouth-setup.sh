#!/bin/bash

# Set the Plymouth theme
plymouth-set-default-theme feralfile-splash

# Regenerate initramfs with Plymouth support
mkinitcpio -P