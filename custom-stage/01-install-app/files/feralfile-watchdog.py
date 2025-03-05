import os
import time
import socket
import logging
import subprocess
import asyncio
import websockets
import sentry_sdk

# Read SENTRY_DSN from environment variables
SENTRY_DSN = os.getenv("SENTRY_DSN")

# Initialize Sentry SDK with the environment-provided DSN
sentry_sdk.init(
    dsn=SENTRY_DSN,  # Read from environment
    traces_sample_rate=1.0,  # Optional: adjust as needed
)

# Configure logging to write to /var/log/feralfile-watchdog.log with timestamps
logging.basicConfig(
    filename="/var/log/feralfile-watchdog.log",
    level=logging.INFO,
    format="%(asctime)s: %(message)s"
)

# Map Chromium log levels to Sentry breadcrumb levels
level_mapping = {
    'DEBUG': 'debug',
    'INFO': 'info',
    'WARNING': 'warning',
    'ERROR': 'error',
    'FATAL': 'fatal',
}

def is_server_up(host='localhost', port=8080):
    """
    Check if a TCP connection to the server can be made,
    replicating the 'nc -z localhost 8080' check.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex((host, port)) == 0

async def monitor_websocket():
    """
    Connect to the WebSocket server and wait for heartbeat messages.
    A timeout of 30 seconds is applied to each receive attempt.
    """
    uri = "ws://localhost:8080/watchdog"
    try:
        async with websockets.connect(uri) as websocket:
            logging.info(f"Monitoring heartbeat...")
            while True:
                try:
                    await asyncio.wait_for(websocket.recv(), timeout=30)
                except asyncio.TimeoutError:
                    logging.info("Timeout: No heartbeat received in 30 seconds")
                    break
    except Exception as e:
        logging.info(f"Error connecting to WebSocket: {e}")

def restart_services():
    """
    Restart the required services using systemctl.
    """
    services = ["feralfile-launcher", "feralfile-chromium", "feralfile-switcher"]
    for service in services:
        subprocess.run(["systemctl", "restart", service])
        logging.info(f"Service {service} restarted")

def parse_last_n_lines(log_path, n=100):
    """
    Read the last n lines from the log file and parse into log entries.
    Assumes log format: [timestamp] [level] message
    """
    try:
        with open(log_path, 'r') as file:
            lines = file.readlines()[-n:]  # Get the last n lines
        log_entries = []
        for line in lines:
            parts = line.strip().split(' ', 2)
            if len(parts) >= 3:
                timestamp, level, message = parts[0], parts[1], parts[2]
                log_entries.append({'timestamp': timestamp, 'level': level, 'message': message})
        return log_entries
    except FileNotFoundError:
        logging.error(f"Log file not found: {log_path}")
        return []
    except Exception as e:
        logging.error(f"Error reading log file {log_path}: {e}")
        return []

def report_to_sentry(log_path):
    """
    Parse the log file and send a Sentry event with the last ERROR and breadcrumbs.
    """
    log_entries = parse_last_n_lines(log_path, n=100)
    if not log_entries:
        sentry_sdk.capture_message("Heartbeat timeout occurred. Unable to read log file.")
        return

    # Add up to 100 log entries as breadcrumbs
    for entry in log_entries:
        level = level_mapping.get(entry['level'].upper(), 'info')
        sentry_sdk.add_breadcrumb(message=entry['message'], level=level)

    # Find the last ERROR message
    last_error = next((entry for entry in reversed(log_entries) if entry['level'].upper() == 'ERROR'), None)
    if last_error:
        message = f"Heartbeat timeout occurred. Last ERROR: {last_error['message']}"
    else:
        message = "Heartbeat timeout occurred. No recent ERROR in logs."
    
    sentry_sdk.capture_message(message)

async def main():
    """
    Main loop:
      1. Wait for the WebSocket server to become available.
      2. Once up, connect and monitor for heartbeats.
      3. If a timeout occurs, report to Sentry and restart services.
      4. Repeat indefinitely.
    """
    while True:
        while not is_server_up():
            logging.info("WebSocket server not up yet, waiting 10 seconds...")
            time.sleep(10)
        logging.info("WebSocket server is up, connecting...")
        
        await monitor_websocket()
        
        # Report log information to Sentry when heartbeat stops
        report_to_sentry('/var/log/chromium/chrome_debug.log')
        
        logging.info("Restarting services...")
        restart_services()

if __name__ == "__main__":
    asyncio.run(main())