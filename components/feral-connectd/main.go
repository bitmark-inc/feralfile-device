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
	maxRetries                 = 4
	baseRetryWebsocketInterval = 3 * time.Second
	watchdogInterval           = 15 * time.Second
	shutdownTimeout            = 1 * time.Second
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

	retryCount := 1
	isConnectSuccess := make(chan bool, 2)
	for {
		if retryCount > maxRetries {
			logger.Error("Max retries reached, exiting")
			cancel()
			time.Sleep(shutdownTimeout)
			os.Exit(1)
		}

		logger.Info(">>>>>Connecting to WebSocket...", zap.Int("retry", retryCount))
		go func() {
			select {
			case <-ctx.Done():
				logger.Info("Closing connectSuccess listening due to context cancellation.")
				return
			case success := <-isConnectSuccess:
				if success {
					retryCount = 1
				}
			}
		}()

		err = wsClient.ConnectAndListen(ctx, isConnectSuccess)
		if err != nil {
			logger.Error("Failed to connect to WebSocket", zap.Error(err))
		}

		retryCount++
		time.Sleep(baseRetryWebsocketInterval * time.Duration(retryCount))

	}
}
