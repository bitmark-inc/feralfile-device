#!/bin/bash

# FeralFile Time Synchronization Service
# This script handles:
# 1. NTP synchronization when online
# 2. Setting timezone and time manually when offline

# Configuration
NTP_CONF="/etc/systemd/timesyncd.conf"
TIMEZONE_FILE="/etc/timezone"
LOCALTIME_LINK="/etc/localtime"
ZONEINFO_PATH="/usr/share/zoneinfo"
STATUS_FILE="/var/lib/feral-timesyncd/status"

# Create status directory if it doesn't exist
mkdir -p "$(dirname "$STATUS_FILE")"
touch "$STATUS_FILE"

# Ensure systemd-timesyncd is enabled
systemctl enable systemd-timesyncd.service

# Function to check network connectivity
check_network() {
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1
    return $?
}

# Function to check if NTP is synchronized
is_ntp_synced() {
    timedatectl show --property=NTPSynchronized | grep -q "yes"
    return $?
}

# Function to synchronize time with NTP
sync_ntp() {
    echo "Attempting NTP synchronization..."
    systemctl restart systemd-timesyncd.service
    
    # Wait for NTP sync for up to 30 seconds
    for i in {1..30}; do
        if is_ntp_synced; then
            echo "NTP time synchronized successfully"
            echo "ntp_synced=true" > "$STATUS_FILE"
            return 0
        fi
        sleep 1
    done
    
    echo "Failed to synchronize time with NTP"
    echo "ntp_synced=false" > "$STATUS_FILE"
    return 1
}

# Function to set timezone and time
set_time() {
    # First parameter is timezone, second is time
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: set-time TIMEZONE 'YYYY-MM-DD HH:MM:SS'"
        return 1
    fi
    
    timezone="$1"
    time_str="$2"
    
    # Verify timezone exists
    if [ ! -f "$ZONEINFO_PATH/$timezone" ]; then
        echo "Invalid timezone: $timezone"
        return 1
    fi
    
    # Set timezone
    echo "$timezone" > "$TIMEZONE_FILE"
    ln -sf "$ZONEINFO_PATH/$timezone" "$LOCALTIME_LINK"
    echo "Timezone set to $timezone"
    
    # Set system time
    if date -s "$time_str" >/dev/null 2>&1; then
        # Update hardware clock from system time
        hwclock --systohc
        echo "System time set to $time_str"
        echo "manual_time_set=true" > "$STATUS_FILE"
        return 0
    else
        echo "Failed to set system time. Invalid format. Use: YYYY-MM-DD HH:MM:SS"
        return 1
    fi
}

# Run NTP sync if network is available
if check_network; then
    echo "Network is available. Attempting NTP sync."
    sync_ntp
else
    echo "Network is unavailable. Skipping NTP sync."
    echo "ntp_synced=false" > "$STATUS_FILE"
fi

# Handle service commands
case "$1" in
    "set-time")
        set_time "$2" "$3"
        exit $?
        ;;
    *)
        # Default behavior - already ran the NTP sync check above
        exit 0
        ;;
esac