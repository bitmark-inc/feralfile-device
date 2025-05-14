#!/bin/bash

# Create log directory
LOG_DIR="/var/log/boot-diagnostics"
mkdir -p $LOG_DIR

# Log system information
{
  echo "=== Boot Diagnostics $(date) ==="
  echo "=== Kernel Information ==="
  uname -a
  
  echo "=== Graphics Hardware ==="
  lspci | grep -E 'VGA|3D|Display'
  
  echo "=== Loaded DRM Modules ==="
  lsmod | grep -E 'drm|i915|amdgpu|radeon|nouveau'
  
  echo "=== Plymouth Status ==="
  if command -v plymouth --ping &> /dev/null; then
    plymouth --ping && echo "Plymouth daemon is running" || echo "Plymouth daemon is NOT running"
  else
    echo "Plymouth command not found"
  fi
  
  echo "=== DRM Renderer Status ==="
  if [ -f /usr/lib/plymouth/renderers/drm.so ]; then
    echo "DRM renderer module exists"
  else
    echo "DRM renderer module NOT found"
  fi
  
  echo "=== Display Configuration ==="
  if command -v modetest &> /dev/null; then
    modetest -p
  fi
  
  echo "=== Xorg/Wayland Status ==="
  ps aux | grep -E 'X|wayland|weston|sway|cage'
  
  echo "=== systemd Service Status ==="
  systemctl status plymouth-start.service
  systemctl status plymouth-quit.service
  systemctl status seatd.service
  systemctl status chromium-kiosk.service
  
  echo "=== Journal Logs for Plymouth ==="
  journalctl -b -u plymouth-start.service
  journalctl -b -u plymouth-quit.service
  
  echo "=== Journal Logs for Graphics/DRM ==="
  journalctl -b | grep -E 'drm|i915|gpu|graphics'
  
  echo "=== End of Boot Diagnostics ==="
} > "$LOG_DIR/boot-$(date +%Y%m%d-%H%M%S).log" 2>&1 