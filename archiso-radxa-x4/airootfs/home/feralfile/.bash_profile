sudo chown feralfile:feralfile /home/feralfile

for service in feral-setupd chromium-kiosk feral-connectd; do
    if ! sudo systemctl is-enabled "$service.service" >/dev/null 2>&1; then
        sudo systemctl enable "$service.service"
        sudo systemctl start "$service.service"
    fi
done