package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.uber.org/zap"
)

// Retry config
const (
	maxRetries       = 3
	baseDelay        = 3 * time.Second
	watchdogInterval = 15 * time.Second
	shutdownTimeout  = 1 * time.Second
)

func main() {
	// Initialize logger with debug enabled for development
	logger, err := New(true)
	if err != nil {
		panic("Failed to initialize logger: " + err.Error())
	}
	defer logger.Sync()

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle signals for graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	go func() {
		sig := <-sigCh
		logger.Info("Received signal, initiating shutdown...",
			zap.String("signal", sig.String()))
		cancel()

		time.Sleep(shutdownTimeout)
		logger.Error("Shutdown timed out, forcing exit...",
			zap.Duration("timeout", shutdownTimeout))
		os.Exit(1)
	}()

	// Load configuration
	config := LoadConfig(logger)

	// Initialize CDP client
	cdpClient := NewCDPClient(config.CDPEndpoint, logger)
	err = cdpClient.InitCDP(ctx)
	if err != nil {
		logger.Fatal("CDP init failed", zap.Error(err))
	}
	defer cdpClient.Close()

	// Start watchdog in a goroutine
	watchdog := NewWatchdog(watchdogInterval, logger)
	go watchdog.Start(ctx)
	defer watchdog.Stop()

	// Initialize Relayer client
	wsConfig := &RelayerConfig{
		URL:        config.WsURL,
		APIKey:     config.WsAPIKey,
		LocationID: config.LocationID,
		TopicID:    config.TopicID,
	}
	wsClient := NewRelayerClient(wsConfig, cdpClient, logger)

	// Main connection loop - keeps trying to reconnect indefinitely
	for {
		select {
		case <-ctx.Done():
			logger.Info("Shutting down...")
			return
		default:
			// Try to connect and listen with retry logic for each connection
			if err := connectWithRetries(ctx, wsClient, logger); err != nil {
				logger.Fatal("Max connection retries exceeded. Shutting down...", zap.Error(err))
				return
			}

			logger.Info("Connection cycle completed, restarting connection process...")
		}
	}
}

// connectWithRetries handles the retry logic for a single connection attempt
func connectWithRetries(ctx context.Context, wsClient *RelayerClient, logger *zap.Logger) error {
	retriesLeft := maxRetries

	for retriesLeft > 0 {
		// Try to connect
		err := wsClient.ConnectAndListen(ctx)

		// If context canceled or no error, we're done
		if ctx.Err() != nil {
			return nil // Context canceled, return without error
		}

		if err == nil {
			// Successful connection that ended cleanly
			logger.Info("WebSocket connection ended normally, will reconnect")
			return nil
		}

		// We got an error, retry
		retriesLeft--
		logger.Error("WebSocket connection failed",
			zap.Error(err),
			zap.Int("retriesLeft", retriesLeft))

		if retriesLeft >= 0 {
			// Calculate delay with backoff
			delay := baseDelay * time.Duration(maxRetries-retriesLeft)
			logger.Info("Retrying connection...",
				zap.Duration("delay", delay),
				zap.Int("retriesLeft", retriesLeft),
				zap.Int("maxRetries", maxRetries))

			// Wait for delay or context cancellation
			select {
			case <-time.After(delay):
				// Continue to retry
			case <-ctx.Done():
				return nil // Context canceled during wait
			}
		} else {
			return err // Out of retries, return the last error
		}
	}

	return nil // Should never reach here
}
