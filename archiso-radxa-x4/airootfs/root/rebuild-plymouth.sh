#!/bin/bash

# Rebuild Plymouth theme and initramfs

# Make sure the theme is properly set
plymouth-set-default-theme feralfile-splash

# Create a theme-specific modprobe.d config for Plymouth
cat > /etc/modprobe.d/plymouth.conf << EOF
# Plymouth needs DRM output
options i915 modeset=1
EOF

# Regenerate the initramfs
mkinitcpio -P

# Log completion
echo "Plymouth rebuild completed on $(date)" > /var/log/plymouth-rebuild.log 