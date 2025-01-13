#!/usr/bin/env bash
###############################################################################
# feralfile-ota-update.sh
#
# This script handles checking an OTA server for updates, installing them,
# showing status using Zenity, and rolling back if needed.
###############################################################################

# Log all output for debugging
exec > /tmp/ota-update.log 2>&1

API_BASE_URL="https://feralfile-device-distribution.bitmark-development.workers.dev"
LOCAL_DEB_PATH="./feralfile-launcher_arm64.deb"
LOCAL_CONFIG_PATH="./feralfile-launcher.conf"
BACKUP_DEB_PATH="./feralfile-launcher_arm64.bak.deb"
BACKUP_CONFIG_PATH="./feralfile-launcher.bak.conf"

REBOOT_DELAY_SECONDS=5

########################################
# FUNCTION: show_info
#   Show a small Zenity popup & log the same message
########################################
function show_info() {
  local message="$1"
  echo "[INFO] $message"
  zenity --info \
    --title="Feral File Launcher Updater" \
    --text="$message" \
    --timeout=5 \
    --width=400 \
    --height=100
}

########################################
# FUNCTION: get_config_value
#   Extract a specific value from the config file
########################################
function get_config_value() {
  local key="$1"
  grep "^$key" "$LOCAL_CONFIG_PATH" | awk -F' = ' '{print $2}' | tr -d ' '
}

########################################
# MAIN SCRIPT LOGIC
########################################

# Read local version from the config file if present
if [[ -f "$LOCAL_CONFIG_PATH" ]]; then
  LOCAL_VERSION="$(get_config_value "app_version")"
  LOCAL_BRANCH="$(get_config_value "app_branch")"
  BASIC_AUTH_USER="$(get_config_value "distribution_auth_user")"
  BASIC_AUTH_PASS="$(get_config_value "distribution_auth_password")"
else
  LOCAL_VERSION=""
  LOCAL_BRANCH=""
  BASIC_AUTH_USER=""
  BASIC_AUTH_PASS=""
fi

echo "Currently installed version: $LOCAL_VERSION"
echo "Currently based branch: $LOCAL_BRANCH"

# Fetch remote metadata. Must return JSON with fields: app_version, latest_version, app_url
API_RESPONSE="$(curl -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASS" -s "$API_BASE_URL/api/latest/$LOCAL_BRANCH")"
REMOTE_VERSION="$(echo "$API_RESPONSE" | jq -r '.latest_version')"
REMOTE_APP_URL="$(echo "$API_RESPONSE" | jq -r '.app_url')"

echo "Latest version: $REMOTE_VERSION"
echo "Remote .deb URL: $REMOTE_APP_URL"

# Compare versions
if [[ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]]; then
  show_info "New version detected..."

  if pgrep -f "/opt/feralfile/feralfile" > /dev/null; then
    show_info "Stopping the running application for update..."
    pkill -TERM -f "/opt/feralfile/feralfile"
  fi

  show_info "Downloading new version..."

  # Back up the current .deb and config file
  cp "$LOCAL_DEB_PATH" "$BACKUP_DEB_PATH"
  echo "Backed up current .deb to $BACKUP_DEB_PATH"

  cp "$LOCAL_CONFIG_PATH" "$BACKUP_CONFIG_PATH"
  echo "Backed up current config to $BACKUP_CONFIG_PATH"

  # Download the new .deb file
  NEW_DEB_TEMP="/tmp/feralfile-launcher_new.deb"
  curl -u "$BASIC_AUTH_USER:$BASIC_AUTH_PASS" -sSL "$API_BASE_URL$REMOTE_APP_URL" -o "$NEW_DEB_TEMP"

  show_info "Installing new version..."

  # Attempt to install the new .deb file
  if dpkg -i "$NEW_DEB_TEMP"; then
    echo "Installation succeeded."
    mv "$NEW_DEB_TEMP" "$LOCAL_DEB_PATH"

    # Update the config file with the new version
    sed -i "s/^app_version = .*/app_version = $REMOTE_VERSION/" "$LOCAL_CONFIG_PATH"

    show_info "Update complete. Rebooting in $REBOOT_DELAY_SECONDS seconds..."
    sleep "$REBOOT_DELAY_SECONDS"
    reboot
  else
    echo "Installation failed! Rolling back..."
    show_info "Installation failed. Rolling back..."

    cp "$BACKUP_DEB_PATH" "$LOCAL_DEB_PATH"
    cp "$BACKUP_CONFIG_PATH" "$LOCAL_CONFIG_PATH"
    dpkg -i "$LOCAL_DEB_PATH"
    show_info "Rollback complete. System remains on the old version."
    /opt/feralfile/feralfile &
  fi
fi