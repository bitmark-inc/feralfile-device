package main

import (
	"encoding/json"
	"log"
	"os"
	"os/exec"
)

type State struct {
	Paired bool `json:"paired"`
}

func main() {
	statePath := "/var/lib/feral/state.json"

	// Check if state file exists
	data, err := os.ReadFile(statePath)
	if err != nil {
		// File doesn't exist or can't be read, isolate to setup.target
		runSystemctl("isolate", "setup.target")
		return
	}

	// Parse state.json
	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		log.Printf("Error parsing state.json: %v", err)
		// If we can't parse, default to setup.target
		runSystemctl("isolate", "setup.target")
		return
	}

	// Check paired status
	if !state.Paired {
		runSystemctl("isolate", "setup.target")
	} else {
		runSystemctl("isolate", "kiosk.target")
	}
}

func runSystemctl(args ...string) {
	cmd := exec.Command("systemctl", args...)
	if err := cmd.Run(); err != nil {
		log.Printf("Error running systemctl %v: %v", args, err)
	}
}
