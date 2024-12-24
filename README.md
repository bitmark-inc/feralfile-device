# Package Raspberry Pi Dynamic Resize Setup into Custom Image

## **Overview**
This issue tracks the creation of a reproducible workflow for packaging the Raspberry Pi dynamic resize and kiosk mode setup into a custom image. This will enable team collaboration and easy deployment.

### **Goals**
- Package all scripts, configurations, and enhancements into a single project.
- Automate installation and image building.
- Ensure the solution works for both **landscape** and **portrait** display orientations.
- Make the setup easily reusable by the team.

---

## **Project Structure**
Organize the project files for clarity and ease of use:

```
project/
├── README.md                 # Instructions for the team
├── scripts/                  # Automation scripts
│   ├── dynamic_resize.sh     # Dynamic resolution/rotation script
│   ├── build_image.sh        # Custom image build script
│   └── setup_kiosk.sh        # Chromium kiosk setup script
├── configs/                  # Configuration files
│   ├── wpa_supplicant.conf   # Wi-Fi configuration template
│   ├── kiosk.desktop         # Chromium autostart configuration
│   ├── config.txt            # Raspberry Pi boot config
│   └── 99-display-hotplug.rules  # Udev rule for HDMI hotplug
└── images/                   # Prebuilt images (optional)
```

---

## **Scripts and Enhancements**

### **1. Dynamic Resize Script**
Handles:
- **Detecting display resolution.**
- **Adjusting orientation** (landscape/portrait).
- **Resizing Chromium** to fullscreen.

Script: `scripts/dynamic_resize.sh`
```bash
#!/bin/bash
export DISPLAY=:0

LOGFILE="/var/log/display_adjust.log"

# Log the script execution
echo "$(date): Starting dynamic_resize.sh" >> $LOGFILE

# Get the connected display name (e.g., HDMI-A-1)
DISPLAY_NAME=$(xrandr | grep " connected" | awk '{print $1}')
if [[ -z "$DISPLAY_NAME" ]]; then
    echo "$(date): No display detected. Exiting." >> $LOGFILE
    exit 1
fi

# Detect the current resolution
RESOLUTION=$(xrandr | grep "$DISPLAY_NAME connected" | awk '{print $4}' | cut -d'+' -f1)
if [[ -z "$RESOLUTION" ]]; then
    echo "$(date): No resolution detected for $DISPLAY_NAME. Using fallback resolution 1920x1080." >> $LOGFILE
    xrandr --output $DISPLAY_NAME --mode 1920x1080
    RESOLUTION="1920x1080"
fi

# Split resolution into width and height
WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)
HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)

echo "$(date): Detected resolution: ${WIDTH}x${HEIGHT}" >> $LOGFILE

# Determine orientation
if [[ $WIDTH -lt $HEIGHT ]]; then
    # Portrait mode
    echo "$(date): Switching to Portrait Mode" >> $LOGFILE
    xrandr --output $DISPLAY_NAME --rotate right
else
    # Landscape mode
    echo "$(date): Switching to Landscape Mode" >> $LOGFILE
    xrandr --output $DISPLAY_NAME --rotate normal
fi

# Resize Chromium to fit the screen
echo "$(date): Resizing Chromium to fullscreen" >> $LOGFILE
wmctrl -r chromium-browser -b add,maximized_vert,maximized_horz

echo "$(date): dynamic_resize.sh completed successfully" >> $LOGFILE
```

---

### **2. Build Image Script**
Automates unpacking, modifying, and repacking the Raspberry Pi image.

Script: `scripts/build_image.sh`
```bash
#!/bin/bash
set -e

IMAGE="raspbian.img"
MOUNT_DIR="/mnt/image"

echo "Mounting image..."
sudo losetup -Pf $IMAGE
sudo mount /dev/loop0p2 $MOUNT_DIR

echo "Applying modifications..."
sudo cp configs/wpa_supplicant.conf $MOUNT_DIR/etc/wpa_supplicant/
sudo cp configs/kiosk.desktop $MOUNT_DIR/home/pi/.config/autostart/
sudo cp scripts/dynamic_resize.sh $MOUNT_DIR/usr/local/bin/
sudo chmod +x $MOUNT_DIR/usr/local/bin/dynamic_resize.sh
sudo cp configs/99-display-hotplug.rules $MOUNT_DIR/etc/udev/rules.d/

echo "Unmounting and repacking image..."
sudo umount $MOUNT_DIR
sudo losetup -d /dev/loop0
```

---

### **3. Master Setup Script**
Installs dependencies, applies configurations, and sets up scripts.

Script: `setup.sh`
```bash
#!/bin/bash
set -e

echo "Starting setup..."

# Copy configuration files
echo "Copying configuration files..."
sudo cp configs/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
sudo cp configs/kiosk.desktop /home/pi/.config/autostart/kiosk.desktop
sudo cp configs/config.txt /boot/firmware/config.txt

# Install required packages
echo "Installing dependencies..."
sudo apt update && sudo apt install -y x11-xserver-utils wmctrl bluez python3-uinput

# Install dynamic resize script
echo "Setting up dynamic resize script..."
sudo cp scripts/dynamic_resize.sh /usr/local/bin/dynamic_resize.sh
sudo chmod +x /usr/local/bin/dynamic_resize.sh

# Set up udev rule for HDMI hotplug
echo "Setting up udev rule..."
sudo cp configs/99-display-hotplug.rules /etc/udev/rules.d/99-display-hotplug.rules
sudo udevadm control --reload

echo "Setup complete. Rebooting now..."
sudo reboot
```

---

## **Configurations**

### **Wi-Fi Configuration**: `configs/wpa_supplicant.conf`
```plaintext
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="YourWiFiSSID"
    psk="YourWiFiPassword"
}
```

### **Chromium Autostart**: `configs/kiosk.desktop`
```plaintext
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=chromium-browser --kiosk --disable-infobars --disable-session-crashed-bubble --noerrdialogs https://your-url.com
X-GNOME-Autostart-enabled=true
```

---

## **Testing Instructions**

1. **Setup**:
   - Clone the repository:
     ```bash
     git clone https://github.com/your-team/repo.git
     cd repo
     ```
   - Run the setup script:
     ```bash
     ./setup.sh
     ```

2. **Build Image**:
   - Place the base Raspberry Pi OS image in the `images/` directory.
   - Run the build script:
     ```bash
     ./scripts/build_image.sh
     ```

3. **Test**:
   - Flash the modified image to an SD card.
   - Boot the Raspberry Pi and verify:
     - Dynamic resolution and orientation.
     - Chromium launches in kiosk mode.
     - HDMI hotplug detection works.

---

## **Next Steps**
1. Host the project in a GitHub repository for collaboration.
2. Review and refine the scripts for edge cases (e.g., no display connected).
3. Test the complete workflow and document any issues.
