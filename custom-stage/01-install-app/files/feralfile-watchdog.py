import time
import socket
import logging
import subprocess
import asyncio
import websockets

# Configure logging to write to /var/log/feralfile-watchdog.log with timestamps.
logging.basicConfig(
    filename="/var/log/feralfile-watchdog.log",
    level=logging.INFO,
    format="%(asctime)s: %(message)s"
)

def is_server_up(host='localhost', port=8080):
    """
    Check if a TCP connection to the server can be made,
    replicating the 'nc -z localhost 8080' check.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        # connect_ex returns 0 if the connection succeeds
        return s.connect_ex((host, port)) == 0

async def monitor_websocket():
    """
    Connect to the WebSocket server and wait for heartbeat messages.
    A timeout of 30 seconds is applied to each receive attempt.
    """
    uri = "ws://localhost:8080/watchdog"
    try:
        async with websockets.connect(uri) as websocket:
            while True:
                try:
                    # Wait for a message with a 30 second timeout
                    message = await asyncio.wait_for(websocket.recv(), timeout=30)
                    logging.info(f"Received heartbeat: {message}")
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

async def main():
    """
    Main loop:
      1. Wait for the WebSocket server to become available.
      2. Once up, connect and monitor for heartbeats.
      3. If a timeout occurs (or the connection fails), restart services.
      4. Repeat indefinitely.
    """
    while True:
        # Wait until the WebSocket server is up.
        while not is_server_up():
            logging.info("WebSocket server not up yet, waiting 10 seconds...")
            time.sleep(10)
        logging.info("WebSocket server is up, connecting...")
        
        # Monitor the heartbeat; if the connection times out or fails, we exit the loop.
        await monitor_websocket()
        
        # Restart services when the inner loop exits.
        logging.info("Restarting services...")
        restart_services()

if __name__ == "__main__":
    # Run the main loop using asyncio.
    asyncio.run(main())