#!/bin/bash

# Create feralfile service 
mkdir -p /etc/systemd/system

# Add these lines to ensure proper user permissions
usermod -a -G bluetooth,dialout feralfile

rm -f /etc/systemd/system/feralfile-launcher.service
cat > /etc/systemd/system/feralfile-launcher.service << EOF
[Unit]
Description=FeralFile Launcher Application
After=bluetooth.target
Requires=bluetooth.service

[Service]
User=feralfile
Group=feralfile
ExecStartPre=/bin/sleep 1.5
ExecStart=/opt/feralfile/feralfile
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/feralfile/.Xauthority
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
EOF

rm -f /etc/systemd/system/feralfile-chromium.service
cat > /etc/systemd/system/feralfile-chromium.service << EOF
[Unit]
Description=FeralFile Chromium
After=feralfile-launcher.service
Wants=feralfile-launcher.service

[Service]
User=feralfile
Group=feralfile
ExecStart=/home/feralfile/services/feralfile-chromium.sh
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=default.target
EOF

rm -f /etc/systemd/system/feralfile-watchdog.service
cat > /etc/systemd/system/feralfile-watchdog.service << EOF
[Unit]
Description=WebSocket Watchdog Service
After=feralfile-launcher.service
Wants=feralfile-launcher.service

[Service]
ExecStart=python3 /home/feralfile/services/feralfile-watchdog.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

rm -f /etc/systemd/system/feralfile-updater@.service
cat > /etc/systemd/system/feralfile-updater@.service << EOF
[Unit]
Description=FeralFile Updater Instance - %i
After=network.target

[Service]
Type=simple
ExecStart=/home/feralfile/services/feralfile-updater.sh
EOF

rm -f /etc/systemd/system/feralfile-updater@.timer
cat > /etc/systemd/system/feralfile-updater@.timer << EOF
[Unit]
Description=FeralFile Updater - %i Run

[Timer]
Persistent=true
OnCalendar=%i
RandomizedDelaySec=7200  # Up to 2 hour random delay
Unit=feralfile-updater@%i.service

[Install]
WantedBy=timers.target
EOF