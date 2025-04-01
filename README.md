# Feral File X1 Project: Raspberry Pi Custom Image with Dynamic Resize and Kiosk Mode

## Overview

This project builds a custom Raspberry Pi image optimized for displaying digital artwork in kiosk mode. It supports dynamic resolution and orientation adjustment, boots directly into the Feral File launcher app, and includes essential tools for UI management. The image is built using pi-gen, a tool maintained by the Raspberry Pi Foundation, and customized to include only required packages and configurations.

---

## Development

### 1. Environment Setup

#### Prerequisites
- A Debian-based system to build the pi-gen image.
- A Debian-based system with ARM64 architecture to build the Flutter app.

**Note**: If you are developing on a macOS system, use the CI to build both the image and the app. You can then test by installing the generated files onto the SD card.

### 2. Building the Flutter App
1. **Use Image Version for Testing**:
   - For testing, use image version `0.1.2`, which still includes the full desktop environment.

2. **Build the App Using CI**:
   - After building the app with the CI pipeline, follow these steps:
     1. Go to the Raspberry Pi and access the [delivery page](https://feralfile-device-distribution.bitmark-development.workers.dev/):
     2. Download the app-only `.deb` package.
     3. Install the `.deb` package on the Pi:
        ```bash
        sudo dpkg -i <deb_file>
        ```
     4. Run the app:
        ```bash
        /opt/feralfile/feralfile
        ```

### 3. Build the Pi Image Using pi-gen
1. **Build the Image**:
    ```bash
    ./build-docker.sh
    ```
2. **Find the Generated Image**:
   - After the build completes, the image will be in the `deploy` folder.

---

## Build

### Steps to Build the Image Using GitHub Actions
1. **Choose the GitHub Action**:
   - Navigate to [GitHub Action Workflow](https://github.com/bitmark-inc/feralfile-device/actions/workflows/build-image-to-cf.yml).
2. **Set Parameters**:
   - Select the branch to build from.
   - Specify the app version to include.
   - Optionally, use a pre-built app version by skipping the app build.
3. **Trigger the Build**:
   - Press the build button to start the process.
4. **Locate the Generated Image**:
   - Visit the delivery page at [https://feralfile-device-distribution.bitmark-development.workers.dev/](https://feralfile-device-distribution.bitmark-development.workers.dev/) and log in

---

## Installation

1. **Download and Flash the Image**:
   - Visit the delivery page at [https://feralfile-device-distribution.bitmark-development.workers.dev/](https://feralfile-device-distribution.bitmark-development.workers.dev/) and log in
   - Download the image file.
   - Use Balena Etcher or Raspberry Pi Imager to flash the image onto an SD card.
   - Insert the flashed SD card into the Raspberry Pi.
2. **Boot the Device**:
   - Power up the Raspberry Pi.
   - The device will boot into kiosk mode with the Feral File launcher app.

---

## Release

1. **Download the Official Feral File Mobile App**:
   - Go to the App Store (iOS) or Google Play Store (Android) and search for "Feral File."
   - Download version `0.59.1` or above.

2. **Request Alpha Group Access**:
   - Open the app and navigate to the fourth tab.
   - Select "Help" and file a ticket requesting to be added to the alpha group.

3. **Enable FF-X1 Pilot Option**:
   - Once added to the alpha group, kill the app and restart it.
   - The "FF-X1 Pilot" option will appear in the menu on the fourth tab.

### Internal Note: Adding Users to the Alpha Group
1. **Get User ID**:
   - Retrieve the user ID from the customer support ticket.
2. **Update Config File**:
   - Add the user ID to the `beta_tester` array in the file located at:
     [https://github.com/bitmark-inc/feral-file-docs/blob/master/configs/app.json](https://github.com/bitmark-inc/feral-file-docs/blob/master/configs/app.json).
3. **Deploy Updated Config**:
   - Use the CI workflow to deploy the updated config to production:
     [https://github.com/bitmark-inc/feral-file-docs/actions/workflows/cloudflare-pages-deploy.yml](https://github.com/bitmark-inc/feral-file-docs/actions/workflows/cloudflare-pages-deploy.yml).
   - Select:
     - **Branch**: `main`
     - **Environment**: `Production`

---

## Debugging and Support

### Obtaining Logs
1. **Find the Device’s IP Address**:
   - Use a network scanning tool or check your router’s connected devices list to locate the Raspberry Pi’s IP address.

2. **Access Logs**:
   - If the device is connected to Wi-Fi, access logs via:
     ```
     http://<device_ip_address>:8080/logs.html
     ```

3. **Share Logs for Support**:
   - Save the logs from the provided URL and share them with the support team for debugging assistance.
