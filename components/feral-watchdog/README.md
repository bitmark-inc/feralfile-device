# CDP Monitor

The CDP Monitor is responsible for monitoring the health of the Chromium browser using Chrome DevTools Protocol.

## Monitoring Logic

1. **Health Check**

   - Checks Chromium health via CDP every 5 seconds
   - If health check fails or returns non-200, checks time since last successful response
   - If no successful response for over 20 seconds, restarts `chromium-kiosk.service`
   - If 3 restarts occur within 5 minutes, triggers a system reboot

# RAM Monitoring

The Feral Watchdog includes a RAM usage monitor that helps prevent system freezes or crashes due to memory exhaustion.

## RAM Monitoring Logic

The system continuously monitors RAM usage with the following logic:

- Checks RAM usage every 5 seconds
- If RAM usage exceeds 95% for 3 consecutive checks (15 seconds total):
  - Restarts the `chromium-kiosk.service` to free up memory
- If high RAM usage recurs within 1 minute after a restart:
  - Triggers a full system reboot to recover from potential memory leaks

# Disk Monitoring

The system continuously monitors Disk usage with the following logic:

## Disk Monitoring Logic

The system monitors disk usage on the `/var` partition with the following logic:

- Checks disk usage every 60 seconds
- If disk usage exceeds 90%:
  - Logs a warning message indicating high disk usage
- If disk usage exceeds 95% (critical threshold):
  - Triggers a system reboot to protect against potential system instability

# GPU Monitoring

The system continuously monitors the Intel i915 GPU to detect and recover from GPU hangs.

## GPU Monitoring Logic

The system monitors kernel messages for GPU-related issues with the following logic:

- Continuously reads from `/dev/kmsg` looking for specific error patterns
- If a message contains both "GPU hang" and "i915" strings:
  - Identifies this as an Intel GPU hang condition
  - Immediately triggers a system reboot to recover
