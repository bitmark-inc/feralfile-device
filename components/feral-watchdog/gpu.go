package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"go.uber.org/zap"
)

const (
	// GPU monitoring configuration
	KMSG_PATH        = "/dev/kmsg"
	GPU_HANG_PATTERN = "GPU hang"
	I915_PATTERN     = "i915"
)

// GPUMonitor monitors for Intel i915 GPU hangs
type GPUMonitor struct {
	logger *zap.Logger
}

// NewGPUMonitor creates a new GPU monitor instance
func NewGPUMonitor(logger *zap.Logger) *GPUMonitor {
	return &GPUMonitor{
		logger: logger,
	}
}

// Start begins the GPU monitoring process
func (m *GPUMonitor) Start(ctx context.Context) {
	m.logger.Info("GPU: Starting GPU hang monitor",
		zap.String("kmsg_path", KMSG_PATH),
		zap.String("hang_pattern", GPU_HANG_PATTERN),
		zap.String("module_pattern", I915_PATTERN))

	for {
		select {
		case <-ctx.Done():
			m.logger.Info("GPU: Monitor shutting down")
			return
		default:
			err := m.monitorKmsg(ctx)
			if err != nil {
				m.logger.Error("GPU: Error monitoring kmsg, will retry after delay",
					zap.Error(err))
				// Wait a bit before retrying to avoid a tight loop on errors
				select {
				case <-ctx.Done():
					return
				case <-time.After(5 * time.Second):
					// Continue and try again
				}
			}
		}
	}
}

// monitorKmsg tails the kernel message log and looks for GPU hang patterns
func (m *GPUMonitor) monitorKmsg(ctx context.Context) error {
	file, err := os.Open(KMSG_PATH)
	if err != nil {
		m.logger.Warn("GPU: Could not open kmsg for monitoring", zap.Error(err))
		return fmt.Errorf("failed to open %s: %w", KMSG_PATH, err)
	}
	defer file.Close()

	m.logger.Info("GPU: Successfully opened kmsg for monitoring")
	scanner := bufio.NewScanner(file)

	// Continuously read kernel messages
	for scanner.Scan() {
		// Check if context is done
		select {
		case <-ctx.Done():
			file.Close()
			return nil
		default:
			// Continue processing
		}

		msg := scanner.Text()
		if m.isGPUHangMessage(msg) {
			m.handleGPUHang(msg)
		}
	}

	// Check if we exited the loop due to an error
	if err := scanner.Err(); err != nil {
		// If context is done, this is an expected error due to our file.Close() call
		select {
		case <-ctx.Done():
			return nil
		default:
			return fmt.Errorf("error reading %s: %w", KMSG_PATH, err)
		}
	}

	return nil
}

// isGPUHangMessage checks if a kernel message indicates a GPU hang
func (m *GPUMonitor) isGPUHangMessage(msg string) bool {
	// Look for both the GPU hang pattern and i915 module references
	return strings.Contains(strings.ToLower(msg), strings.ToLower(GPU_HANG_PATTERN)) &&
		strings.Contains(strings.ToLower(msg), strings.ToLower(I915_PATTERN))
}

// handleGPUHang takes action when a GPU hang is detected
func (m *GPUMonitor) handleGPUHang(msg string) {
	m.logger.Error("GPU: Intel i915 GPU hang detected, initiating system reboot",
		zap.String("message", msg))

	// Reboot the system immediately
	m.rebootSystem()
}

// rebootSystem triggers a system reboot
func (m *GPUMonitor) rebootSystem() {
	m.logger.Error("GPU: Initiating system reboot due to GPU hang")

	cmd := exec.Command("sudo", "systemctl", "reboot")
	if output, err := cmd.CombinedOutput(); err != nil {
		m.logger.Error("GPU: Failed to reboot system",
			zap.Error(err),
			zap.ByteString("output", output))
	}
}
