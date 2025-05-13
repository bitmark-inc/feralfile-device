package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"

	"go.uber.org/zap"
)

var (
	CONFIG_FILE       = "/home/feralfile/.config/connectd.json"
	DEBUG_CONFIG_FILE = "./connectd.json"

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
	fp := GetConfigFile()
	logger.Info("Loading config", zap.String("file", fp))

	// Try to read the file
	data, err := os.ReadFile(fp)
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

func GetConfigFile() string {
	fp := CONFIG_FILE
	if DEBUG {
		fp = DEBUG_CONFIG_FILE
	}
	return fp
}
