package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// WSClient handles WebSocket connection to relay server
type WSClient struct {
	config *Config
	cdp    *CDPClient
	conn   *websocket.Conn
	mu     sync.Mutex
	done   chan struct{}
}

// NewWSClient creates a new WebSocket client
func NewWSClient(config *Config, cdp *CDPClient) *WSClient {
	return &WSClient{
		config: config,
		cdp:    cdp,
		done:   make(chan struct{}),
	}
}

// ConnectAndListen connects to the WebSocket server and listens for messages
func (w *WSClient) ConnectAndListen(ctx context.Context) error {
	// Create URL with locationID and topicID if available
	connectURL := w.config.WsURL

	w.config.RLock()
	if w.config.WsAPIKey != "" {
		connectURL += fmt.Sprintf("/api/connection?apiKey=%s", w.config.WsAPIKey)
	}

	if w.config.LocationID != "" {
		connectURL += fmt.Sprintf("&locationID=%s", w.config.LocationID)
	}

	if w.config.TopicID != "" {
		connectURL += fmt.Sprintf("&topicID=%s", w.config.TopicID)
	}

	w.config.RUnlock()

	log.Printf("Connecting to WebSocket: %s", connectURL)
	dialer := websocket.DefaultDialer

	w.mu.Lock()
	conn, _, err := dialer.Dial(connectURL, nil)
	if err != nil {
		w.mu.Unlock()
		return err
	}

	w.conn = conn
	w.mu.Unlock()
	defer func() {
		w.mu.Lock()
		if w.conn != nil {
			w.conn.Close()
			w.conn = nil
		}
		w.mu.Unlock()
	}()

	log.Println("Connected to WebSocket")

	// WS ping/pong
	stopPing := make(chan struct{})
	go w.startPingPong(stopPing)
	defer close(stopPing)

	// Handle context cancellation
	go func() {
		select {
		case <-ctx.Done():
			log.Println("Closing WebSocket connection due to context cancellation")
			w.Close()
		case <-w.done:
			// Exit if closed manually
			log.Println("Context handler exiting due to manual close")
		}
	}()

	// Read message from relay server
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-w.done:
			return nil
		default:
			w.mu.Lock()
			if w.conn == nil {
				w.mu.Unlock()
				return nil
			}

			_, msg, err := w.conn.ReadMessage()
			w.mu.Unlock()

			if err != nil {
				return err
			}

			// Reset deadline when receiving any message
			w.mu.Lock()
			if w.conn != nil {
				_ = w.conn.SetReadDeadline(time.Time{})
			}
			w.mu.Unlock()

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
						w.config.Lock()
						w.config.LocationID = locationID
						w.config.Unlock()

						length, err := StringToUint64Varint(len(locationID))
						if err != nil {
							log.Printf("Failed to convert locationID to varint: %v", err)
						}

						fmt.Printf("%d %s\n", length, locationID)
					}

					if topicID, ok := message["topicID"].(string); ok {
						w.config.Lock()
						w.config.TopicID = topicID
						w.config.Unlock()
						length, err := StringToUint64Varint(len(topicID))
						if err != nil {
							log.Printf("Failed to convert topicID to varint: %v", err)
						}

						fmt.Printf("%d %s\n", length, topicID)
					}
				}
			}

			log.Printf("Received JSON: %s", msg)

			// Forward message to Chrome via CDP
			// TODO: Implement message forwarding
		}
	}
}

// startPingPong sends periodic pings to keep the connection alive
func (w *WSClient) startPingPong(stop chan struct{}) {
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

			w.mu.Lock()
			if w.conn == nil {
				w.mu.Unlock()
				return
			}

			if err := w.conn.WriteMessage(websocket.TextMessage, pingBytes); err != nil {
				log.Printf("Failed to send ping: %v", err)
				w.mu.Unlock()
				return
			}

			_ = w.conn.SetReadDeadline(time.Now().Add(pongWait))
			w.mu.Unlock()

		case <-stop:
			return
		case <-w.done:
			return
		}
	}
}

// Close closes the WebSocket connection
func (w *WSClient) Close() {
	w.mu.Lock()
	defer w.mu.Unlock()

	select {
	case <-w.done:
		// Already closed
		return
	default:
		close(w.done)
	}

	if w.conn != nil {
		w.conn.Close()
		w.conn = nil
	}
}
