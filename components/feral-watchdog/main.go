package main

import (
	"context"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"go.uber.org/zap"
)

const (
	// Timeouts
	SHUTDOWN_TIMEOUT  = 2 * time.Second
	GOROUTINE_TIMEOUT = 1500 * time.Millisecond // 1.5 seconds
	DEBUG_MODE        = true
)

func main() {
	// Initialize logger
	logger, err := newLogger(DEBUG_MODE)
	if err != nil {
		panic("Failed to initialize logger: " + err.Error())
	}
	defer logger.Sync()

	logger.Info("Starting feral-watchdog daemon")
	logger.Info("Logs are being saved to", zap.String("logFile", LOG_FILE_PATH))

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle signals for graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigCh
		logger.Info("Received signal, initiating shutdown...",
			zap.String("signal", sig.String()))
		cancel()

		// Force exit if graceful shutdown takes too long
		time.Sleep(SHUTDOWN_TIMEOUT)
		logger.Error("Shutdown timed out, forcing exit...",
			zap.Duration("timeout", SHUTDOWN_TIMEOUT))
		os.Exit(1)
	}()

	// Load configuration
	config, err := LoadConfig(DEBUG_MODE, logger)
	if err != nil {
		logger.Fatal("Failed to load configuration", zap.Error(err))
	}

	// Create a WaitGroup to track all the monitoring goroutines
	var wg sync.WaitGroup

	// Start systemd watchdog
	systemdWatchdog := NewSystemdWatchdog(logger)
	wg.Add(1)
	go func() {
		defer wg.Done()
		systemdWatchdog.Start(ctx)
	}()

	// Start CDP monitor
	cdpMonitor := NewCDPMonitor(config.CDPConfig, logger)
	wg.Add(1)
	go func() {
		defer wg.Done()
		cdpMonitor.Start(ctx)
	}()

	// Start RAM monitor
	ramMonitor := NewRAMMonitor(logger)
	wg.Add(1)
	go func() {
		defer wg.Done()
		ramMonitor.Start(ctx)
	}()

	// Start Disk monitor
	diskMonitor := NewDiskMonitor(logger)
	wg.Add(1)
	go func() {
		defer wg.Done()
		diskMonitor.Start(ctx)
	}()

	// Start GPU monitor
	gpuMonitor := NewGPUMonitor(logger)
	wg.Add(1)
	go func() {
		defer wg.Done()
		gpuMonitor.Start(ctx)
	}()

	// Notify systemd that we're ready
	if err := systemdWatchdog.NotifyReady(); err != nil {
		logger.Warn("Failed to notify systemd, but continuing", zap.Error(err))
	}

	// Block until context is done (cancel is called)
	<-ctx.Done()
	logger.Info("Shutdown signal received, cleaning up...")

	// Wait for all goroutines to finish (with timeout)
	waitCh := make(chan struct{})
	go func() {
		wg.Wait()
		close(waitCh)
	}()

	select {
	case <-waitCh:
		logger.Info("All goroutines have terminated cleanly")
	case <-time.After(GOROUTINE_TIMEOUT / 2):
		logger.Warn("Some goroutines did not terminate in time")
	}

	logger.Info("feral-watchdog daemon shutdown complete")
}
