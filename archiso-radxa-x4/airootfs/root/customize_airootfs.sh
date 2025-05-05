#!/bin/bash
set -e -u

# Set locale
sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
locale-gen

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Configure root user
usermod -s /bin/bash root
cp -aT /etc/skel/ /root/
chmod 700 /root

# Create a default user
useradd -m -G wheel,audio,video,input -s /bin/bash feralfile
echo "feralfile:feralfile" | chpasswd
echo "root:root" | chpasswd

# Add user to sudoers
echo "feralfile ALL=(ALL) ALL" > /etc/sudoers.d/feralfile
chmod 440 /etc/sudoers.d/feralfile

# Enable services
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable bluetooth

# Create cage service for auto-starting the launcher in kiosk mode
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/cage-feralfile.service << EOF
[Unit]
Description=Cage Wayland compositor running Feral File Launcher
After=systemd-user-sessions.service network.target

[Service]
Type=simple
User=feralfile
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WLR_RENDERER=pixman
ExecStart=/usr/bin/cage -d -s -- /usr/bin/feralfile-launcher
Restart=on-failure

[Install]
WantedBy=graphical.target
EOF

# Enable the cage service
systemctl enable cage-feralfile.service

# Set XDG environment variables
mkdir -p /etc/environment.d
cat > /etc/environment.d/wayland.conf << EOF
# Use Wayland where possible
XDG_SESSION_TYPE=wayland
EOF

# Set proper permissions for the home directory
chown -R feralfile:feralfile /home/feralfile
