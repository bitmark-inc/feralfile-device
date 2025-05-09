package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

const (
	STATE_FILE = "/home/feralfile/.state/connectd.state"
)

var (
	stateLock sync.Mutex
	state     *State
)

type State struct {
	sync.Mutex
	ConnectedDevice *Device `json:"connectedDevice"`
	Relayer         struct {
		LocationID string `json:"locationId"`
		TopicID    string `json:"topicId"`
	} `json:"relayer"`
}

func (c *State) RelayerReadyConnecting() bool {
	return c.Relayer.LocationID != "" && c.Relayer.TopicID != ""
}

// LoadState loads state from file or creates a new one if file doesn't exist
func LoadState() (*State, error) {
	// Ensure directory exists
	stateDir := filepath.Dir(STATE_FILE)
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return state, fmt.Errorf("failed to create state directory: %w", err)
	}

	// Try to read the file
	data, err := os.ReadFile(STATE_FILE)
	if os.IsNotExist(err) {
		// File doesn't exist, return empty state
		return state, nil
	} else if err != nil {
		return state, fmt.Errorf("failed to read state file: %w", err)
	}

	// Lock during unmarshaling to prevent concurrent access
	stateLock.Lock()
	defer stateLock.Unlock()

	if err := json.Unmarshal(data, state); err != nil {
		return state, fmt.Errorf("failed to unmarshal state file: %w", err)
	}
	return state, nil
}

func (s *State) Save() error {
	s.Lock()
	defer s.Unlock()

	// Ensure directory exists
	stateDir := filepath.Dir(STATE_FILE)
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return fmt.Errorf("failed to create state directory: %w", err)
	}

	data, err := json.Marshal(s)
	if err != nil {
		return fmt.Errorf("failed to marshal state: %w", err)
	}

	// Write to a temporary file first, then rename for atomic updates
	tempFile := STATE_FILE + ".tmp"
	if err := os.WriteFile(tempFile, data, 0644); err != nil {
		return fmt.Errorf("failed to write state file: %w", err)
	}

	if err := os.Rename(tempFile, STATE_FILE); err != nil {
		return fmt.Errorf("failed to finalize state file: %w", err)
	}

	return nil
}

// GetState returns the current state safely
func GetState() *State {
	stateLock.Lock()
	defer stateLock.Unlock()

	if state == nil {
		state = &State{}
	}
	return state
}
