#!/bin/bash

# Install required packages
apt-get update
apt-get install -y jq curl

# Make the update checker executable
mkdir -p /opt/feralfile

# Create systemd service
cat > /etc/systemd/system/feralfile-updater.service <<EOF
[Unit]
Description=Feral File OTA Update Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/feralfile/update-checker.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable feralfile-updater.service
systemctl start feralfile-updater.service

