package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.uber.org/zap"
)

const (
	// RAM monitoring configuration
	PROC_MEMINFO_PATH         = "/proc/meminfo"
	RAM_CRITICAL_THRESHOLD    = 95.0             // 95% used RAM triggers action
	RAM_RESTART_WINDOW        = 60 * time.Second // Window for tracking multiple restarts
	RAM_CHECK_INTERVAL        = 5 * time.Second  // Check RAM every 5 seconds
	RAM_CONSECUTIVE_THRESHOLD = 3                // Number of consecutive samples above threshold to trigger action
)

// RAMMonitor monitors system RAM usage
type RAMMonitor struct {
	mu                    sync.Mutex
	logger                *zap.Logger
	lastRestartTime       time.Time
	highUsageSamplesCount int
}

// NewRAMMonitor creates a new RAM monitor instance
func NewRAMMonitor(logger *zap.Logger) *RAMMonitor {
	return &RAMMonitor{
		logger: logger,
	}
}

// Start begins the RAM monitoring process
func (m *RAMMonitor) Start(ctx context.Context) {
	m.logger.Info("RAM: Starting RAM monitor",
		zap.Duration("check_interval", RAM_CHECK_INTERVAL),
		zap.Float64("critical_threshold_percent", RAM_CRITICAL_THRESHOLD),
		zap.Int("consecutive_samples_required", RAM_CONSECUTIVE_THRESHOLD))

	ticker := time.NewTicker(RAM_CHECK_INTERVAL)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			m.logger.Info("RAM: Monitor shutting down")
			return
		case <-ticker.C:
			available, total, err := m.getMemInfo(ctx)
			if err != nil {
				m.logger.Error("RAM: Failed to get memory information", zap.Error(err))
				continue
			}

			percentAvailable := (float64(available) / float64(total)) * 100
			percentUsed := 100.0 - percentAvailable

			m.logger.Info("RAM: Usage check",
				zap.Float64("percent_available", percentAvailable))

			// Check if RAM usage is critically high
			if percentUsed > RAM_CRITICAL_THRESHOLD {
				m.trackHighMemoryUsage(percentUsed)
			} else {
				// Reset consecutive samples count if memory usage returns to normal
				m.mu.Lock()
				m.highUsageSamplesCount = 0
				m.mu.Unlock()
			}
		}
	}
}

// getMemInfo reads and parses memory information from /proc/meminfo
func (m *RAMMonitor) getMemInfo(ctx context.Context) (available int64, total int64, err error) {
	file, err := os.Open(PROC_MEMINFO_PATH)
	if err != nil {
		return 0, 0, fmt.Errorf("failed to open %s: %w", PROC_MEMINFO_PATH, err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)

	// We need to find both MemTotal and MemAvailable
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			file.Close()
			return 0, 0, fmt.Errorf("context cancelled")
		default:
			// Continue processing
		}

		line := scanner.Text()

		if strings.HasPrefix(line, "MemTotal:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				total, err = strconv.ParseInt(parts[1], 10, 64)
				if err != nil {
					return 0, 0, fmt.Errorf("failed to parse MemTotal: %w", err)
				}
			}
		} else if strings.HasPrefix(line, "MemAvailable:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				available, err = strconv.ParseInt(parts[1], 10, 64)
				if err != nil {
					return 0, 0, fmt.Errorf("failed to parse MemAvailable: %w", err)
				}
			}
		}

		// If we found both values, we can return early
		if total > 0 && available > 0 {
			return available, total, nil
		}
	}

	if err := scanner.Err(); err != nil {
		return 0, 0, fmt.Errorf("error reading %s: %w", PROC_MEMINFO_PATH, err)
	}

	// If we didn't find both values, return an error
	if total == 0 || available == 0 {
		return 0, 0, fmt.Errorf("failed to find MemTotal or MemAvailable in %s", PROC_MEMINFO_PATH)
	}

	return available, total, nil
}

// trackHighMemoryUsage tracks consecutive high RAM usage samples
func (m *RAMMonitor) trackHighMemoryUsage(percentUsed float64) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.highUsageSamplesCount++

	m.logger.Info("RAM: High RAM usage detected",
		zap.Float64("percent_used", percentUsed),
		zap.Int("High usage count", m.highUsageSamplesCount))

	if m.highUsageSamplesCount >= RAM_CONSECUTIVE_THRESHOLD {
		m.handleHighMemory(percentUsed)
		// Reset the counter after taking action
		m.highUsageSamplesCount = 0
	}
}

// handleHighMemory takes action when RAM usage is critically high for consecutive samples
func (m *RAMMonitor) handleHighMemory(percentUsed float64) {
	m.logger.Error("RAM: Critical RAM usage detected for consecutive samples",
		zap.Float64("percent_used", percentUsed))

	// Check if we recently restarted and need to escalate
	timeSinceLastRestart := time.Since(m.lastRestartTime)
	if !m.lastRestartTime.IsZero() && timeSinceLastRestart < RAM_RESTART_WINDOW {
		m.logger.Error("RAM: Second RAM breach within restart window, escalating to system reboot",
			zap.Duration("since_last_restart", timeSinceLastRestart),
			zap.Duration("restart_window", RAM_RESTART_WINDOW))
		m.rebootSystem()
		return
	}

	// Try restarting the Chromium service first
	m.lastRestartTime = time.Now()
	m.logger.Warn("RAM: Restarting chromium-kiosk.service due to high memory usage")

	cmd := exec.Command("sudo", "systemctl", "restart", "chromium-kiosk.service")
	if output, err := cmd.CombinedOutput(); err != nil {
		m.logger.Error("RAM: Failed to restart chromium-kiosk.service",
			zap.Error(err),
			zap.ByteString("output", output))
	} else {
		m.logger.Info("RAM: Successfully restarted chromium-kiosk.service due to high memory usage")
	}
}

// rebootSystem triggers a system reboot
func (m *RAMMonitor) rebootSystem() {
	m.logger.Error("RAM: Initiating system reboot due to recurring RAM usage issues")

	cmd := exec.Command("sudo", "systemctl", "reboot")
	if output, err := cmd.CombinedOutput(); err != nil {
		m.logger.Error("Failed to reboot system",
			zap.Error(err),
			zap.ByteString("output", output))
	}
}
