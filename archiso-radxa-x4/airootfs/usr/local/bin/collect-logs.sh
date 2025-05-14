#!/bin/bash

# Run the boot diagnostics script to collect current system state
/root/boot-diagnostics.sh

echo "Logs collected at /var/log/boot-diagnostics/"
echo "Latest log: /var/log/boot-diagnostics/latest.log" 