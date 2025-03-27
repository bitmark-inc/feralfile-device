#!/bin/bash

set -e  # Exit on error

# Desired BlueZ version
DESIRED_BLUE_Z_VERSION="5.79"

# Get current BlueZ version (if installed)
if command -v bluetoothd >/dev/null 2>&1; then
  CURRENT_VERSION="$(bluetoothd -v)"
  echo "Current BlueZ version: $CURRENT_VERSION"
else
  CURRENT_VERSION="0.0"
  echo "BlueZ not installed."
fi

# Function to compare versions
version_lt() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]
}

if version_lt "$CURRENT_VERSION" "$DESIRED_BLUE_Z_VERSION"; then
  echo "Updating BlueZ to version $DESIRED_BLUE_Z_VERSION..."

  apt-get install libglib2.0-dev libdbus-1-dev libudev-dev libical-dev libreadline-dev python3-docutils -y

  cd /home/feralfile
  wget http://www.kernel.org/pub/linux/bluetooth/bluez-${DESIRED_BLUE_Z_VERSION}.tar.xz
  tar xvf bluez-${DESIRED_BLUE_Z_VERSION}.tar.xz
  cd bluez-${DESIRED_BLUE_Z_VERSION}/
  ./configure --prefix=/usr --mandir=/usr/share/man --sysconfdir=/etc --localstatedir=/var --with-systemdsystemunitdir=/lib/systemd/system --with-systemduserunitdir=/usr/lib/system --enable-experimental
  make -j4
  make install

  apt-get remove libglib2.0-dev libdbus-1-dev libudev-dev libical-dev libreadline-dev python3-docutils -y
  rm /home/feralfile/bluez-${DESIRED_BLUE_Z_VERSION}.tar.xz
  rm -rf /home/feralfile/bluez-${DESIRED_BLUE_Z_VERSION}
  cd /

  echo "BlueZ updated to $DESIRED_BLUE_Z_VERSION."
else
  echo "BlueZ is already up to date (version $CURRENT_VERSION)."
fi