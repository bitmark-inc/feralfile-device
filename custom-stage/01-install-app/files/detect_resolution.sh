#!/bin/bash

# Log file for debugging
LOG_FILE="/var/log/resolution_detect.log"

# Function to log messages
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
    echo "$1"
}

log_message "Starting resolution detection script"

# Get the connected display name
DISPLAY_NAME=$(xrandr | grep " connected" | awk '{print $1}')
if [[ -z "$DISPLAY_NAME" ]]; then
    log_message "No display detected. Exiting."
    exit 1
fi

log_message "Detected display: $DISPLAY_NAME"

# Get current resolution
CURRENT_RESOLUTION=$(xrandr | grep "$DISPLAY_NAME connected" | grep -oP '\d+x\d+' | head -1)
if [[ -z "$CURRENT_RESOLUTION" ]]; then
    log_message "Could not detect current resolution. Using fallback."
    CURRENT_RESOLUTION="1920x1080"
fi

log_message "Current resolution: $CURRENT_RESOLUTION"

# Get all supported resolutions for this display
SUPPORTED_RESOLUTIONS=$(xrandr | grep -A 20 "$DISPLAY_NAME connected" | grep -oP '\d+x\d+' | sort -u)
log_message "Supported resolutions: $SUPPORTED_RESOLUTIONS"

# Check if this is likely a Samsung Frame TV (can be expanded with more detection logic)
IS_SAMSUNG_FRAME=false
if xrandr | grep -i "samsung" > /dev/null; then
    log_message "Samsung display detected, checking if it's a Frame TV"
    # Additional checks could be added here
    # For now, we'll assume any Samsung display might be a Frame
    IS_SAMSUNG_FRAME=true
fi

# Split current resolution into width and height
WIDTH=$(echo $CURRENT_RESOLUTION | cut -d'x' -f1)
HEIGHT=$(echo $CURRENT_RESOLUTION | cut -d'x' -f2)

# Determine if we're in portrait mode (height > width)
if [[ $HEIGHT -gt $WIDTH ]]; then
    log_message "Display appears to be in portrait orientation (H:$HEIGHT > W:$WIDTH)"
    
    if [[ "$IS_SAMSUNG_FRAME" == "true" ]]; then
        log_message "Samsung Frame TV detected in portrait mode, applying special handling"
        
        # For Samsung Frame TVs in portrait, we need to use a specific transformation
        # The physical display is rotated, but we need to tell the system how to handle it
        
        # First, try to find the best resolution for portrait mode
        # Samsung Frame TVs often work best with specific resolutions in portrait
        BEST_RESOLUTION=""
        
        # Check for common Samsung Frame resolutions in order of preference
        for RES in "3840x2160" "1920x1080" "1280x720"; do
            if echo "$SUPPORTED_RESOLUTIONS" | grep -q "$RES"; then
                BEST_RESOLUTION=$RES
                break
            fi
        done
        
        if [[ -z "$BEST_RESOLUTION" ]]; then
            log_message "No preferred resolution found, using current: $CURRENT_RESOLUTION"
            BEST_RESOLUTION=$CURRENT_RESOLUTION
        else
            log_message "Selected optimal resolution for Samsung Frame: $BEST_RESOLUTION"
        fi
        
        # Extract width and height from the best resolution
        BEST_WIDTH=$(echo $BEST_RESOLUTION | cut -d'x' -f1)
        BEST_HEIGHT=$(echo $BEST_RESOLUTION | cut -d'x' -f2)
        
        # Apply the transformation - for Samsung Frame in portrait, right rotation (90°) works best
        log_message "Applying right rotation (90°) for Samsung Frame in portrait mode"
        xrandr --output $DISPLAY_NAME --mode $BEST_RESOLUTION --rotate right
        
        # Success message
        log_message "Samsung Frame TV configured for portrait mode at $BEST_RESOLUTION with right rotation"
    else
        # For standard displays in portrait mode
        log_message "Standard display in portrait mode, applying normal portrait rotation"
        xrandr --output $DISPLAY_NAME --rotate right
    fi
else
    # We're in landscape mode
    log_message "Display is in landscape orientation (W:$WIDTH >= H:$HEIGHT)"
    
    # For landscape, we typically use normal rotation
    xrandr --output $DISPLAY_NAME --rotate normal
    log_message "Applied normal rotation for landscape mode"
fi

# Final check to verify the changes were applied
FINAL_ORIENTATION=$(xrandr | grep "$DISPLAY_NAME" | grep -o "normal\|left\|right\|inverted")
FINAL_RESOLUTION=$(xrandr | grep "$DISPLAY_NAME connected" | grep -oP '\d+x\d+' | head -1)

log_message "Configuration complete. Display: $DISPLAY_NAME, Resolution: $FINAL_RESOLUTION, Orientation: $FINAL_ORIENTATION"
exit 0
