#!/bin/bash

# Paths to applications
FERALFILE="/opt/feralfile/feralfile"

# Environment setup
export DISPLAY=:0
export XAUTHORITY=/home/feralfile/.Xauthority

# Start the FeralFile application
echo "Starting FeralFile application..."
"$FERALFILE"
