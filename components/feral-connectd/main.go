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

	// Connection retry loop
	retries := 0

	for {
		select {
		case <-ctx.Done():
			logger.Info("Shutting down...")
			return
		default:
			err := wsClient.ConnectAndListen(ctx)
			if err != nil {
				logger.Error("Relayer error", zap.Error(err))
				retries++
				if retries > maxRetries {
					logger.Fatal("Max retries exceeded. Shutting down...")
				}

				delay := baseDelay * time.Duration(retries)
				logger.Info("Reconnecting...", zap.Duration("delay", delay))

				select {
				case <-time.After(delay):
					// Continue retry loop
				case <-ctx.Done():
					logger.Info("Shutting down during reconnect...")
					return
				}
			} else {
				// Reset retries on successful connection that ended normally
				retries = 0
			}
		}
	}
}
