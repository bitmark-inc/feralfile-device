#!/bin/bash
set -euo pipefail

chmod +x /root/soak-test/test.sh
chmod +x /root/soak-test/summary.py

/root/soak-test/test.sh