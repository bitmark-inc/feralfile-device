#!/bin/bash
set -euo pipefail

output=$(sudo pacman -Sy --needed --noconfirm feral-connectd feral-setupd)

if ! echo "$output" | grep -q "there is nothing to do"; then
  echo "Detected installation or upgrade. Reloading systemd and restarting services..."
  sudo systemctl daemon-reload
  sudo systemctl restart feral-connectd.service
  sudo systemctl restart feral-setupd.service
else
  echo "Packages already up to date. No action needed."
fi