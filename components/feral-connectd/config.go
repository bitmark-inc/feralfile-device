package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"go.uber.org/zap"
)

var (
	CONFIG_FILE = "/home/feralfile/.config/connectd.json"

	configLock sync.Mutex
	config     *Config
)

// Configuration for all components
type Config struct {
	sync.Mutex
	CDPConfig     *CDPConfig     `json:"cdp"`
	RelayerConfig *RelayerConfig `json:"relayer"`
}

// LoadConfig loads the configuration from a JSON file
func LoadConfig(logger *zap.Logger) (*Config, error) {
	logger.Info("Loading config", zap.String("file", CONFIG_FILE))

	// Try to read the file
	data, err := os.ReadFile(CONFIG_FILE)
	if os.IsNotExist(err) {
		return nil, fmt.Errorf("config file not found: %w", err)
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

	config = &c
	return config, nil
}

// PersistConfig persists the configuration to a JSON file
func (c *Config) Save() error {
	c.Lock()
	defer c.Unlock()

	// Ensure directory exists
	configDir := filepath.Dir(CONFIG_FILE)
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	data, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal configuration: %w", err)
	}

	// Write to a temporary file first, then rename for atomic updates
	tempFile := CONFIG_FILE + ".tmp"
	if err := os.WriteFile(tempFile, data, 0644); err != nil {
		return fmt.Errorf("failed to write configuration: %w", err)
	}

	if err := os.Rename(tempFile, CONFIG_FILE); err != nil {
		return fmt.Errorf("failed to finalize configuration file: %w", err)
	}

	return nil
}

// GetConfig returns the current configuration safely
func GetConfig() *Config {
	configLock.Lock()
	defer configLock.Unlock()

	if config == nil {
		config = &Config{
			CDPConfig:     &CDPConfig{},
			RelayerConfig: &RelayerConfig{},
		}
	}
	return config
}
