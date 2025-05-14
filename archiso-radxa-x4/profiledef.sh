#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="radxa-x4-arch"
iso_label="ARCH_RADXA_X4"
iso_publisher="Feral File <https://feralfile.com>"
iso_application="Feral File Launcher"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/install-to-disk.sh"]="0:0:755"
  ["/home/feralfile/"]="1000:1000:755"
  ["/usr/bin/feral-setupd"]="0:0:755"
  ["/usr/bin/feral-connectd"]="0:0:755"
  ["/usr/share/plymouth/themes/feralfile-splash/feralfile-splash.script"]="0:0:644"
  ["/usr/share/plymouth/themes/feralfile-splash/feralfile-splash.plymouth"]="0:0:644"
  ["/usr/share/plymouth/themes/feralfile-splash/splash.jpg"]="0:0:644"
  ["/etc/plymouth/plymouthd.conf"]="0:0:644"
  ["/etc/initcpio/hooks/plymouth-theme"]="0:0:755"
  ["/etc/initcpio/install/plymouth-theme"]="0:0:755"
  ["/root/plymouth-setup.sh"]="0:0:755"
  ["/etc/profile.d/plymouth-setup.sh"]="0:0:755"
  ["/etc/initcpio/hooks/plymouth-drm"]="0:0:755"
  ["/etc/initcpio/install/plymouth-drm"]="0:0:755"
  ["/root/boot-diagnostics.sh"]="0:0:755"
  ["/etc/systemd/system/boot-diagnostics.service"]="0:0:644"
)
