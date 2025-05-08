# FF‑X1 Flashing & Provisioning Playbook

*Rev 0.1 – 2025-05-07*

This playbook explains how we get the Arch‑based FF‑X1 OS onto Radxa X4 boards—**today for dev kits and tomorrow for 50–100‑unit sales waves**.  

---

## 1  Development‑phase flashing 

### 1.1  Image flavours

| Flavour | Use‑case | Notes |
| :---- | :---- | :---- |
| **Live‑only ISO** | Quick smoke tests, no disk writes | Boots in RAM, throwaway |
| **Live ISO \+ `install-to-disk.sh`** **← recommended** | Test first, then install permanently | One file; no drive‑size coupling |
| Pre‑flashed `.img` | CI, automated QEMU tests | dd/xzcat identical clone |

### 1.2  install‑to‑disk script (for devs)

```shell
# archiso/airootfs/root/install-to-disk.sh
#!/usr/bin/env bash
set -e
target=${1:-/dev/mmcblk0}
echo "⚠️  Wipes $target. Type YES to continue."; read confirm
[[ $confirm != YES ]] && exit 1
sgdisk --zap-all "$target"
sgdisk -n1:0:+512M -t1:ef00 -n2:0:0 -t2:8300 "$target"
mkfs.vfat -F32 "${target}p1"
mkfs.ext4 -F "${target}p2"
mount "${target}p2" /mnt && mkdir /mnt/boot && mount "${target}p1" /mnt/boot
rsync -aAX --exclude={"/proc/*","/sys/*"} / /mnt
arch-chroot /mnt bootctl install
echo "Install complete — reboot, remove USB."
```

Banner hint in ISO:

```shell
echo -e "\nRun \e[33minstall-to-disk.sh /dev/mmcblk0\e[0m to install FF‑X1."   >> /etc/zsh/zprofile
```

### 1.3  Flash tools

* **GUI:** balenaEtcher (macOS / Windows / Linux)  
* **CLI:** `tools/flash.sh`

```shell
xzcat image.iso.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

---

## 2  Production flashing for 50–100‑unit waves (soldered eMMC)

### 2.1  Master production image

* Rootfs shrunk to fit smallest eMMC minus 200 MB.  
* `factory.flag` present ➜ boots to 1‑min self‑test.  
* State file: `{"paired": false}`.  
* Signed (.gpg) \+ `.sha256`.

### 2.2  Clone method — *board flashes itself*

1. Prepare a **USB stick** with the live ISO **and** `/opt/ffx1-prod.img.xz`.  
2. **install‑to‑emmc.sh** (autoruns on boot) writes the compressed image to `/dev/mmcblk0`.

```shell
xzcat /opt/ffx1-prod.img.xz | dd of=/dev/mmcblk0 bs=4M conv=fsync status=progress
sync && touch /var/lib/feral/factory.flag && reboot
```

3. Board reboots, runs 60‑s factory self‑test.

### 2.3  Provisioning & jig

| Stage | Action |
| :---- | :---- |
| **Self‑test PASS** | Board sets LED green; exposes USB storage to host jig PC |
| **`provision.py`** | Generates UUID \+ PSK → `/var/lib/feral/device.json`; clears `factory.flag`; prints QR |
| **Box & label** | Operator unplugs board, screws into case, attaches label |

*Throughput:* 6‑slot USB‑C hub ≈ 4 min/board → 90 boards per 8‑hour shift with one operator.

### 2.4  Hardware BOM

| Item | Qty | Cost |
| :---- | :---- | :---- |
| Powered USB‑C hub (10 Gbps) | 1 | $120 |
| 2‑slot pogo‑pin bed (custom) | 1 | $300 |
| Brother QL label printer | 1 | $120 |
| USB sticks (32 GB) | 6 | $60 |

---

## 3  Quality & Traceability

* **`factory_result.json`** stored on board and mirrored to internal API.  
* QR scanner at boxing verifies Device‑ID & PSK pair in DB.  
* Boards without PASS log are quarantined.

---

## 4  Scaling beyond 1 k units

If monthly volume exceeds \~1 k units:

* Switch to **network‑boot cloning rack** to avoid USB shuffle.  
* Evaluate secure‑boot key signing for museum/enterprise installs.  
* Consider a robotic conveyor for automated pogo‑bed engagement.

---

### Summary

* **Dev kits:** Live ISO \+ `install-to-disk.sh` (micro SD/USB)  
* **First 100 units:** Board‑self‑flashes from USB, 6‑slot pogo jig for provisioning  
* **Future high volume:** Same scripts, swap manual USB for network rack

Everything the team needs—from scripts to SOP—is outlined here.  Pull requests welcome for refinements\!  