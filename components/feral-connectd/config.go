package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"

	"go.uber.org/zap"
)

// Configuration for all components
type Config struct {
	sync.RWMutex
	CDPEndpoint string

	WsURL    string
	WsAPIKey string

	LocationID string
	TopicID    string
}

// CredentialsFile is the structure of the JSON credentials file
type CredentialsFile struct {
	Relayer struct {
		Endpoint string `json:"endpoint"`
		APIKey   string `json:"apiKey"`
	} `json:"relayer"`
	CDP struct {
		Endpoint string `json:"endpoint"`
	} `json:"cdp"`
}

const (
	CREDS_FILE_DIR = "/var/lib/feralfile/creds.json"
)

// LoadCredentials loads credentials from a JSON file
func LoadCredentials(logger *zap.Logger) (*CredentialsFile, error) {
	data, err := os.ReadFile(CREDS_FILE_DIR)
	if err != nil {
		return nil, fmt.Errorf("failed to read credentials file: %w", err)
	}

	var creds CredentialsFile
	if err := json.Unmarshal(data, &creds); err != nil {
		return nil, fmt.Errorf("failed to parse credentials file: %w", err)
	}

	return &creds, nil
}

// LoadConfig reads the configuration from credentials file or environment variables
func LoadConfig(logger *zap.Logger) *Config {
	// Load credentials
	creds, err := LoadCredentials(logger)
	if err != nil {
		logger.Fatal("Failed to load credentials", zap.Error(err))
	}

	config := &Config{
		CDPEndpoint: creds.CDP.Endpoint,
		WsAPIKey:    creds.Relayer.APIKey,
		WsURL:       creds.Relayer.Endpoint,
	}

	logger.Info("CDP configuration loaded",
		zap.String("endpoint", config.CDPEndpoint),
		zap.String("ws_url", config.WsURL))

	return config
}
