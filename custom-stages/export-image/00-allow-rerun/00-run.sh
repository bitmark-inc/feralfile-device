#!/bin/bash -e

if [ ! -d "${ROOTFS_DIR}" ]; then
   copy_previous
fi

mkdir -p "${ROOTFS_DIR}/usr/bin"
cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"

if [ ! -x "${ROOTFS_DIR}/usr/bin/qemu-arm-static" ]; then
	cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"
fi

if [ -e "${ROOTFS_DIR}/etc/ld.so.preload" ]; then
	mv "${ROOTFS_DIR}/etc/ld.so.preload" "${ROOTFS_DIR}/etc/ld.so.preload.disabled"
fi
