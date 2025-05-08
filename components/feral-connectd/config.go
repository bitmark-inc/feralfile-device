package main

import (
	"log"
	"os"
	"strconv"
	"sync"
)

// Configuration for CDP connection
type Config struct {
	sync.RWMutex
	CDPHost string
	CDPPort int

	WsURL    string
	WsAPIKey string

	LocationID string
	TopicID    string
}

// Environment variable names
const (
	ENV_CDP_PORT   = "CDP_PORT"
	ENV_WS_API_KEY = "WS_API_KEY"
	ENV_WS_URL     = "WS_URL"

	// Default values
	CDP_HOST         = "http://127.0.0.1"
	DEFAULT_CDP_PORT = 9222
	DEFAULT_WS_URL   = "wss://tv-cast-coordination.bitmark-development.workers.dev"
)

// LoadConfig reads environment variables and returns a config struct
func LoadConfig() *Config {
	cdpPort := DEFAULT_CDP_PORT
	if portStr := os.Getenv(ENV_CDP_PORT); portStr != "" {
		if port, err := strconv.Atoi(portStr); err == nil && port > 0 {
			cdpPort = port
		} else if err != nil {
			log.Printf("Invalid %s value: %v, using default: %d", ENV_CDP_PORT, err, DEFAULT_CDP_PORT)
		}
	}

	wsApiKey := os.Getenv(ENV_WS_API_KEY)
	if wsApiKey == "" {
		log.Fatalf("Missing %s environment variable", ENV_WS_API_KEY)
	}

	wsURL := os.Getenv(ENV_WS_URL)
	if wsURL == "" {
		wsURL = DEFAULT_WS_URL
	}

	config := &Config{
		CDPHost:  CDP_HOST,
		CDPPort:  cdpPort,
		WsAPIKey: wsApiKey,
		WsURL:    wsURL,
	}

	log.Printf("CDP configuration: %s:%d", config.CDPHost, config.CDPPort)

	return config
}
