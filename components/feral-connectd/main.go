package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Retry config
const (
	maxRetries       = 3
	baseDelay        = 3 * time.Second
	watchdogInterval = 15 * time.Second
	shutdownTimeout  = 3 * time.Second
)

func main() {
	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle signals for graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	go func() {
		sig := <-sigCh
		log.Printf("Received signal: %v, initiating shutdown...", sig)
		cancel()

		time.Sleep(shutdownTimeout)
		log.Printf("Shutdown timed out after %v, forcing exit...", shutdownTimeout)
		os.Exit(1)
	}()

	// Load configuration
	config := LoadConfig()

	// Initialize CDP client
	cdpClient := NewCDPClient(config)
	err := cdpClient.InitCDP(ctx)
	if err != nil {
		log.Fatalf("CDP init failed: %v", err)
	}
	defer cdpClient.Close()

	// Test CDP connection
	// Navigate to YouTube
	err = cdpClient.SendCDPRequest(NavigateMethod, map[string]interface{}{
		"url": "https://www.youtube.com",
	})
	if err != nil {
		log.Printf("Failed to navigate to YouTube: %v", err)
	}

	// Evaluate JavaScript: console.log Hello World
	err = cdpClient.SendCDPRequest(EvaluateMethod, map[string]interface{}{
		"expression": "console.log('Hello World')",
	})
	if err != nil {
		log.Printf("Failed to evaluate JavaScript: %v", err)
	}

	// Start watchdog in a goroutine
	watchdog := NewWatchdog(watchdogInterval)
	go watchdog.Start(ctx)
	defer watchdog.Stop()

	// Initialize WebSocket client
	wsClient := NewWSClient(config, cdpClient)

	// Connection retry loop
	retries := 0

	for {
		select {
		case <-ctx.Done():
			log.Println("Shutting down...")
			return
		default:
			err := wsClient.ConnectAndListen(ctx)
			if err != nil {
				log.Printf("WebSocket error: %v", err)
				retries++
				if retries > maxRetries {
					log.Fatalf("Max retries exceeded. Shutting down...")
				}

				delay := baseDelay * time.Duration(retries)
				log.Printf("Reconnecting in %v...", delay)

				select {
				case <-time.After(delay):
					// Continue retry loop
				case <-ctx.Done():
					log.Println("Shutting down during reconnect...")
					return
				}
			} else {
				// Reset retries on successful connection that ended normally
				retries = 0
			}
		}
	}
}
