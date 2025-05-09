#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/sync-to-x4.sh [local-dir] [remote-dir]
# E.g:
#   ./scripts/sync-to-x4.sh . /home/feralfile/wifi_bt_app

LOCAL_DIR="${1:-.}/"
REMOTE_USER="feralfile"
REMOTE_HOST="192.168.31.91"
REMOTE_PASS="portal"
REMOTE_DIR="${2:-/home/${REMOTE_USER}/project/}"

# ensure sshpass is installed
if ! command -v sshpass &>/dev/null; then
  echo "❌ sshpass not found. Install it via: brew install sshpass"
  exit 1
fi

# build ssh wrapper
SSH_CMD="sshpass -p '${REMOTE_PASS}' ssh -o StrictHostKeyChecking=no"

# print debug info
echo "🔍 LOCAL_DIR = ${LOCAL_DIR}"
echo "🌐 REMOTE_DIR = ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"

rsync -avz \
  --delete \
  --exclude 'target/' \
  --exclude '.git/' \
  --exclude '*.rs.bk' \
  -e "${SSH_CMD}" \
  "${LOCAL_DIR}" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"