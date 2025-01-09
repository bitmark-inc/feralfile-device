#!/bin/bash

# Install required packages
apt-get update
apt-get install -y jq curl

# Make the update checker executable

# Create init.d service script
cat > /etc/init.d/feralfile-updater <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          feralfile-updater
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Feral File OTA Update Service
### END INIT INFO

DAEMON="/opt/feralfile/update-checker.sh"
NAME="feralfile-updater"

case "\$1" in
    start)
        echo "Starting \$NAME"
        start-stop-daemon --start --background --exec \$DAEMON
        ;;
    stop)
        echo "Stopping \$NAME"
        start-stop-daemon --stop --name \$NAME
        ;;
    restart)
        \$0 stop
        \$0 start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
exit 0
EOF

# Make the init.d script executable
chmod +x /etc/init.d/feralfile-updater

# Update rc.d to enable the service on boot
update-rc.d feralfile-updater defaults

# Start the service
/etc/init.d/feralfile-updater start

