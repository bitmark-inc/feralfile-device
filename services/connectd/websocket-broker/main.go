package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/coreos/go-systemd/daemon"
	"github.com/gorilla/websocket"
)

// Configuration for CDP connection
type Config struct {
	sync.RWMutex
	CDPHost string
	CDPPort int

	WsURL    string
	WsAPIKey string

	LocationID string
	TopicID    string
}

// Environment variable names
const (
	ENV_CDP_PORT   = "CDP_PORT"
	ENV_WS_API_KEY = "WS_API_KEY"
	ENV_WS_URL     = "WS_URL"

	// Default values
	CDP_HOST         = "http://127.0.0.1"
	DEFAULT_CDP_PORT = 9222
	DEFAULT_WS_URL   = "wss://tv-cast-coordination.bitmark-development.workers.dev/api/connection"

	// CDP Methods
	NavigateMethod  = "Page.navigate"
	EvaluateMethod  = "Runtime.evaluate"
)

var (
	config *Config
)

var (
	cdpConn *websocket.Conn
	reqID   = 0
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

	wsApiKey := os.Getenv(ENV_WS_API_KEY)
	if wsApiKey == "" {
		log.Fatalf("Missing %s environment variable", ENV_WS_API_KEY)
	}

	wsURL := os.Getenv(ENV_WS_URL)
	if wsURL == "" {
		wsURL = DEFAULT_WS_URL
	}

	config = &Config{
		CDPHost:  CDP_HOST,
		CDPPort:  cdpPort,
		WsAPIKey: wsApiKey,
		WsURL:    wsURL,
	}

	log.Printf("CDP configuration: %s:%d", config.CDPHost, config.CDPPort)
}

func main() {
	// Start watchdog in a goroutine
	go startWatchdog()

	// Connect to Chromium CDP
	err := initCDP()
	if err != nil {
		log.Fatalf("CDP init failed: %v", err)
	}
	defer cdpConn.Close()

	// Test send CDP request
	// Navigate to YouTube
	err = sendCDPRequest(NavigateMethod, map[string]interface{}{
		"url": "https://www.youtube.com",
	})
	if err != nil {
		log.Printf("Failed to navigate to YouTube: %v", err)
	}

	// Evaluate JavaScript: console.log Hello World
	err = sendCDPRequest(EvaluateMethod, map[string]interface{}{
		"expression": "console.log('Hello World')",
	})
	if err != nil {
		log.Printf("Failed to evaluate JavaScript: %v", err)
	}

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

// initCDP fetches WS endpoint and dials Chromium
func initCDP() error {
	// Fetch JSON with websocket debugger URL
	resp, err := http.Get(config.CDPHost + ":" + strconv.Itoa(config.CDPPort) + "/json")
	if err != nil {
		return fmt.Errorf("failed to fetch debug targets: %w", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read targets: %w", err)
	}

	var targets []struct {
		Type                  string `json:"type"`
		WebSocketDebuggerURL string `json:"webSocketDebuggerUrl"`
	}
	if err := json.Unmarshal(body, &targets); err != nil {
		return fmt.Errorf("invalid targets format: %w", err)
	}

	// Connect to CDP websocket
	for _, t := range targets {
		if t.Type == "page" {
			cdpConn, _, err = websocket.DefaultDialer.Dial(t.WebSocketDebuggerURL, nil)
			if err != nil {
				return fmt.Errorf("cdp dial error: %w", err)
			}
			log.Println("Connected to Chromium CDP page target:", t.WebSocketDebuggerURL)
			return nil
		}
	}

	return fmt.Errorf("no page target found in Chromium instance")
}

// sendCDPRequest sends a raw CDP JSON-RPC message and waits for response
func sendCDPRequest(method string, params map[string]interface{}) error {
	if cdpConn == nil {
		return fmt.Errorf("CDP connection is not initialized")
	}

	reqID++
	msg := map[string]interface{}{
		"id":     reqID,
		"method": method,
		"params": params,
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("CDP marshal error: %w", err)
	}

	if err := cdpConn.WriteMessage(websocket.TextMessage, data); err != nil {
		return fmt.Errorf("CDP write error: %w", err)
	}

	// Wait for response
	_, response, err := cdpConn.ReadMessage()
	if err != nil {
		return fmt.Errorf("failed to read CDP response: %w", err)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(response, &resp); err != nil {
		return fmt.Errorf("failed to parse CDP response: %w", err)
	}

	// Check for error in response
	if err, ok := resp["error"].(map[string]interface{}); ok {
		return fmt.Errorf("CDP error: %v", err)
	}

	log.Printf("CDP response: %s", response)
	return nil
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
	connectURL := config.WsURL

	config.RLock()
	if config.WsAPIKey != "" {
		connectURL += fmt.Sprintf("/api/connection?apiKey=%s", config.WsAPIKey)
	}

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
