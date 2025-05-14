#!/bin/bash

# Create log directory with proper permissions
LOG_DIR="/var/log/boot-diagnostics"
mkdir -p $LOG_DIR
chmod 755 $LOG_DIR

# Log file with timestamp
LOG_FILE="$LOG_DIR/boot-$(date +%Y%m%d-%H%M%S).log"

# Ensure we can write to the log file
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Function to log with timestamp
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Start logging
log "=== Boot Diagnostics Started ==="

# System information
log "Kernel: $(uname -a)"

# Graphics hardware
log "=== Graphics Hardware ==="
lspci | grep -E 'VGA|3D|Display' >> "$LOG_FILE" 2>&1

# DRM modules
log "=== Loaded DRM Modules ==="
lsmod | grep -E 'drm|i915|amdgpu|radeon|nouveau' >> "$LOG_FILE" 2>&1

# Plymouth status
log "=== Plymouth Status ==="
if command -v plymouth &> /dev/null; then
  plymouth --ping && log "Plymouth daemon is running" || log "Plymouth daemon is NOT running"
else
  log "Plymouth command not found"
fi

# Check DRM renderer
log "=== DRM Renderer Status ==="
if [ -f /usr/lib/plymouth/renderers/drm.so ]; then
  log "DRM renderer module exists"
else
  log "DRM renderer module NOT found"
fi

# Display configuration
log "=== Display Configuration ==="
if command -v modetest &> /dev/null; then
  modetest -p >> "$LOG_FILE" 2>&1
fi

# Running display processes
log "=== Display Processes ==="
ps aux | grep -E 'X|wayland|weston|sway|cage' >> "$LOG_FILE" 2>&1

# Service status
log "=== Plymouth Service Status ==="
systemctl status plymouth-start.service >> "$LOG_FILE" 2>&1
systemctl status plymouth-quit.service >> "$LOG_FILE" 2>&1

# Journal logs for Plymouth
log "=== Journal Logs for Plymouth ==="
journalctl -b -u plymouth-start.service >> "$LOG_FILE" 2>&1
journalctl -b -u plymouth-quit.service >> "$LOG_FILE" 2>&1

# Graphics/DRM logs
log "=== Journal Logs for Graphics/DRM ==="
journalctl -b | grep -E 'drm|i915|gpu|graphics' >> "$LOG_FILE" 2>&1

# End logging
log "=== Boot Diagnostics Completed ==="

# Create a symlink to the latest log
ln -sf "$LOG_FILE" "$LOG_DIR/latest.log" 