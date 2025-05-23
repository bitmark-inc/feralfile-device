#!/bin/bash
set -euo pipefail

cage bash -- --login /home/soaktest/test.sh > soaktest.log 2>&1
