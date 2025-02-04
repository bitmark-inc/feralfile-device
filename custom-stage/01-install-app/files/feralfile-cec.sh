#!/bin/bash

# Environment setup
export DISPLAY=:0
export XAUTHORITY=/home/feralfile/.Xauthority

# LED control functions
set_led_green() {
    echo 0 > /sys/class/leds/PWR/brightness
    echo 255 > /sys/class/leds/ACT/brightness
}

set_led_yellow() {
    echo 255 > /sys/class/leds/PWR/brightness
    echo 255 > /sys/class/leds/ACT/brightness
}

# Function to handle CEC power events
handle_cec_event() {
    while IFS= read -r line; do
        echo "$(date): CEC Event: $line" >> /var/log/feralfile-cec.log
        
        if [[ $line == *"STANDBY"* ]]; then
            echo "$(date): Handling standby event" >> /var/log/feralfile-cec.log
            # Set LED to green for standby
            set_led_green
            # Turn off display
            xset dpms force off
            # Suspend the system
            systemctl suspend
            # Stop FeralFile service
            systemctl stop feralfile-launcher.service
        elif [[ $line == *"WAKEUP"* ]] || [[ $line == *"IMAGE VIEW ON"* ]] || [[ $line == *"TEXT VIEW ON"* ]]; then
            echo "$(date): Handling wake event" >> /var/log/feralfile-cec.log
            # Set LED back to yellow for active state
            set_led_yellow
            # Turn on display
            xset dpms force on
            # Start FeralFile service
            systemctl start feralfile-launcher.service
            # Set as active source
            echo 'as' | cec-client -s -d 1
        fi
    done
}

# Set initial LED state to yellow (active)
set_led_yellow

# Start CEC client in monitoring mode
echo "$(date): Starting CEC monitoring" >> /var/log/feralfile-cec.log
cec-client -d 8 -t p -o "FeralFile" | handle_cec_event