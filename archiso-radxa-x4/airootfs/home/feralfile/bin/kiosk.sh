#!/usr/bin/env bash
exec /usr/bin/chromium \
  --ozone-platform=wayland \
  --ignore-gpu-blocklist \
  --use-angle=gl \
  --enable-gpu-rasterization \
  --enable-features=AcceleratedVideoDecodeLinuxGL \
  --enable-features=VaapiVideoDecoder,CanvasOopRasterization,UseSkiaRenderer,UseChromeOSDirectVideoDecoder \
  --kiosk https://bit.ly/36pointsDE \
  --show-fps-counter
