#!/bin/bash

# Input device for power button
PWR_BUTTON_DEVICE="/dev/input/event0"
DISABLE_FLAG="/tmp/disable_power_button"

# Function to log debug information
log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a /var/log/feralfile-power-button.log
}

# Function to check if power button is disabled
is_power_button_disabled() {
    [ -f "$DISABLE_FLAG" ]
}

# Function to enable power button
enable_power_button() {
    if [ -f "$DISABLE_FLAG" ]; then
        sudo rm "$DISABLE_FLAG"
        log_debug "Power button enabled"
    fi
}

# Function to disable power button
disable_power_button() {
    sudo touch "$DISABLE_FLAG"
    log_debug "Power button disabled"
}

# Function to perform power off
perform_power_off() {
    log_debug "Rebooting system..."
    sudo reboot
}

# Function to perform soft reset
perform_soft_reset() {
    log_debug "Performing soft reset..."
    sudo /opt/feralfile/scripts/soft-reset.sh
}

# Function to perform factory reset
perform_factory_reset() {
    log_debug "Performing factory reset..."
    sudo /opt/feralfile/scripts/factory-reset.sh
}

# Function to monitor power button
monitor_power_button() {
    log_debug "Starting power button monitor"
    
    while true; do
        # Check if power button is disabled
        if is_power_button_disabled; then
            sleep 1
            continue
        fi
        
        # Wait for button press
        while true; do
            # Read input event
            if [ -e "$PWR_BUTTON_DEVICE" ]; then
                # Use evtest to monitor button press
                if evtest "$PWR_BUTTON_DEVICE" | grep -q "value 1"; then
                    log_debug "Button pressed"
                    break
                fi
            else
                log_debug "Power button device not found"
                sleep 1
                continue
            fi
            sleep 0.1
        done
        
        # Button is pressed, start counting
        start_time=$(date +%s)
        button_pressed=true
        
        while [ "$button_pressed" = true ]; do
            current_time=$(date +%s)
            duration=$((current_time - start_time))
            
            # Check if button is still pressed
            if ! evtest "$PWR_BUTTON_DEVICE" | grep -q "value 1"; then
                button_pressed=false
                log_debug "Button released after $duration seconds"
                # If button was released before 5 seconds, perform power off
                if [ $duration -lt 5 ]; then
                    perform_power_off
                fi
                break
            fi
            
            if [ $duration -ge 10 ]; then
                # Button held for 10+ seconds - factory reset
                log_debug "Button held for $duration seconds - performing factory reset"
                perform_factory_reset
                break
            elif [ $duration -ge 5 ]; then
                # Button held for 5 seconds - soft reset
                log_debug "Button held for $duration seconds - performing soft reset"
                perform_soft_reset
                break
            fi
            
            sleep 0.1
        done
        
        sleep 0.1
    done
}

# Start monitoring
monitor_power_button 