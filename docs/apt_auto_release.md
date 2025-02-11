# FeralFile Auto Release to APT Repository

This document describes the automated process for building, packaging, and deploying the `feralfile-launcher` app to a custom APT repository hosted on Cloudflare Pages & Workers. The system supports branch-based releases automatically.

## Overview

The github workflow `build-app-to-cf.yml` automates:

- Building the application and packaging it as a `.deb` file.
- Generating APT repository metadata files (`Packages`, `Packages.gz`, `Release`).
- Signing the `Release` with a GPG key by action runner (`InRelease`).
- Uploading everything to Cloudflare R2.

The build distribution page will host the files following the APT rules.

## Details

### Secrets & Variables

| Name | Description |
|------|-------------|
| APT_GPG_SIGN_KEY_PASSPHRASE | Passphrase for signing APT repo |
| APT_GPG_SIGN_KEY_ID | GPG Key ID for signing |

- The passphrase and private/public key are stored on Bitwarden

### APT Repository Structure

The repository is structured as follows in Cloudflare R2:

```text
/ff-device-images/                    
  ├── $your_branch_name/               
  │   ├── feralfile-launcher_1.0.0_arm64.deb
  │   ├── feralfile-launcher_1.0.1_arm64.deb
  │   ├── Release             
  │   ├── InRelease           
  │   ├── Packages            
  │   ├── Packages.gz
```

### Installing on a Linux based devices

1. Add the gpg public key to your device

    - You can find the `public-key.asc` in the `/custome-stage/01-install-app/files/apt-public-key.asc`
    - Store it on your device

    ```sh
    /etc/apt/trusted.gpg.d/feralfile.asc
    ```

2. Add the distribution site credential to your device

    ```sh
    cat > /etc/apt/auth.conf.d/feralfile.conf << EOF
    machine feralfile-device-distribution.bitmark-development.workers.dev
    login $BASIC_AUTH_USER
    password $BASIC_AUTH_PASS
    EOF
    ```

3. Add the APT repository to your device APT repo list

    ```sh
    cat > /etc/apt/sources.list.d/feralfile.list << EOF
    deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/feralfile.asc] https://feralfile-device-distribution.bitmark-development.workers.dev/ $your_branch_name main
    EOF
    ```

4. Update and install:

    ```sh
    sudo apt-get update
    sudo apt-get install feralfile-launcher
    ```
