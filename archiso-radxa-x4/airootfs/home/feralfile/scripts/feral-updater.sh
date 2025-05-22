#!/bin/bash
set -euo pipefail

if ! ping -q -c 1 -W 2 8.8.8.8 >/dev/null; then
  echo "❌ No network connection. Aborting update."
  exit 1
fi

CONFIG_FILE="/home/feralfile/x1-config.json"
OTA_API="https://feralfile-device-distribution.bitmark-development.workers.dev/api/latest"

echo "📖 Reading config from $CONFIG_FILE"
branch=$(jq -r '.branch' "$CONFIG_FILE")
current_version=$(jq -r '.version' "$CONFIG_FILE")
auth_user=$(jq -r '.distribution_acc' "$CONFIG_FILE")
auth_pass=$(jq -r '.distribution_pass' "$CONFIG_FILE")

API_URL="$OTA_API/$branch"
echo "🌐 Fetching latest version info from: $API_URL"
response=$(curl -su "$auth_user:$auth_pass" -f "$API_URL")
latest_version=$(jq -r '.latest_version' <<< "$response")
image_url=$(jq -r '.image_url' <<< "$response")

echo "🆚 Current: $current_version  →  Remote: $latest_version"
if [[ "$latest_version" != "$current_version" ]]; then
  echo "📦 New Image version detected. Running full OTA update..."
  exec /home/feralfile/scripts/feral-system-update.sh "$image_url"
else
  echo "✅ Image already up-to-date. Checking for package updates..."
  exec /home/feralfile/scripts/feral-service-update.sh
fi
