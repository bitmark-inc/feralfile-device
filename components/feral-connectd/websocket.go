package main

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

type RelayerConfig struct {
	URL        string
	APIKey     string
	LocationID string
	TopicID    string
}

// RelayerClient handles WebSocket connection to relay server
type RelayerClient struct {
	config *RelayerConfig
	cdp    *CDPClient
	conn   *websocket.Conn
	mu     sync.Mutex
	done   chan struct{}
	logger *zap.Logger
}

// NewRelayerClient creates a new WebSocket client
func NewRelayerClient(config *RelayerConfig, cdp *CDPClient, logger *zap.Logger) *RelayerClient {
	return &RelayerClient{
		config: config,
		cdp:    cdp,
		done:   make(chan struct{}),
		logger: logger,
	}
}

// ConnectAndListen connects to the WebSocket server and listens for messages
func (r *RelayerClient) ConnectAndListen(ctx context.Context) error {
	// Create URL with locationID and topicID if available
	connectURL := r.config.URL

	if r.config.APIKey != "" {
		connectURL += fmt.Sprintf("/api/connection?apiKey=%s", r.config.APIKey)
	}

	if r.config.LocationID != "" {
		connectURL += fmt.Sprintf("&locationID=%s", r.config.LocationID)
	}

	if r.config.TopicID != "" {
		connectURL += fmt.Sprintf("&topicID=%s", r.config.TopicID)
	}

	r.logger.Info("Connecting to WebSocket", zap.String("url", connectURL))
	dialer := websocket.DefaultDialer

	r.mu.Lock()
	conn, _, err := dialer.Dial(connectURL, nil)
	if err != nil {
		r.mu.Unlock()
		return err
	}

	r.conn = conn
	r.mu.Unlock()
	defer func() {
		r.mu.Lock()
		if r.conn != nil {
			r.conn.Close()
			r.conn = nil
		}
		r.mu.Unlock()
	}()

	r.logger.Info("Connected to WebSocket")

	// WS ping/pong
	stopPing := make(chan struct{})
	go r.startPingPong(stopPing)
	defer close(stopPing)

	// Handle context cancellation
	go func() {
		select {
		case <-ctx.Done():
			r.logger.Info("Closing WebSocket connection due to context cancellation")
			r.Close()
		case <-r.done:
			// Exit if closed manually
			r.logger.Info("Context handler exiting due to manual close")
		}
	}()

	// Read message from relay server
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-r.done:
			return nil
		default:
			r.mu.Lock()
			if r.conn == nil {
				r.mu.Unlock()
				return nil
			}

			_, msg, err := r.conn.ReadMessage()
			r.mu.Unlock()

			if err != nil {
				return err
			}

			// Reset deadline when receiving any message
			r.mu.Lock()
			if r.conn != nil {
				_ = r.conn.SetReadDeadline(time.Time{})
			}
			r.mu.Unlock()

			// Check JSON
			var data map[string]interface{}
			if err := json.Unmarshal(msg, &data); err != nil {
				r.logger.Error("Invalid JSON received", zap.ByteString("message", msg))
				continue
			}

			// Get message ID for logging
			messageID, _ := data["messageID"].(string)

			// Handle system message to get locationID and topicID
			if messageID == "system" {
				if message, ok := data["message"].(map[string]interface{}); ok {
					if locationID, ok := message["locationID"].(string); ok {
						r.config.LocationID = locationID
						length, err := ConvertToUint64Varint(len(locationID))
						if err != nil {
							r.logger.Error("Failed to convert locationID to varint",
								zap.Error(err), zap.String("locationID", locationID))
						}

						fmt.Printf("%d %s\n", length, locationID)
					}

					if topicID, ok := message["topicID"].(string); ok {
						r.config.TopicID = topicID
						length, err := ConvertToUint64Varint(len(topicID))
						if err != nil {
							r.logger.Error("Failed to convert topicID to varint",
								zap.Error(err), zap.String("topicID", topicID))
						}

						fmt.Printf("%d %s\n", length, topicID)
					}
				}
			}

			r.logger.Debug("Received WebSocket message",
				zap.String("messageID", messageID),
				zap.Any("data", data))

			// Forward message to Chrome via CDP
			// TODO: Implement message forwarding
		}
	}
}

// startPingPong sends periodic pings to keep the connection alive
func (r *RelayerClient) startPingPong(stop chan struct{}) {
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

			r.mu.Lock()
			if r.conn == nil {
				r.mu.Unlock()
				return
			}

			if err := r.conn.WriteMessage(websocket.TextMessage, pingBytes); err != nil {
				r.logger.Error("Failed to send ping", zap.Error(err))
				r.mu.Unlock()
				return
			}

			_ = r.conn.SetReadDeadline(time.Now().Add(pongWait))
			r.mu.Unlock()
			r.logger.Debug("Sent ping")

		case <-stop:
			r.logger.Debug("Ping/pong loop stopped")
			return
		case <-r.done:
			r.logger.Debug("Ping/pong loop stopped due to connection close")
			return
		}
	}
}

// Close closes the WebSocket connection
func (r *RelayerClient) Close() {
	r.mu.Lock()
	defer r.mu.Unlock()

	select {
	case <-r.done:
		// Already closed
		return
	default:
		close(r.done)
	}

	if r.conn != nil {
		r.conn.Close()
		r.conn = nil
		r.logger.Info("WebSocket connection closed")
	}
}
