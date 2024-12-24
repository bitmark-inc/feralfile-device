# Raspberry Pi Custom Image with Dynamic Resize and Kiosk Mode

## **Overview**
This project provides a custom Raspberry Pi image setup for:
- **Dynamic resolution and orientation adjustment.**
- Running **Chromium in kiosk mode** for digital artwork.
- Ensuring the image is compact, using **PiShrink** to reduce size for distribution.

## **Directory Structure**
```
project/
├── README.md                 # Instructions for the team
├── scripts/                  # Automation scripts
│   ├── dynamic_resize.sh     # Dynamic resolution/rotation script
│   ├── build_image.sh        # Custom image build script
│   ├── setup_kiosk.sh        # Chromium kiosk setup script
│   └── shrink_image.sh       # Image shrinking script using PiShrink
├── configs/                  # Configuration files
│   ├── kiosk.desktop         # Chromium autostart configuration
│   ├── config.txt            # Raspberry Pi boot config
│   └── 99-display-hotplug.rules  # Udev rule for HDMI hotplug
└── images/                   # Prebuilt images (optional)
```

---

## **Scripts and Methods**

### **1. Dynamic Resize Script**
Handles:
- Detecting display resolution.
- Adjusting orientation (landscape/portrait).
- Resizing Chromium to fullscreen.

File: `scripts/dynamic_resize.sh`

[See the script content above.]

---

### **2. Build Image Script**
Automates unpacking, modifying, and repacking the Raspberry Pi image.

File: `scripts/build_image.sh`

[See the script content above.]

---

### **3. Shrink Image Script**
This script uses **PiShrink** to reduce the size of the Raspberry Pi image for efficient distribution.

File: `scripts/shrink_image.sh`

#### **Installation**
Ensure PiShrink is installed:
```bash
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo mv pishrink.sh /usr/local/bin/pishrink
```

#### **Shrink Script**
```bash
#!/bin/bash
set -e

INPUT_IMAGE=$1
if [[ -z "$INPUT_IMAGE" ]]; then
    echo "Usage: $0 <image-file>"
    exit 1
fi

echo "Shrinking image: $INPUT_IMAGE"
sudo pishrink $INPUT_IMAGE
echo "Image shrink complete!"
```

Save the file as `scripts/shrink_image.sh` and make it executable:
```bash
chmod +x scripts/shrink_image.sh
```

---

### **4. Master Setup Script**
Installs dependencies, applies configurations, and sets up scripts.

File: `setup.sh`

[See the script content above.]

---

## **Workflow**

### **1. Building and Modifying the Image**
1. Place the base Raspberry Pi OS image (`raspbian.img`) in the `images/` directory.
2. Run the build script to apply modifications:
   ```bash
   ./scripts/build_image.sh
   ```

### **2. Shrinking the Image**
1. Shrink the modified image to reduce its size:
   ```bash
   ./scripts/shrink_image.sh images/raspbian.img
   ```

2. The shrunk image will overwrite the original image unless you use the `-k` option with `pishrink`.

### **3. Flashing the Image**
1. Use a tool like **BalenaEtcher** or **Raspberry Pi Imager** to flash the shrunk image to an SD card.

### **4. Auto-Expanding Filesystem on First Boot**
The Raspberry Pi will automatically expand the filesystem on the first boot to utilize the full SD card space.

---

## **Testing Instructions**
1. Flash the modified, shrunk image to an SD card.
2. Boot the Raspberry Pi and verify:
   - Dynamic resolution and orientation.
   - Chromium launches in kiosk mode.
   - HDMI hotplug detection works.

---

## **Next Steps**
1. Host the project in a GitHub repository for collaboration.
2. Integrate PiShrink into the CI/CD pipeline for automated image shrinking.
3. Test the complete workflow and document any edge cases.

---

### **Changes Made**
- Added a dedicated **Shrink Image Script** section to explain PiShrink usage.
- Updated the workflow to include shrinking after building the image.
- Highlighted how to install and use PiShrink for team members unfamiliar with it.
- Retained the original structure for clarity.
