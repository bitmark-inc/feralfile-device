package main

import (
	"encoding/json"
	"fmt"
	"os"

	"go.uber.org/zap"
)

var config *Config

// Configuration for all components
type Config struct {
	CDPConfig     *CDPConfig       `json:"cdp"`
	RelayerConfig *RelayerConfig   `json:"relayer"`
	FeralFile     *FeralFileConfig `json:"feralFile"`
	Indexer       *IndexerConfig   `json:"indexer"`
}

const (
	CONFIG_FILE_DIR = "/var/lib/feralfile/connectd.json"
)

// LoadConfig loads the configuration from a JSON file
func LoadConfig(logger *zap.Logger) (*Config, error) {
	data, err := os.ReadFile(CONFIG_FILE_DIR)
	if err != nil {
		return nil, fmt.Errorf("failed to read credentials file: %w", err)
	}

	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse credentials file: %w", err)
	}

	return config, nil
}

// PersistConfig persists the configuration to a JSON file
func PersistConfig(logger *zap.Logger) error {
	if config == nil {
		return fmt.Errorf("configuration is not loaded")
	}

	data, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal configuration: %w", err)
	}

	if err := os.WriteFile(CONFIG_FILE_DIR, data, 0644); err != nil {
		return fmt.Errorf("failed to write configuration: %w", err)
	}

	return nil
}
