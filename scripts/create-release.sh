#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-stable}"
VERSION="${2:-0.0.1}"

# 1) Detect which architectures have Packages or Packages.gz
ARCHS=()
for arch in arm64 amd64; do
  if compgen -G "./${arch}/Packages" >/dev/null || compgen -G "./${arch}/Packages.gz" >/dev/null; then
    ARCHS+=("${arch}")
  fi
done
if [ ${#ARCHS[@]} -eq 0 ]; then
  echo "Error: no Packages or Packages.gz found under ./arm64 or ./amd64" >&2
  exit 1
fi

# 2) Join architectures with a single space (no trailing space)
ARCHS_LINE="${ARCHS[*]}"

# 3) Emit Release header
cat <<EOF
Origin: feralfile-launcher
Label: Feral File Repository
Suite: ${BRANCH}
Version: ${VERSION}
Codename: ${BRANCH}
Date: $(date -Ru)
Architectures: ${ARCHS_LINE}
Components: main
Description: Feral File Connection Assistant
EOF

# 4) Function to generate checksum blocks for a given algorithm
generate_hash_block() {
  local algo_name=$1   # e.g. "MD5Sum", "SHA1", "SHA256"
  local cmd=$2         # e.g. "md5sum", "sha1sum", "sha256sum"

  echo
  echo "${algo_name}:"
  for arch in "${ARCHS[@]}"; do
    find "./${arch}" -type f \( -name 'Packages' -o -name 'Packages.gz' \) | sort | \
    while read -r file; do
      local filename=$(basename "$file")
      local checksum=$($cmd "$file" | awk '{print $1}')
      local size=$(stat -c '%s' "$file")
      printf " %s %d main/binary-%s/%s\n" \
        "$checksum" "$size" "$arch" "$filename"
    done
  done
}

# 5) Output MD5, SHA1 and SHA256 blocks
generate_hash_block "MD5Sum"  "md5sum"
generate_hash_block "SHA1"    "sha1sum"
generate_hash_block "SHA256"  "sha256sum"