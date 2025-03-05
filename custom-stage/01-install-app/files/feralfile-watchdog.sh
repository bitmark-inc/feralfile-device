#!/bin/bash

# Redirect all output to a log file
exec >> /var/log/feralfile-watchdog.log 2>&1

# Log function to add timestamps
log() {
    echo "$(date): $1"
}

while true; do
    # Wait until the WebSocket server is up
    while ! nc -z localhost 8080; do
        log "WebSocket server not up yet, waiting 10 seconds..."
        sleep 10
    done
    
    log "WebSocket server is up, connecting..."
    
    # Connect and monitor heartbeat
    websocat ws://localhost:8080/watchdog | while true; do
        if read -t 30 -r message; then
            log "Received heartbeat: $message"
        else
            log "Timeout: No heartbeat received in 30 seconds"
            break
        fi
    done
    
    # If we exit the inner loop, restart services
    log "Restarting services..."
    systemctl restart feralfile-launcher
    systemctl restart feralfile-chromium
    systemctl restart feralfile-switcher
done