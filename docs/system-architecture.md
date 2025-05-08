# FF-X1 System Architecture

*Rev 0.1 – 2025-05-06*

---

## 1\. Purpose

A concise, implementation-ready outline of how the FF-X1 device boots, connects, and operates on the Radxa X4 (Intel N100) / Arch Linux stack. 

---

## 2\. Design Principles

* **Stateless Core OS** – Read-only root with overlayfs; factory reset requires deleting a single directory.  
* **Single Source of Truth** – All control uses one protobuf schema, independent of transport.  
* **Composable systemd** targets keep setup logic isolated from kiosk runtime.  
* **Hybrid Connectivity** – Wi-Fi for bulk data & control, BLE for pairing and low-latency HID.  
* **Automated CI / Image Build** – Every push yields a flashable image \+ OTA repo.

---

## 3\. High-Level Block Diagram

```
┌──────────────┐   EFI   ┌───────────────┐
│ systemd-boot │────────►│  linux kernel │
└──────┬───────┘         └──────┬────────┘
       │ default.target         │ rootfs (ro)
       ▼                        ▼
  feral-state.service   ┌────────────────────┐
    (checks paired?)    │   overlay /var     │
       │yes/no          └────────┬───────────┘
       │                         │writable state
┌──────┴──────┐      setup.target│        kiosk.target
│ QR / BLE UI │◄──────────────┐  │  ┌──────────────┐
│ launcher-ui │               │  │  │ chromium-kiosk│
└─────────────┘               │  │  └──────────────┘
     ▲ paired=true            │  │  (art playback)
     │                        │  │
┌────┴─────────┐              │  │  ┌──────────────┐
│feral-setupd  │────BLE/DBus──┘  └──►feral-connectd│
│(pairing/WiFi)│                      (BLE⇆WS⇆Cloud)
└──────────────┘
```

---

## 4\. Boot & State Flow

1. **systemd-boot** loads kernel \+ initramfs from a 512 MiB ESP.  
     
2. **feral-state.service** (`Type=oneshot`, `RemainAfterExit=yes`) reads `/var/lib/feral/state.json`.  
     
   * **Not paired** → `systemctl isolate setup.target`  
   * **Paired** → `systemctl isolate kiosk.target`

   

3. **setup.target** starts  
     
   * **feral-setupd** – BLE advert, Wi-Fi credential ingest  
   * **launcher-ui** – QR code screen rendered by Chromium with an HTML bundle

   

4. Successful pairing writes `{paired:true,…}` to state and isolates **kiosk.target** (or reboots). 

---

## 5\. Connectivity Model

| Payload | Preferred Transport | Fallback |
| :---- | :---- | :---- |
| Pairing & Wi-Fi creds | **BLE GATT** | — |
| Control commands | **Wi-Fi WebSocket** | BLE |
| Playlists / metadata | Wi-Fi | BLE |
| Large assets (artwork) | **Wi-Fi HTTPS** | — |
| HID / Beacon triggers | **BLE notifications** | Wi-Fi mDNS |
| Remote (outside LAN) | Wi-Fi → Cloud relay | LTE AP |

### `feral-connectd`

A lightweight daemon exposing a gRPC bus and bridging:

* BLE ⇆ gRPC  
* Local WebSocket (TLS/PSK) ⇆ gRPC  
* Cloud WebSocket relay (MQTT-style) ⇆ gRPC 

---

## 6\. Service Inventory

| Unit File | Purpose | Key ExecStart / Action |
| :---- | :---- | :---- |
| **feral-state.service** | One-shot gatekeeper deciding **setup.target** vs **kiosk.target** | `/usr/bin/feral-state` *(calls* `systemctl isolate …` *)* |
| **feral-setupd.service** | BLE pairing \+ Wi-Fi join daemon | `/usr/bin/feral-setupd` |
| **launcher-ui.service** | QR onboarding screen (Chromium app window) | `/usr/bin/chromium --ozone-platform=wayland --app=file:///opt/feral/ui/launcher/index.html --disable-features=TranslateUI --noerrdialogs` |
| **feral-connectd.service** | Transport broker (BLE ⇄ local WS ⇄ cloud relay) | `/usr/bin/feral-connectd` |
| **feral-watchdog.service** | Restart kiosk / reboot on GPU, disk, or heartbeat failure | `/usr/bin/feral-watchdog`  |
| **chromium-kiosk.service** | Art player after pairing | `/usr/bin/chromium --ozone-platform=wayland --kiosk https://app.feralfile.com/device?kiosk_id=%m --enable-features=VaapiVideoDecoder,CanvasOopRasterization,UseChromeOSDirectVideoDecoder` |
| **ota-update.timer** | Weekly pacman upgrade → **ota-update.service** | `OnCalendar=Sun 03:00` → `/usr/bin/pacman -Syuu --noconfirm` |

---

## 7\. Packaging & Build Pipeline

1. **PKGBUILDs** for each custom component (`setupd`, `connectd`, `launcher-ui`).  
     
2. **archiso** profile (cloned from `releng`) injects custom packages & overlays; mounts root ro \+ overlay.  
     
3. **GitHub Actions** matrix:  
     
   * Build UI → artifact ZIP  
   * Build daemons → `.pkg.tar.zst`  
   * Run `archiso` in Docker → `ff-x1-<ver>.img.xz`  
   * Publish image \+ signed pacman repo to Releases & Cloudflare Pages.

---

## 8\. OTA Strategy

* Devices track `https://ota.feralfile.com/$arch` (signed pacman repo).  
* `ota-update.timer` runs weekly; reboots only if kernel or critical libs changed.  
* Major kernel bumps ship as full-disk images or factory reflasher.

---

## 9\. Security & Pairing

1. BLE LE Secure Connections creates LTK.  
     
2. Phone sends Wi-Fi SSID/PSK \+ 32-byte device PSK over encrypted GATT.  
     
3. Device stores PSK in `/var/lib/feral/creds.json` (mode 0600, owner `feral-connectd`) and reuses it for:  
     
   * Local WSS (TLS-PSK) sessions  
   * Cloud relay auth

   

4. Reset button wipes `/var/lib/feral` → unpaired state.

---

## 10\. Development Workflow

```shell
# Dev VM with Wayland accel
make vm                  

# Build everything
make image VERSION=0.6.0   # → out/ff-x1-0.6.0.img.xz

# Flash & 24-h smoke test
./tools/flash.sh /dev/nvme0n1 out/ff-x1-0.6.0.img.xz
./tools/smoke-test.sh
```

---

## 11\. Future Extensions

* Multi-frame sync via UDP multicast on Wi-Fi.  
* WebRTC low-latency streaming for live generative works.  
* Matter / Thread pairing path when mainstream APs catch up.

---

## 12\. Glossary

| Term | Meaning |
| :---- | :---- |
| **BLE** | Bluetooth Low Energy |
| **ESP** | EFI System Partition |
| **mDNS** | Multicast DNS service discovery |
| **OTA** | Over-the-air update |
| **PSK** | Pre-Shared Key |
