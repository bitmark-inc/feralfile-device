package main

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

var errRelayerAlreadyConnected = fmt.Errorf("relayer is already connected")

const (
	RELAYER_PING_INTERVAL = 15 * time.Second
	RELAYER_PONG_WAIT     = 10 * time.Second
)

type RelayerConfig struct {
	Endpoint string `json:"endpoint"`
	APIKey   string `json:"apiKey"`
}

type RelayerHandler func(ctx context.Context, data map[string]interface{}) error

// RelayerClient handles Relayer connection to relay server
type RelayerClient struct {
	sync.Mutex

	config   *RelayerConfig
	conn     *websocket.Conn
	done     chan struct{}
	logger   *zap.Logger
	handlers []RelayerHandler
}

// NewRelayerClient creates a new Relayer client
func NewRelayerClient(config *RelayerConfig, logger *zap.Logger) *RelayerClient {
	return &RelayerClient{
		config:   config,
		done:     make(chan struct{}),
		logger:   logger,
		handlers: []RelayerHandler{},
	}
}

// RetriableConnect connects to the Relayer server and listens for messages
// with exponential backoff
func (r *RelayerClient) RetriableConnect(ctx context.Context) error {
	bo := backoff.NewExponentialBackOff()
	bo.InitialInterval = 5 * time.Second
	bo.Multiplier = 2
	bo.MaxElapsedTime = 30 * time.Second

	var err error
	ops := func() error {
		err = r.Connect(ctx)
		if err == errRelayerAlreadyConnected {
			return nil
		}
		return err
	}

	_ = backoff.Retry(ops, bo)
	return err
}

// Connect connects to the Relayer server and listens for messages
func (r *RelayerClient) Connect(ctx context.Context) error {
	// Ensure the relayer is not connected
	r.Lock()
	if r.conn != nil {
		r.Unlock()
		return errRelayerAlreadyConnected
	}
	r.Unlock()

	r.logger.Info("Connecting to Relayer", zap.String("endpoint", r.config.Endpoint))

	// Create URL with locationID and topicID if available
	connectURL := r.config.Endpoint

	if r.config.APIKey != "" {
		connectURL += fmt.Sprintf("/api/connection?apiKey=%s", r.config.APIKey)
	}

	state := GetState()
	if state.RelayerReadyConnecting() {
		connectURL += fmt.Sprintf("&locationID=%s&topicID=%s", state.Relayer.LocationID, state.Relayer.TopicID)
	}

	r.logger.Info("Connecting to WebSocket", zap.String("url", connectURL))
	dialer := websocket.DefaultDialer

	r.Lock()
	conn, _, err := dialer.Dial(connectURL, nil)

	if err != nil {
		r.Unlock()
		return err
	}

	r.conn = conn
	r.Unlock()

	conn.SetPongHandler(func(appData string) error {
		r.logger.Info("Received pong")
		conn.SetReadDeadline(time.Time{})
		time.Sleep(RELAYER_PING_INTERVAL)
		r.startPing()
		return nil
	})
	r.startPing()

	// Handle background tasks
	r.background(ctx)

	r.logger.Info("Connected to Relayer")

	return nil
}

func (r *RelayerClient) OnRelayerMessage(f RelayerHandler) {
	r.Lock()
	defer r.Unlock()
	r.handlers = append(r.handlers, f)
}

func (r *RelayerClient) RemoveRelayerMessage(f RelayerHandler) {
	r.Lock()
	defer r.Unlock()

	for i, handler := range r.handlers {
		if fmt.Sprintf("%p", handler) == fmt.Sprintf("%p", f) {
			r.handlers = append(r.handlers[:i], r.handlers[i+1:]...)
			break
		}
	}
}

func (r *RelayerClient) background(ctx context.Context) {
	go func() {
		r.logger.Info("Relayer background goroutine started")
		for {
			select {
			case <-ctx.Done():
				r.logger.Info("Closing WebSocket connection due to context cancellation")
				r.Close()
				return
			case <-r.done:
				// Exit if closed manually
				r.logger.Info("Context handler exiting due to manual close")
				return
			default:
				r.Lock()
				if r.conn == nil {
					r.Unlock()
					return
				}

				conn := r.conn
				r.Unlock()
				_, msg, err := conn.ReadMessage()
				if err != nil {
					r.logger.Error("Failed to read message", zap.Error(err))
					continue
				}

				// Check JSON
				var data map[string]interface{}
				if err := json.Unmarshal(msg, &data); err != nil {
					r.logger.Error("Invalid JSON received", zap.ByteString("message", msg))
					continue
				}

				// Forward message to handlers
				for _, handler := range r.handlers {
					if err := handler(ctx, data); err != nil {
						r.logger.Error("Failed to handle message", zap.Error(err))
					}
				}
			}
		}
	}()
}

// Send sends a message to the Relayer server
func (r *RelayerClient) Send(ctx context.Context, data interface{}) error {
	r.Lock()
	defer r.Unlock()

	r.logger.Info("Sending message to Relayer", zap.Any("data", data))

	return r.conn.WriteJSON(data)
}

// startPingPong sends periodic pings to keep the connection alive
func (r *RelayerClient) startPing() {
	r.Lock()
	if r.conn == nil {
		r.Unlock()
		return
	}

	r.logger.Info("Sending ping")

	if err := r.conn.WriteMessage(websocket.PingMessage, []byte("ping")); err != nil {
		r.logger.Error("Failed to send ping", zap.Error(err))
		r.Unlock()
		return
	}

	r.Unlock()
	r.conn.SetReadDeadline(time.Now().Add(RELAYER_PONG_WAIT))
}

// Close closes the Relayer connection
func (r *RelayerClient) Close() {
	r.Lock()
	defer r.Unlock()

	r.logger.Info("Closing Relayer connection")

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
		r.logger.Info("Relayer connection closed")
	}
}
