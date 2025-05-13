sudo chown feralfile:feralfile /home/feralfile

for timer in 08:00 16:00 20:00; do
    if ! sudo systemctl is-enabled "feral-updater@$timer.timer" >/dev/null 2>&1; then
        sudo systemctl enable --now "feral-updater@$timer.timer"
    fi
done