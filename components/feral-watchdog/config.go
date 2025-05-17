package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"

	"go.uber.org/zap"
)

const (
	// Configuration file paths
	DEBUG_CONFIG_FILE = "./feral-watchdog.json"
	CONFIG_FILE       = "/home/feralfile/.config/feral-watchdog.json"
)

var (
	configLock sync.Mutex
	config     *Config
)

// Config represents the configuration for the watchdog daemon
type Config struct {
	sync.Mutex
	CDPConfig *CDPConfig `json:"cdp"`
}

// CDPConfig holds the configuration for the Chrome DevTools Protocol
type CDPConfig struct {
	Endpoint string `json:"endpoint"`
}

// LoadConfig loads the configuration from a JSON file
func LoadConfig(debug bool, logger *zap.Logger) (*Config, error) {
	fp := getConfigFile(debug)
	logger.Info("Loading config", zap.String("file", fp))

	// Try to read the file
	data, err := os.ReadFile(fp)
	if os.IsNotExist(err) {
		// If the file doesn't exist, create a default config with default CDP endpoint
		logger.Warn("Config file not found, using default configuration", zap.Error(err))
		return &Config{
			CDPConfig: &CDPConfig{
				Endpoint: "http://localhost:9222",
			},
		}, nil
	} else if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	// Lock during unmarshaling to prevent concurrent access
	configLock.Lock()
	defer configLock.Unlock()

	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	// Set default endpoint if not provided
	if c.CDPConfig == nil {
		c.CDPConfig = &CDPConfig{
			Endpoint: "http://localhost:9222",
		}
	} else if c.CDPConfig.Endpoint == "" {
		c.CDPConfig.Endpoint = "http://localhost:9222"
	}

	config = &c
	return config, nil
}

// getConfigFile returns the appropriate config file path
func getConfigFile(debug bool) string {
	// Check if running in debug mode
	if debug {
		return DEBUG_CONFIG_FILE
	}
	return CONFIG_FILE
}
