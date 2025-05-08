# Chromium Performance Flags for Low-Power Kiosk Mode

## GPU Acceleration and Rendering Flags

- `--ignore-gpu-blocklist`: Forces Chromium to use GPU features even if blacklisted. Essential for low-power GPUs like Intel N100 or Radxa 5C's Mali.  
  _Trade-off: May expose rendering instability if the driver is buggy._

- `--enable-gpu-rasterization`: Paints web content using GPU instead of CPU. Boosts performance for CSS, canvas, etc.  
  _Trade-off: Slightly higher GPU memory usage._

- `--enable-zero-copy`: Eliminates CPU→GPU memory copies by writing tiles directly to GPU memory.  
  _Trade-off: Only works if supported by the driver._

- `--enable-native-gpu-memory-buffers`: Uses native GPU buffers for compositing.  
  _Trade-off: No effect if not supported._

- `--disable-gpu-driver-bug-workarounds`: Disables safety workarounds for known GPU driver bugs.  
  _Trade-off: Risk of rendering glitches._

- `--disable-software-rasterizer`: Prevents fallback to CPU rasterization.  
  _Trade-off: Content might not render if GPU can’t handle it._

- `--force-gpu-rasterization`: Forces all rasterization onto GPU.  
  _Trade-off: Might hurt trivial renders._

- `--enable-oop-rasterization`: Moves raster tasks to a dedicated process.  
  _Trade-off: Slightly higher memory use._

- GL Backend Selection:

  - `--use-gl=egl`: For ARM and Wayland systems (e.g., Radxa 5C).
  - `--use-gl=desktop`: For Intel/X11 systems. Required for VA-API.

- `--enable-features=Vulkan`: Enables Vulkan rendering (experimental).  
  _Trade-off: May cause instability or fallback to software._

## Hardware-Accelerated Video Playback

- `--enable-accelerated-video-decode`: Enables GPU-based video decoding.  
  _Trade-off: Falls back to CPU if unsupported._

- `--enable-features=VaapiVideoDecoder,VaapiVideoEncoder`: Enables VA-API on Linux/Intel for hardware decode/encode.  
  _Trade-off: Requires working drivers._

- Radxa 5C Tips:

  - Use `--ignore-gpu-blocklist`, `--enable-accelerated-video-decode`, `--use-gl=egl`.
  - Verify decode in `chrome://gpu`.

- `--disable-features=UseChromeOSDirectVideoDecoder`: Useful if ChromeOS paths break video decode.  
  _Trade-off: Might reduce performance if ChromeOS path was working._

- Verify video decode in `chrome://media-internals`.

## Process Model and Security Trade-offs

- `--no-sandbox` and `--disable-setuid-sandbox`: Disables Chromium sandboxing.  
  _Trade-off: Huge security risk._

- `--disable-features=IsolateOrigins,site-per-process`: Disables strict site isolation.  
  _Trade-off: Weaker memory/process isolation._

- `--process-per-site`: Limits processes per domain.  
  _Trade-off: Less isolation but fewer processes._

- `--disable-ipc-flooding-protection`: Removes IPC rate limits.  
  _Trade-off: May freeze if misused._

- `--disable-hang-monitor`: Prevents “Page unresponsive” dialog.  
  _Trade-off: Hangs won’t auto-recover._

- `--disable-backgrounding-occluded-windows` and `--disable-renderer-backgrounding`: Prevents throttling in background tabs.  
  _Trade-off: Minor CPU use._

- `--disable-web-security`: Disables same-origin/CORS restrictions.  
  _Trade-off: Removes all browser security checks._

## Network and Resource Loading Optimizations

- `--enable-features=ParallelDownloading`: Splits downloads into parallel streams.  
  _Trade-off: Slightly more resource usage._

- `--enable-tcp-fast-open`: Reduces connection setup time.  
  _Trade-off: Needs server and OS support._

- `--disable-quic`: Disables HTTP/3.  
  _Trade-off: Might worsen performance in some networks._

- `--enable-simple-cache-backend`: More efficient disk cache.  
  _Trade-off: None significant._

- `--enable-scroll-prediction`: Smoother scrolling.  
  _Trade-off: None._

- `--cc-scroll-animation-duration-in-seconds=0.6`: Faster scroll settle time.  
  _Trade-off: Less inertia._

- `--enable-checker-imaging`: Async image decoding.  
  _Trade-off: May show checkerboard briefly._

- `--enable-experimental-canvas-features`: Enables faster canvas rendering.  
  _Trade-off: Experimental features may have bugs._

- `--enable-low-res-tiling`: Uses low-res tiles during fast scrolling.  
  _Trade-off: More memory use._

- Tiling and Raster:
  - `--max-tiles-for-interest-area=512`: Renders content ahead of view.
  - `--default-tile-height=512`: Larger tiles reduce overhead.
  - `--num-raster-threads=4`: Use more threads for raster work.  
    _Trade-off: May cause CPU contention._

## Additional System Tweaks

- Set CPU governor to `performance` to avoid downclocking.  
  _Trade-off: Higher power use._

- Keep GPU drivers updated. Prefer Mesa or vendor-specific drivers.

- Use lightweight display managers (avoid GNOME/KDE if possible).

- Disable Chrome features:

  - `--disable-extensions`
  - `--disable-component-update`
  - `--disable-background-networking`
  - `--disable-background-timer-throttling`

- Kiosk UI flags:

  - `--disable-infobars`
  - `--autoplay-policy=no-user-gesture-required`
  - `--noerrdialogs`

- Filesystem tuning: use `noatime`, `f2fs`, `zram` for better disk/memory performance.

- Add external watchdog to restart Chromium if it hangs/crashes.

- Check `chrome://gpu` and `chrome://media-internals` for hardware acceleration status.

---

## Conclusion

These flags strip Chromium down to a lean, GPU-first engine ideal for kiosks. You're trading security and general-purpose stability for predictable, high-performance rendering of trusted content. Perfect for Intel N100 or RK3588S boards running WebGL, video, and generative art in kiosk mode.
