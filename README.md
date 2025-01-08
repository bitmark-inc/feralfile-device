# Raspberry Pi Custom Image with Dynamic Resize and Kiosk Mode

## Overview

This project builds a custom Raspberry Pi image optimized for displaying digital artwork in kiosk mode. It supports dynamic resolution and orientation adjustment, boots directly into the Feral File launcher app, and includes essential tools for UI management.

The image is built using pi-gen, a tool maintained by the Raspberry Pi Foundation, and customized to include only required packages and configurations.

## Building the Image

### Prerequisites

- A Debian based system
- A Raspberry Pi 4 or 5

### 1. Generate the Base Image with pi-gen
####	1.	Clone the pi-gen repository:

```bash
git clone https://github.com/RPi-Distro/pi-gen.git
cd pi-gen
```

#### 2.	Follow the pi-gen folder convention for stages:
	•	Each stage (e.g., stage1, stage2) contains scripts to configure the image.
	•	Custom configurations are added in a custom-stage directory, replacing the default stage3.
	•	Package lists are defined in 00-packages for mandatory packages and 00-packages-nr for recommended (non-essential) ones.
#### 3.	Copy the custom-stage folder into pi-gen:

```bash
cp -r ../custom-stage pi-gen/stage3
```

#### 4.	Build the image:

```bash
./build-docker.sh
```

#### 5.	After completion, the generated image will be in the deploy folder.

### 2. Custom-Stage Details

The custom-stage folder customizes the image to support the Feral File launcher app. It includes:
#### 1.	Package Installation:
	•	Installs only required UI packages for GTK and Flutter compatibility.
	•	Package lists are in:
	•	00-packages - Required packages.
	•	00-packages-nr - Recommended packages (not mandatory).
#### 2.	Launcher App Installation:
	•	Installs the Feral File launcher app as a Debian package (.deb).
	•	Automatically sets the launcher to boot at startup using the script 01-run-chroot.sh.
#### 3.	Boot Configuration Script (01-run-chroot.sh):
	•	Copies the app to /opt/feralfile.
	•	Ensures the app launches on boot using systemd service configuration.
	•	Enables dynamic display resizing and orientation adjustments.

### 3. CI/CD Workflow

The Continuous Integration (CI) process automates building and deploying the image.

Steps:
#### 1.	Build the Launcher App:
	•	The launcher app (Flutter) is built in the launcher-app folder.
	•	Runs on an ARM64 instance because Flutter does not support cross-architecture compiling.
#### 2.	Create a Debian Package (.deb):
	•	Packages the compiled app into a .deb file for installation.
	•	Uses GitHub Actions to automate this step.
#### 3.	Integrate the App into the Image:
	•	Copies the .deb file into the custom-stage folder of pi-gen.
	•	Replaces the default stage3 in pi-gen to include the app and required dependencies.

## Contributing

### 1. App Development
	•	Update the launcher app code in the launcher-app folder.
	•	Build the app and generate the Debian package:

flutter build linux --release --target-platform=linux-arm64
dpkg-deb --build package feralfile-launcher_<version>_arm64.deb


	•	Transfer the .deb file to the Pi:

scp feralfile-launcher_<version>_arm64.deb pi@<raspberry-pi-ip>:~


	•	Install and test:

sudo dpkg -i feralfile-launcher_<version>_arm64.deb
/opt/feralfile/feralfile

### 2. Image Customization
	•	Add or Remove Packages:
Update 00-packages or 00-packages-nr in custom-stage.
	•	Update Boot Script:
Modify 01-run-chroot.sh in custom-stage to change startup behavior.
	•	Test the Updated Image:
Rebuild the image and test on the Raspberry Pi.

Building and Distributing the Image
	1.	Use the GitHub Action to build and deploy the image:
GitHub Action Workflow
	2.	Fill in the required parameters:
	•	Branch: Select the GitHub branch to build from.
	•	Version Number: Specify the app version to include.
	•	Skip App Building: Optionally, use a pre-built version by filling in the version number.

## Testing Instructions
	1.	Flash the generated image onto an SD card using Balena Etcher or Raspberry Pi Imager.
	2.	Boot the Raspberry Pi and verify:
	•	Dynamic resolution and orientation adjustments work.
	•	Chromium launches in kiosk mode.
	•	The launcher app starts automatically.
	3.	Check logs for errors and confirm connectivity.