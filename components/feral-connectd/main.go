package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.uber.org/zap"
)

const (
	WATCHDOG_INTERVAL = 15 * time.Second
	SHUTDOWN_TIMEOUT  = 1 * time.Second
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

		time.Sleep(SHUTDOWN_TIMEOUT)
		logger.Error("Shutdown timed out, forcing exit...",
			zap.Duration("timeout", SHUTDOWN_TIMEOUT))
		os.Exit(1)
	}()

	// Load configuration
	config, err := LoadConfig(logger)
	if err != nil {
		logger.Fatal("Failed to load configuration", zap.Error(err))
	}

	// Load state
	state, err := LoadState(logger)
	if err != nil {
		logger.Fatal("Failed to load state", zap.Error(err))
	}

	// Initialize CDP client
	cdpClient := NewCDPClient(config.CDPConfig, logger)
	err = cdpClient.InitCDP(ctx)
	if err != nil {
		logger.Fatal("CDP init failed", zap.Error(err))
	}
	defer cdpClient.Close()

	// Start watchdog in a goroutine
	watchdog := NewWatchdog(WATCHDOG_INTERVAL, logger)
	go watchdog.Start(ctx)
	defer watchdog.Stop()

	// Initialize Relayer client
	relayerClient := NewRelayerClient(config.RelayerConfig, logger)
	defer relayerClient.Close()

	// Connect to Relayer if ready
	if state.RelayerChanReady() {
		err = relayerClient.RetriableConnect(ctx)
		if err != nil {
			logger.Fatal("Failed to connect to relayer", zap.Error(err))
		}
	}

	// Initialize DBus client
	dbusClient := NewDBusClient(ctx, logger, relayerClient)
	err = dbusClient.Start()
	if err != nil {
		logger.Fatal("DBus init failed", zap.Error(err))
	}
	defer dbusClient.Stop()

	// Initialize command handler
	cmd := NewCommandHandler(cdpClient, logger)

	// Initialize Mediator
	mediator := NewMediator(relayerClient, dbusClient, cdpClient, cmd, logger)
	mediator.Start()
	defer mediator.Stop()

	<-ctx.Done()
}
