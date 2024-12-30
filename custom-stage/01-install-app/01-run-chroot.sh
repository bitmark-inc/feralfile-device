#!/bin/bash

dpkg -i feralfile-launcher_arm64.deb

# Create autostart directory and desktop entry
mkdir -p /home/feralfile/.config/autostart
cat > /home/feralfile/.config/autostart/feralfile-launcher.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Feral File Launcher
Exec=/opt/feralfile/feralfile
X-GNOME-Autostart-enabled=true
DESKTOP

# Set correct ownership
chown -R feralfile:feralfile /home/feralfile/.config