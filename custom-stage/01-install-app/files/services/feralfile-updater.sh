#!/bin/bash

set -e

CONFIG_FILE="/home/feralfile/.config/feralfile/feralfile-launcher.conf"
REPO_URL="https://github.com/bitmark-inc/feralfile-device.git"
SPARSE_PATH="custom-stage/01-install-app/files"
TEMP_DIR="/tmp/feralfile-updating-files"
DEST_DIR="/home/feralfile"

get_config_value() {
    local key="$1"
    grep "^$key" "$CONFIG_FILE" | awk -F' = ' '{print $2}' | tr -d ' '
}

set_config_value() {
    local key="$1"
    local value="$2"
    if grep -q "^$key" "$CONFIG_FILE"; then
        sed -i "s/^$key *= *.*/$key = $value/" "$CONFIG_FILE"
    else
        echo "$key = $value" >> "$CONFIG_FILE"
    fi
}

BRANCH=$(get_config_value "app_branch")
CURRENT_COMMIT=$(get_config_value "commit_hash")
if [ -z "$BRANCH" ]; then
    echo "Error: app_branch not set in config."
    exit 1
fi

LATEST_COMMIT=$(git ls-remote "$REPO_URL" "refs/heads/$BRANCH" | cut -f1)

if [ "$CURRENT_COMMIT" == "$LATEST_COMMIT" ]; then
    echo "✅ Already up to date (commit $CURRENT_COMMIT)"
    exit 0
fi

echo "🔄 Updating files from branch: $BRANCH"
echo "Old commit: $CURRENT_COMMIT"
echo "New commit: $LATEST_COMMIT"

# Clone minimal repo
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

git init
git remote add origin "$REPO_URL"
git config core.sparseCheckout true
echo "$SPARSE_PATH" >> .git/info/sparse-checkout
git pull origin "$BRANCH"

cd "$TEMP_DIR/$SPARSE_PATH"

# Replace files
for path in migrations scripts services; do
    rm -rf "$DEST_DIR/$path"
    cp -r "$path" "$DEST_DIR/$path"
done

cp "migrate.sh" "$DEST_DIR/migrate.sh"

mkdir -p "/etc/apt/trusted.gpg.d/"
cp "apt-public-key.asc" "/etc/apt/trusted.gpg.d/feralfile.asc"
chmod 644 "/etc/apt/trusted.gpg.d/feralfile.asc"

set_config_value "commit_hash" "$LATEST_COMMIT"

echo "✅ Files Update complete at $(date)"
echo "🔄 Executing /home/feralfile/migrate.sh..."

/home/feralfile/migrate.sh

echo "✅ Migrate complete at $(date)"