#!/bin/bash

# Path to the power button GPIO
POWER_BUTTON_GPIO="/sys/class/gpio/gpio17/value"
LED_GPIO="/sys/class/gpio/gpio18/value"

# Function to blink LED
blink_led() {
    local count=$1
    for ((i=0; i<count; i++)); do
        echo 1 > $LED_GPIO
        sleep 0.5
        echo 0 > $LED_GPIO
        sleep 0.5
    done
}

# Function to perform soft reset
perform_soft_reset() {
    echo "Performing soft reset..."
    blink_led 1
    sudo /usr/local/bin/soft-reset.sh
}

# Function to perform factory reset
perform_factory_reset() {
    echo "Performing factory reset..."
    blink_led 2
    sudo /usr/local/bin/factory-reset.sh
}

# Main loop to monitor power button
while true; do
    # Read power button state
    button_state=$(cat $POWER_BUTTON_GPIO)
    
    if [ "$button_state" = "1" ]; then
        # Button is pressed, start counting
        start_time=$(date +%s)
        while [ "$(cat $POWER_BUTTON_GPIO)" = "1" ]; do
            current_time=$(date +%s)
            duration=$((current_time - start_time))
            
            if [ $duration -ge 10 ]; then
                # Button held for 10+ seconds - factory reset
                perform_factory_reset
                break
            elif [ $duration -ge 5 ]; then
                # Button held for 5 seconds - soft reset
                perform_soft_reset
                break
            fi
            
            sleep 0.1
        done
    fi
    
    sleep 0.1
done 