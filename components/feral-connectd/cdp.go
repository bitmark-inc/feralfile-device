package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"

	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// CDP Methods
const (
	CDP_METHOD_NAVIGATE = "Page.navigate"
	CDP_METHOD_EVALUATE = "Runtime.evaluate"
)

type CDPConfig struct {
	Endpoint string `json:"endpoint"`
}

type CDPClient struct {
	mu       sync.Mutex
	conn     *websocket.Conn
	reqID    int
	endpoint string
	isClosed bool
	logger   *zap.Logger
}

// NewCDPClient creates a new CDP client
func NewCDPClient(config *CDPConfig, logger *zap.Logger) *CDPClient {
	return &CDPClient{
		endpoint: config.Endpoint,
		reqID:    0,
		isClosed: false,
		logger:   logger,
	}
}

// InitCDP fetches WS endpoint and dials Chromium
func (c *CDPClient) InitCDP(ctx context.Context) error {
	// Fetch JSON with websocket debugger URL
	resp, err := http.Get(c.endpoint + "/json")
	if err != nil {
		return fmt.Errorf("failed to fetch debug targets: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read targets: %w", err)
	}

	var targets []struct {
		Type                 string `json:"type"`
		Title                string `json:"title"`
		WebSocketDebuggerURL string `json:"webSocketDebuggerUrl"`
	}
	if err := json.Unmarshal(body, &targets); err != nil {
		return fmt.Errorf("invalid targets format: %w", err)
	}

	// Collect all page targets
	var pageTargets []struct {
		Type                 string `json:"type"`
		Title                string `json:"title"`
		WebSocketDebuggerURL string `json:"webSocketDebuggerUrl"`
	}

	for _, t := range targets {
		if t.Type == "page" && strings.Contains(t.Title, "Feral File") {
			pageTargets = append(pageTargets, t)
		}
	}

	if len(pageTargets) == 0 {
		return fmt.Errorf("no page target found in Chromium instance")
	}

	if len(pageTargets) > 1 {
		return fmt.Errorf("multiple page targets found in Chromium instance")
	}

	// Connect to the single page target
	target := pageTargets[0]
	c.mu.Lock()
	defer c.mu.Unlock()

	c.conn, _, err = websocket.DefaultDialer.Dial(target.WebSocketDebuggerURL, nil)
	if err != nil {
		return fmt.Errorf("cdp dial error: %w", err)
	}

	c.logger.Info("Connected to Chromium CDP page target",
		zap.String("url", target.WebSocketDebuggerURL))

	// Start goroutine to handle context cancellation
	go func() {
		<-ctx.Done()
		c.logger.Info("Closing CDP connection due to context cancellation")
		c.Close()
	}()

	return nil
}

// SendCDPRequest sends a raw CDP JSON-RPC message and waits for response
func (c *CDPClient) SendCDPRequest(method string, params map[string]interface{}) (map[string]interface{}, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.isClosed || c.conn == nil {
		return nil, fmt.Errorf("CDP connection is not initialized or already closed")
	}

	c.reqID++
	msg := map[string]interface{}{
		"id":     c.reqID,
		"method": method,
		"params": params,
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return nil, fmt.Errorf("CDP marshal error: %w", err)
	}

	if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
		return nil, fmt.Errorf("CDP write error: %w", err)
	}

	// Wait for response
	_, response, err := c.conn.ReadMessage()
	if err != nil {
		return nil, fmt.Errorf("failed to read CDP response: %w", err)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(response, &resp); err != nil {
		return nil, fmt.Errorf("failed to parse CDP response: %w", err)
	}

	// Check for error in response
	if err, ok := resp["error"].(map[string]interface{}); ok {
		return nil, fmt.Errorf("CDP error: %v", err)
	}

	c.logger.Debug("CDP response received",
		zap.String("method", method),
		zap.String("response", string(response)))
	return resp, nil
}

// Close closes the CDP connection
func (c *CDPClient) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.isClosed {
		// Already closed
		return
	}

	c.isClosed = true

	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}
}
