#!/bin/bash -e

on_chroot <<- EOF
	apt-mark auto python3-pyqt5 python3-opengl
	SUDO_USER="${FIRST_USER_NAME}" raspi-config nonint do_boot_behaviour B4
	raspi-config nonint do_xcompmgr 0
EOF
