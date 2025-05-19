package main

import (
	"os/exec"
	"sync"

	"go.uber.org/zap"
)

// CommandHandler implements system health checking and remediation actions
type CommandHandler struct {
	logger            *zap.Logger
	mu                sync.Mutex
	isRestartingKiosk bool
	isCleaningDisk    bool
}

func NewCommandHandler(logger *zap.Logger) *CommandHandler {
	return &CommandHandler{
		logger: logger,
	}
}

// restartKiosk attempts to restart the chromium-kiosk service
func (c *CommandHandler) restartKiosk() {
	c.mu.Lock()
	if c.isRestartingKiosk {
		c.mu.Unlock()
		return
	}

	c.isRestartingKiosk = true
	c.mu.Unlock()

	defer func() {
		c.mu.Lock()
		c.isRestartingKiosk = false
		c.mu.Unlock()
	}()

	cmd := exec.Command("sudo", "systemctl", "restart", "chromium-kiosk.service")
	if output, err := cmd.CombinedOutput(); err != nil {
		c.logger.Error("Failed to restart chromium-kiosk service",
			zap.Error(err),
			zap.ByteString("output", output))
	} else {
		c.logger.Info("Successfully restarted chromium-kiosk service")
	}
}

// rebootSystem initiates a system reboot
func (c *CommandHandler) rebootSystem() {
	c.mu.Lock()
	defer c.mu.Unlock()

	cmd := exec.Command("sudo", "systemctl", "reboot")
	if output, err := cmd.CombinedOutput(); err != nil {
		c.logger.Error("Failed to reboot system",
			zap.Error(err),
			zap.ByteString("output", output))
	}
}

func (c *CommandHandler) cleanupDiskSpace() {
	c.mu.Lock()
	if c.isCleaningDisk {
		c.mu.Unlock()
		return
	}

	c.isCleaningDisk = true
	c.mu.Unlock()

	defer func() {
		c.mu.Lock()
		c.isCleaningDisk = false
		c.mu.Unlock()
	}()

	// Cleanup temp folder
	cmd := exec.Command("sudo", "find", TEMP_FOLDER_PATH, "-depth", "-delete")
	if output, err := cmd.CombinedOutput(); err != nil {
		c.logger.Error("Failed to cleanup temp folder",
			zap.Error(err),
			zap.ByteString("output", output))
	}

	// Clean pacman cache
	cmd = exec.Command("sudo", "pacman", "-Sc", "--noconfirm")
	if output, err := cmd.CombinedOutput(); err != nil {
		c.logger.Error("Failed to clean pacman cache",
			zap.Error(err),
			zap.ByteString("output", output))
	}
}
