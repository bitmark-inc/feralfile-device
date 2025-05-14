package main

import (
	"context"
	"fmt"
	"net"
	"sync"
	"time"

	"go.uber.org/zap"
)

const (
	// Target address to ping for connectivity check
	PING_TARGET = "1.1.1.1:443"

	// Ping interval in seconds
	PING_INTERVAL = 30 * time.Second

	// Connection timeout
	PING_TIMEOUT = 2 * time.Second
)

type ConnectivityHandler func(ctx context.Context, connected bool)

type Connectivity struct {
	sync.Mutex

	ctx           context.Context
	logger        *zap.Logger
	handlers      []ConnectivityHandler
	done          chan struct{}
	lastConnected bool
}

func NewConnectivity(ctx context.Context, logger *zap.Logger) *Connectivity {
	return &Connectivity{
		ctx:           ctx,
		logger:        logger,
		handlers:      []ConnectivityHandler{},
		done:          make(chan struct{}),
		lastConnected: false,
	}
}

func (c *Connectivity) Start() {
	c.logger.Info("Starting Connectivity Watcher")
	c.background()
}

func (c *Connectivity) Stop() {
	select {
	case <-c.done:
		c.logger.Info("Connectivity Watcher already stopped")
	default:
		close(c.done)
	}
	c.logger.Info("Connectivity Watcher stopped")
}

func (c *Connectivity) OnConnectivityChange(handler ConnectivityHandler) {
	c.Lock()
	defer c.Unlock()
	c.handlers = append(c.handlers, handler)
}

func (c *Connectivity) RemoveConnectivityChange(h ConnectivityHandler) {
	c.Lock()
	defer c.Unlock()

	for i, handler := range c.handlers {
		if fmt.Sprintf("%p", handler) == fmt.Sprintf("%p", h) {
			c.handlers = append(c.handlers[:i], c.handlers[i+1:]...)
			break
		}
	}
}

// notifyHandlers notifies all registered handlers about connectivity status
func (c *Connectivity) notifyHandlers(ctx context.Context, connected bool) {
	c.Lock()
	handlers := make([]ConnectivityHandler, len(c.handlers))
	copy(handlers, c.handlers)
	c.Unlock()

	for _, handler := range handlers {
		go func(h ConnectivityHandler) {
			h(ctx, connected)
		}(handler)
	}
}

func (c *Connectivity) background() {
	go func() {
		c.logger.Info("Connectivity background goroutine started")

		// Check initial connectivity
		connected := c.checkConnectivity()
		c.notifyHandlers(c.ctx, connected)

		for {
			select {
			case <-c.ctx.Done():
				c.logger.Info("Connectivity background goroutine stopped")
				return
			case <-c.done:
				c.logger.Info("Connectivity Watcher stopped")
				return
			case <-time.After(PING_INTERVAL):
				c.logger.Info("Checking connectivity")
				connected := c.checkConnectivity()
				if connected != c.lastConnected {
					c.notifyHandlers(c.ctx, connected)
					c.lastConnected = connected
				}
				c.logger.Info("Connectivity check result", zap.Bool("connected", connected))
			}
		}
	}()
}

// checkConnectivity attempts to connect to the PING_TARGET address to check connectivity
func (c *Connectivity) checkConnectivity() bool {
	conn, err := net.DialTimeout("tcp", PING_TARGET, PING_TIMEOUT)
	if err != nil {
		c.logger.Warn("Connectivity check failed", zap.Error(err))
		return false
	}
	defer conn.Close()
	return true
}
