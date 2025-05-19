# RAM, GPU, DISK Monitoring

The monitord will send a metric every 2s.

## GPU

If hanging, immediately reboot.

## DISK

If disk usage > 90% (or even > 95%), trigger cleanup /tmp/ and pacman cache. After cleanup, freeze the disk checking for 10s.
After 10s from the cleanup.

- If disk usage > 95%: reboot.
- If disk usage > 90%: cleanup again.
- If disk usage < 90%: Normal, reset cleanup state.

## RAM

If RAM usage > 95% for more than 15s, then restart kiosk. If RAM usage > 95% for > 15s again with 60s after a restart, then reboot.
After restart kiosk, freeze the monitor for 5s, wait for the service restarting before checking again.
