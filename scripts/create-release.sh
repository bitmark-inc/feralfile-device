#!/bin/sh
set -e

BRANCH="${1:-stable}"
VERSION="${2:-0.0.1}"
ARCH="${3:-arm64}"

do_hash() {
    HASH_NAME=$1
    HASH_CMD=$2
    echo "${HASH_NAME}:"
    for f in $(find . -type f); do
        f=$(echo $f | cut -c3-) # remove ./ prefix
        if [ "$f" = "Release" ]; then
            continue
        fi
        if [ "$f" = "Packages" ]; then
            echo " $(${HASH_CMD} ${f} | cut -d' ' -f1) $(wc -c $f | awk '{print $1}') main/binary-${ARCH}/Packages"
        fi
        if [ "$f" = "Packages.gz" ]; then
            echo " $(${HASH_CMD} ${f} | cut -d' ' -f1) $(wc -c $f | awk '{print $1}') main/binary-${ARCH}/Packages.gz"
        fi
    done
}

cat << EOF
Origin: feralfile-launcher
Label: Feral File Repository
Suite: stable
Codename: ${BRANCH}
Version: ${VERSION}
Architectures: ${ARCH}
Components: main
Description: Feral File Connection Assistant
Date: $(date -Ru)
EOF
do_hash "MD5Sum" "md5sum"
do_hash "SHA1" "sha1sum"
do_hash "SHA256" "sha256sum"