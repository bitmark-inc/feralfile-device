#!/bin/bash
set -e

# Check if an image file is provided as an argument
if [[ -z "$1" ]]; then
    echo "Usage: $0 <image-file>"
    exit 1
fi

INPUT_IMAGE=$1

# Verify the image file exists
if [[ ! -f "$INPUT_IMAGE" ]]; then
    echo "Error: Image file '$INPUT_IMAGE' not found."
    exit 1
fi

echo "Shrinking image: $INPUT_IMAGE"

# Ensure PiShrink is installed
if ! command -v pishrink &> /dev/null; then
    echo "PiShrink is not installed. Installing now..."
    wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
    chmod +x pishrink.sh
    sudo mv pishrink.sh /usr/local/bin/pishrink
fi

# Run PiShrink on the input image
sudo pishrink "$INPUT_IMAGE"

echo "Image shrinking complete!"