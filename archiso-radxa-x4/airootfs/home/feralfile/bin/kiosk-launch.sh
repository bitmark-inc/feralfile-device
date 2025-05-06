#!/usr/bin/env bash
set -euo pipefail
/usr/bin/cage -s -- /home/feralfile/bin/kiosk.sh &
wait
