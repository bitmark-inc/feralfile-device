package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/coreos/go-systemd/daemon"
	"github.com/gorilla/websocket"
)

const wsURL = "wss://tv-cast-coordination.bitmark-development.workers.dev/api/connection"

// Configuration for CDP connection
type Config struct {
	sync.RWMutex
	CDPHost string
	CDPPort int

	LocationID string
	TopicID    string
}

// Environment variable names
const (
	ENV_CDP_PORT = "CDP_PORT"

	// Default values
	CDP_HOST         = "localhost"
	DEFAULT_CDP_PORT = 9222
)

var (
	config *Config
)

// Retry config
const (
	maxRetries = 3
	baseDelay  = 3 * time.Second
)

func init() {
	cdpPort := DEFAULT_CDP_PORT
	if portStr := os.Getenv(ENV_CDP_PORT); portStr != "" {
		if port, err := strconv.Atoi(portStr); err == nil && port > 0 {
			cdpPort = port
		} else if err != nil {
			log.Printf("Invalid %s value: %v, using default: %d", ENV_CDP_PORT, err, DEFAULT_CDP_PORT)
		}
	}

	config = &Config{
		CDPHost: CDP_HOST,
		CDPPort: cdpPort,
	}

	log.Printf("CDP configuration: %s:%d", config.CDPHost, config.CDPPort)
}

func main() {
	// Start watchdog in a goroutine
	go startWatchdog()

	retries := 0

	for {
		err := connectAndListen()
		if err != nil {
			log.Printf("WebSocket error: %v", err)
			retries++
			if retries > maxRetries {
				log.Fatalf("Max retries exceeded. Shutting down...")
			}

			delay := baseDelay * time.Duration(retries)
			log.Printf("Reconnecting in %v...", delay)
			time.Sleep(delay)
		} else {
			retries = 0
		}
	}
}

func startWatchdog() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		log.Println("Watchdog check...")
		daemon.SdNotify(false, daemon.SdNotifyWatchdog)
	}
}

func connectAndListen() error {
	// Create URL with locationID and topicID if available
	connectURL := wsURL

	config.RLock()
	if config.LocationID != "" {
		connectURL += fmt.Sprintf("&locationID=%s", config.LocationID)
	}
	if config.TopicID != "" {
		connectURL += fmt.Sprintf("&topicID=%s", config.TopicID)
	}
	config.RUnlock()

	log.Printf("Connecting to WebSocket: %s", connectURL)
	dialer := websocket.DefaultDialer
	conn, _, err := dialer.Dial(connectURL, nil)
	if err != nil {
		return err
	}
	defer conn.Close()
	log.Println("Connected to WebSocket")

	// WS ping/pong
	stopPing := make(chan struct{})
	go startPingPong(conn, stopPing)
	defer close(stopPing)

	// Read message from relay server
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			return err
		}

		// Reset deadline when receiving any message
		_ = conn.SetReadDeadline(time.Time{})

		// Check JSON
		var data map[string]interface{}
		if err := json.Unmarshal(msg, &data); err != nil {
			log.Printf("Invalid JSON: %s", msg)
			continue
		}

		// Handle system message to get locationID and topicID
		if messageID, ok := data["messageID"].(string); ok && messageID == "system" {
			if message, ok := data["message"].(map[string]interface{}); ok {
				if locationID, ok := message["locationID"].(string); ok {
					config.Lock()
					config.LocationID = locationID
					config.Unlock()
					log.Printf("Received locationID: %s", locationID)
				}

				if topicID, ok := message["topicID"].(string); ok {
					config.Lock()
					config.TopicID = topicID
					config.Unlock()
					log.Printf("Received topicID: %s", topicID)
				}
			}
		}

		log.Printf("Received JSON: %s", msg)

		// Forward message to Chrome via CDP
		// go forwardToCDP(msg)
	}
}

func startPingPong(conn *websocket.Conn, stop chan struct{}) {
	pingInterval := 5 * time.Minute
	pongWait := 10 * time.Second

	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			pingMsg := map[string]string{
				"messageID": "ping",
				"message":   "ping",
			}
			pingBytes, _ := json.Marshal(pingMsg)
			if err := conn.WriteMessage(websocket.TextMessage, pingBytes); err != nil {
				log.Printf("Failed to send ping: %v", err)
				return
			}

			_ = conn.SetReadDeadline(time.Now().Add(pongWait))

		case <-stop:
			return
		}
	}
}
