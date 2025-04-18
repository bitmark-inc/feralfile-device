import socket
import logging
import subprocess
import asyncio
import websockets
import sentry_sdk
import os
import dbus
from subprocess import run, PIPE, DEVNULL

# Constants
LOG_PATH = "/var/log/chromium/chrome_debug.log"
HEARTBEAT_TIMEOUT = 15  # Seconds to wait for a heartbeat
MAX_HEARTBEAT_FAILURES = 4  # Number of heartbeat failures before rebooting
PING_IPS = ["8.8.8.8", "1.1.1.1", "9.9.9.9"]  # IPs to check internet connectivity

CONFIG_PATH = "/home/feralfile/.config/feralfile/feralfile-launcher.conf"

def get_config_value(key, config_path=CONFIG_PATH):
    if not os.path.exists(config_path):
        return None
    with open(config_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith(f"{key}"):
                # Split on ' = ' and strip spaces
                parts = line.split("=", 1)
                if len(parts) == 2:
                    return parts[1].strip()
    return None

SENTRY_DSN = get_config_value("sentry_dsn")

# Initialize Sentry SDK
sentry_sdk.init(
    dsn=SENTRY_DSN,
    traces_sample_rate=1.0,
)

# Configure logging
logging.basicConfig(
    filename="/var/log/feralfile-watchdog.log",
    level=logging.INFO,
    format="%(asctime)s: %(message)s",
)

# Map Chromium log levels to Sentry breadcrumb levels
LEVEL_MAPPING = {
    "DEBUG": "debug",
    "INFO": "info",
    "WARNING": "warning",
    "ERROR": "error",
    "FATAL": "fatal",
}

heartbeat_failed_count = 0

async def wait_for_server(wait_interval=5, max_failures=12):
    """
    Waits for the server to be up and returns True if successful,
    or False if the maximum number of failures is reached.
    """
    failures = 0
    while True:
        internetConnected = internet_connected()
        serverUp = is_server_up()
        if internetConnected and serverUp:
            return True
        elif internetConnected and not serverUp:
            logging.warning("WebSocket server not up but internet is connected")
            failures += 1
        elif not internetConnected and serverUp:
            logging.info("WebSocket server is up, waiting for internet connectivity...")
        else:
            logging.info("WebSocket server is not up, waiting for internet connectivity...")
        if failures >= max_failures:
            return False
        await asyncio.sleep(wait_interval)

def is_server_up(host="localhost", port=8080):
    """
    Check if a TCP connection to the server can be made.
    
    Args:
        host (str): Hostname to check (default: 'localhost').
        port (int): Port to check (default: 8080).
    
    Returns:
        bool: True if server is up.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex((host, port)) == 0

def internet_connected():
    """
    Check internet connectivity by pinging well-known IP addresses.
    
    Returns:
        bool: True if at least one ping succeeds, False otherwise.
    """
    for ip in PING_IPS:
        try:
            result = subprocess.run(
                ["ping", "-c", "1", "-W", "1", ip],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if result.returncode == 0:
                logging.info(f"Ping successful to {ip}")
                return True
        except Exception as e:
            logging.warning(f"Ping to {ip} failed: {e}")
    return False

async def monitor_websocket():
    """
    Connect to the WebSocket server and monitor heartbeat messages.
    
    Resets failure count on first heartbeat, exits on timeout or connection error.
    """
    global heartbeat_failed_count
    uri = "ws://localhost:8080/watchdog"
    try:
        async with websockets.connect(uri) as websocket:
            logging.info("Trying to receive first heartbeat...")
            try:
                await asyncio.wait_for(websocket.recv(), timeout=HEARTBEAT_TIMEOUT)
                heartbeat_failed_count = 0
            except asyncio.TimeoutError:
                logging.warning("Timeout: Failed to receive first heartbeat")
                return
            logging.info("Monitoring heartbeat...")
            while True:
                try:
                    await asyncio.wait_for(websocket.recv(), timeout=HEARTBEAT_TIMEOUT)
                except asyncio.TimeoutError:
                    logging.warning(f"Timeout: No heartbeat received in {HEARTBEAT_TIMEOUT} seconds")
                    break
    except Exception as e:
        logging.info(f"Error connecting to WebSocket: {e}")

def report_to_sentry(log_path):
    """
    Send a Sentry report with log breadcrumbs and the last error message.
    
    Args:
        log_path (str): Path to the log file to analyze.
    """
    logging.info("Starting log analysis for Sentry reporting")
    log_entries = parse_last_n_lines(log_path, n=100)
    if not log_entries:
        logging.warning("No log entries found or unable to read log file")
        sentry_sdk.capture_message("Heartbeat timeout occurred. Unable to read log file.")
        return
    for entry in log_entries:
        level = LEVEL_MAPPING.get(entry["level"].upper(), "info")
        sentry_sdk.add_breadcrumb(message=entry["message"], level=level)
    last_error = next((entry for entry in reversed(log_entries) if entry["level"].upper() == "ERROR"), None)
    if last_error:
        message = f"Heartbeat timeout occurred. Last ERROR: {last_error['message']}"
        logging.warning(message)
    else:
        message = "Heartbeat timeout occurred. No recent ERROR in logs."
        logging.info(message)
    sentry_sdk.capture_message(message)
    logging.info("Sentry report sent successfully")

def parse_last_n_lines(log_path, n=100):
    """
    Parse the last n lines from a log file into structured entries.
    
    Args:
        log_path (str): Path to the log file.
        n (int): Number of lines to read (default: 100).
    
    Returns:
        list: List of dicts with 'timestamp', 'level', and 'message' keys.
    """
    try:
        with open(log_path, "r") as file:
            lines = file.readlines()[-n:]
        log_entries = []
        for line in lines:
            line = line.strip()
            if line.startswith("[") and "]" in line:
                try:
                    prefix, message = line.split("]", 1)
                    prefix = prefix[1:]  # Remove leading '['
                    parts = prefix.split(":")
                    if len(parts) >= 4:
                        timestamp = parts[2]
                        level = parts[3]
                        message = message.strip()
                        log_entries.append({"timestamp": timestamp, "level": level, "message": message})
                    else:
                        logging.warning(f"Malformed log entry: {line}")
                except Exception as e:
                    logging.warning(f"Error parsing log entry: {line} - {e}")
            else:
                logging.warning(f"Non-standard log entry: {line}")
        logging.info(f"Parsed {len(log_entries)} log entries from {log_path}")
        return log_entries
    except FileNotFoundError:
        logging.error(f"Log file not found: {log_path}")
        return []
    except Exception as e:
        logging.error(f"Error reading log file {log_path}: {e}")
        return []

def reboot():
    """
    Reboot the device.
    """
    result = subprocess.run(["sudo", "reboot", "-f"])
    if result.returncode == 0:
        logging.info(f"Reboot triggered successfully")
    else:
        logging.error(f"Failed to reboot")

def check_bluetooth_service():
    """
    Check if Bluetooth service is running and functioning properly.
    Returns: tuple (bool, str) - (is_healthy, status_message)
    """
    try:
        # Check systemd service status
        result = run(['systemctl', 'is-active', 'bluetooth'], 
                    stdout=PIPE, stderr=PIPE, text=True)
        
        if result.stdout.strip() != 'active':
            logging.error(f"Bluetooth service is not active: {result.stdout}")
            return False, "service_inactive"

        # Try to get BlueZ interface through D-Bus
        bus = dbus.SystemBus()
        try:
            adapter_obj = bus.get_object('org.bluez', '/org/bluez/hci0')
            adapter_props = dbus.Interface(adapter_obj, 'org.freedesktop.DBus.Properties')
            powered = adapter_props.Get('org.bluez.Adapter1', 'Powered')
            
            if not powered:
                logging.error("Bluetooth adapter is not powered on")
                return False, "adapter_off"
                
        except dbus.exceptions.DBusException as e:
            logging.error(f"D-Bus error checking Bluetooth: {e}")
            return False, "dbus_error"

        return True, "healthy"
        
    except Exception as e:
        logging.error(f"Error checking Bluetooth status: {e}")
        return False, "check_failed"

def restart_bluetooth():
    """
    Restart the Bluetooth service and wait for it to be ready.
    Returns: bool - True if restart was successful
    """
    try:
        logging.info("Attempting to restart Bluetooth service...")
        
        # Stop the service
        run(['sudo', 'systemctl', 'stop', 'bluetooth'], check=True)
        
        # Small delay to ensure clean shutdown
        asyncio.sleep(2)
        
        # Start the service
        run(['sudo', 'systemctl', 'start', 'bluetooth'], check=True)
        
        # Wait for service to be fully up
        for _ in range(10):  # Try for 10 seconds
            asyncio.sleep(1)
            is_healthy, status = check_bluetooth_service()
            if is_healthy:
                logging.info("Bluetooth service successfully restarted")
                return True
                
        logging.error("Bluetooth service failed to restart properly")
        return False
        
    except Exception as e:
        logging.error(f"Error restarting Bluetooth service: {e}")
        return False

async def main():
    global heartbeat_failed_count
    bluetooth_restart_attempts = 0
    MAX_BLUETOOTH_RESTARTS = 3
    
    while heartbeat_failed_count < MAX_HEARTBEAT_FAILURES:
        # Check Bluetooth status
        is_healthy, status = check_bluetooth_service()
        
        if not is_healthy:
            logging.warning(f"Bluetooth issue detected: {status}")
            
            if bluetooth_restart_attempts < MAX_BLUETOOTH_RESTARTS:
                bluetooth_restart_attempts += 1
                logging.info(f"Attempting Bluetooth restart ({bluetooth_restart_attempts}/{MAX_BLUETOOTH_RESTARTS})")
                
                if restart_bluetooth():
                    bluetooth_restart_attempts = 0  # Reset counter on successful restart
                    continue
                else:
                    logging.error("Failed to restart Bluetooth service")
            else:
                logging.error("Max Bluetooth restart attempts reached, triggering reboot")
                report_to_sentry(LOG_PATH)
                reboot()
                return
        
        # Continue with existing WebSocket monitoring
        if not await wait_for_server():
            report_to_sentry(LOG_PATH)
            logging.info("Reached maximum connection failures. Rebooting...")
            reboot()
            return
            
        await monitor_websocket()
        heartbeat_failed_count += 1
        
    report_to_sentry(LOG_PATH)
    logging.info("Reached maximum heartbeat failures. Rebooting...")
    reboot()

if __name__ == "__main__":
    asyncio.run(main())