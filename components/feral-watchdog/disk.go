package main

import (
	"context"
	"fmt"
	"os/exec"
	"syscall"
	"time"

	"go.uber.org/zap"
)

const (
	// Disk monitoring configuration
	VAR_MOUNT_PATH          = "/var"
	DISK_WARNING_THRESHOLD  = 90.0             // 90% usage triggers warning
	DISK_CRITICAL_THRESHOLD = 95.0             // 95% usage triggers reboot
	DISK_CHECK_INTERVAL     = 60 * time.Second // Check disk usage every 60 seconds
)

// DiskMonitor monitors disk usage on the /var partition
type DiskMonitor struct {
	logger *zap.Logger
}

// NewDiskMonitor creates a new disk monitor instance
func NewDiskMonitor(logger *zap.Logger) *DiskMonitor {
	return &DiskMonitor{
		logger: logger,
	}
}

// Start begins the disk usage monitoring process
func (m *DiskMonitor) Start(ctx context.Context) {
	m.logger.Info("Disk: Starting disk usage monitor",
		zap.String("mount_path", VAR_MOUNT_PATH),
		zap.Duration("check_interval", DISK_CHECK_INTERVAL),
		zap.Float64("warning_threshold", DISK_WARNING_THRESHOLD),
		zap.Float64("critical_threshold", DISK_CRITICAL_THRESHOLD))

	ticker := time.NewTicker(DISK_CHECK_INTERVAL)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			m.logger.Info("Disk: Monitor shutting down")
			return
		case <-ticker.C:
			usage, err := m.getDiskUsage(VAR_MOUNT_PATH)
			if err != nil {
				m.logger.Error("Disk: Failed to get disk usage",
					zap.String("path", VAR_MOUNT_PATH),
					zap.Error(err))
				continue
			}

			m.logger.Info("Disk: Usage check",
				zap.String("path", VAR_MOUNT_PATH),
				zap.Float64("percent_used", usage))

			// Check warning threshold
			if usage >= DISK_WARNING_THRESHOLD {
				m.logger.Warn("Disk: Usage is high",
					zap.Float64("percent_used", usage))
			}

			// Check critical threshold
			if usage >= DISK_CRITICAL_THRESHOLD {
				m.handleCriticalDiskUsage(usage)
			}
		}
	}
}

// getDiskUsage returns the disk usage percentage for the given path
func (m *DiskMonitor) getDiskUsage(path string) (float64, error) {
	var stat syscall.Statfs_t
	err := syscall.Statfs(path, &stat)
	if err != nil {
		return 0, fmt.Errorf("failed to get filesystem stats: %w", err)
	}

	// Calculate disk usage percentage
	totalBlocks := stat.Blocks
	freeBlocks := stat.Bfree

	// Avoid division by zero
	if totalBlocks == 0 {
		return 0, fmt.Errorf("filesystem reports zero total blocks")
	}

	usedBlocks := totalBlocks - freeBlocks
	usagePercent := (float64(usedBlocks) / float64(totalBlocks)) * 100.0

	return usagePercent, nil
}

// handleCriticalDiskUsage takes action when disk usage is critically high
func (m *DiskMonitor) handleCriticalDiskUsage(usage float64) {
	m.logger.Error("Disk: Critical disk usage detected, initiating system reboot",
		zap.Float64("percent_used", usage),
		zap.Float64("critical_threshold", DISK_CRITICAL_THRESHOLD))

	// Reboot the system
	m.rebootSystem()
}

// rebootSystem triggers a system reboot
func (m *DiskMonitor) rebootSystem() {
	m.logger.Error("Disk: Initiating system reboot due to critical disk usage")

	cmd := exec.Command("sudo", "systemctl", "reboot")
	if output, err := cmd.CombinedOutput(); err != nil {
		m.logger.Error("Disk: Failed to reboot system",
			zap.Error(err),
			zap.ByteString("output", output))
	}
}
