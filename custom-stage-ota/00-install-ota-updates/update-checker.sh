#!/bin/bash

FERALFILE_DIR="/opt/feralfile"
VERSION_FILE="$FERALFILE_DIR/version.json"
API_BASE="https://feralfile-device-distribution.bitmark-development.workers.dev"
LOG_FILE="/var/log/feralfile-updater.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_internet() {
    nmcli -t -f STATE g | grep -q "connected"
    return $?
}

get_branch() {
    jq -r '.branch' "$VERSION_FILE"
}

get_current_fingerprint() {
    jq -r '.app_fingerprint' "$VERSION_FILE"
}

while true; do
    if check_internet; then
        BRANCH=$(get_branch)
        CURRENT_FINGERPRINT=$(get_current_fingerprint)
        
        # Get latest version info
        RESPONSE=$(curl -s "$API_BASE/api/latest/$BRANCH")
        if [ $? -eq 0 ]; then
            NEW_FINGERPRINT=$(echo "$RESPONSE" | jq -r '.app_fingerprint')
            APP_URL=$(echo "$RESPONSE" | jq -r '.app_url')
            
            if [ "$NEW_FINGERPRINT" != "$CURRENT_FINGERPRINT" ]; then
                log "New version detected. Downloading update..."
                
                # Download new version
                TEMP_DEB="/tmp/feralfile-launcher.deb"
                if curl -s "$API_BASE$APP_URL" -o "$TEMP_DEB"; then
                    # Stop current app
                    pkill -f "/opt/feralfile/feralfile"
                    
                    # Install new version
                    if dpkg -i "$TEMP_DEB"; then
                        log "Update installed successfully"
                        
                        # Update fingerprint in version file
                        TMP_VERSION=$(mktemp)
                        jq --arg fp "$NEW_FINGERPRINT" '.app_fingerprint = $fp' "$VERSION_FILE" > "$TMP_VERSION"
                        mv "$TMP_VERSION" "$VERSION_FILE"
                        
                        # Restart app
                        /opt/feralfile/feralfile &
                    else
                        log "Failed to install update"
                    fi
                    
                    rm -f "$TEMP_DEB"
                else
                    log "Failed to download update"
                fi
            fi
        else
            log "Failed to check for updates"
        fi
    fi
    
    sleep 30
done