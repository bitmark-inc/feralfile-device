#!/bin/bash
mkdir -p /opt/feralfile
dpkg -i /custom-stage/packages/feralfile-launcher_arm64.deb

# Create systemd service
cat > /etc/systemd/system/feralfile-launcher.service <<SERVICE
[Unit]
Description=Feral File Launcher
After=network.target

[Service]
ExecStart=/opt/feralfile/launcher
Restart=always
User=feralfile
WorkingDirectory=/opt/feralfile
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/feralfile/.Xauthority

[Install]
WantedBy=multi-user.target
SERVICE

systemctl enable feralfile-launcher.service 