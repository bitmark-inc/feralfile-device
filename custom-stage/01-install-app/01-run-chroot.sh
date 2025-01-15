#!/bin/bash

chown -R feralfile:feralfile /home/feralfile/feralfile/

dpkg -i /home/feralfile/feralfile/feralfile-launcher_arm64.deb

# Create autostart
mkdir -p /home/feralfile/.config/openbox
cat > /home/feralfile/.config/openbox/autostart <<EOF
xset s off
xset s noblank
xset -dpms

/opt/feralfile/feralfile &
sleep 5
if ! pgrep -x "feralfile" > /dev/null; then
    zenity --info \
        --title="Feral File Launcher" \
        --text="Can't start launcher normally, reinstalling backup..." \
        --timeout=5 \
        --width=400 \
        --height=100
    sudo dpkg -i /home/feralfile/feralfile/feralfile-launcher_arm64.deb
    /opt/feralfile/feralfile &
fi
EOF

# Set correct ownership
chown -R feralfile:feralfile /home/feralfile/.config

# Configure auto-login for feralfile user
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/12-autologin.conf <<EOF
[Seat:*]
autologin-user=feralfile
autologin-user-timeout=0
EOF

# Create btautopair file to enable Bluetooth HID auto-pairing
touch /boot/firmware/btautopair

# Add OTA cronjob update script
chmod 755 /home/feralfile/feralfile/feralfile-ota-update.sh
CRON_CMD="*/30 * * * * DISPLAY=:0 XAUTHORITY=/home/feralfile/.Xauthority sudo /home/feralfile/feralfile/feralfile-ota-update.sh"
crontab -u feralfile -l 2>/dev/null || true > /tmp/feralfile_cron
grep -F "$CRON_CMD" /tmp/feralfile_cron >/dev/null 2>&1 || echo "$CRON_CMD" >> /tmp/feralfile_cron
crontab -u feralfile /tmp/feralfile_cron
rm /tmp/feralfile_cron

# Create a custom configuration for unattended-upgrades
mkdir -p /etc/apt/apt.conf.d
sudo cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Origins-Pattern {
    "origin=Raspbian,codename=${distro_codename},label=Raspbian";
    "origin=Raspberry Pi Foundation,codename=${distro_codename},label=Raspberry Pi Foundation";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Allow-downgrade "true";
Unattended-Upgrade::Keep-Debs-After-Install "true";
EOF

sudo cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "1";
EOF