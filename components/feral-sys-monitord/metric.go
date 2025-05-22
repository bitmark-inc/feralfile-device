package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.uber.org/zap"
)

type CPUMetrics struct {
	MaxFrequency       float64 `json:"max_frequency"`
	CurrentFrequency   float64 `json:"current_frequency"`
	MaxTemperature     float64 `json:"max_temperature"`
	CurrentTemperature float64 `json:"current_temperature"`
}

type GPUMetrics struct {
	MaxFrequency       float64 `json:"max_frequency"`
	CurrentFrequency   float64 `json:"current_frequency"`
	CurrentTemperature float64 `json:"current_temperature"`
	MaxTemperature     float64 `json:"max_temperature"`
}

type MemoryMetrics struct {
	MaxCapacity  float64 `json:"max_capacity"`
	UsedCapacity float64 `json:"used_capacity"`
}

type ScreenMetrics struct {
	Width       int     `json:"width"`
	Height      int     `json:"height"`
	RefreshRate float64 `json:"refresh_rate"`
}

type DiskMetrics struct {
	TotalCapacity     float64            `json:"total_capacity"`
	UsedCapacity      float64            `json:"used_capacity"`
	AvailableCapacity float64            `json:"available_capacity"`
	Breakdown         map[string]float64 `json:"breakdown"`
}

type SysMetrics struct {
	CPU       CPUMetrics    `json:"cpu"`
	GPU       GPUMetrics    `json:"gpu"`
	Memory    MemoryMetrics `json:"memory"`
	Screen    ScreenMetrics `json:"screen"`
	Uptime    float64       `json:"uptime"`
	Disk      DiskMetrics   `json:"disk"`
	Timestamp time.Time     `json:"timestamp"`
}

type MonitorHandler func(metrics *SysMetrics)

type SysResMonitor struct {
	sync.Mutex

	ctx         context.Context
	logger      *zap.Logger
	lastMetrics *SysMetrics
	handlers    []MonitorHandler
	doneChan    chan struct{}
}

func NewSysResMonitor(ctx context.Context, logger *zap.Logger) *SysResMonitor {
	return &SysResMonitor{
		ctx:      ctx,
		logger:   logger,
		handlers: []MonitorHandler{},
		doneChan: make(chan struct{}),
	}
}

func (p *SysResMonitor) LastMetrics() *SysMetrics {
	p.Lock()
	defer p.Unlock()

	return p.lastMetrics
}

func (p *SysResMonitor) Start() {
	go p.run()
}

func (p *SysResMonitor) run() {
	p.logger.Info("SysResMonitor started in the background")

	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-p.doneChan:
			p.logger.Info("SysResMonitor stopped")
			return
		case <-p.ctx.Done():
			p.logger.Info("SysResMonitor stopped because context was cancelled")
			return
		case <-ticker.C:
			metrics, err := p.monitor(p.ctx)
			if err != nil {
				p.logger.Error("Failed to monitor system resources", zap.Error(err))
				continue
			}
			p.notifyHandlers(p.ctx, metrics)
			p.Lock()
			p.lastMetrics = metrics
			p.Unlock()
		}
	}
}

func (p *SysResMonitor) monitor(ctx context.Context) (*SysMetrics, error) {
	metrics := &SysMetrics{
		CPU:       CPUMetrics{},
		GPU:       GPUMetrics{},
		Memory:    MemoryMetrics{},
		Screen:    ScreenMetrics{},
		Uptime:    0,
		Timestamp: time.Now(),
	}

	var wg sync.WaitGroup
	var mu sync.Mutex
	var errs []error

	// Run CPU metrics collection
	wg.Add(1)
	go func() {
		defer wg.Done()
		cpuMetrics, err := p.monitorCPU(ctx)
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			errs = append(errs, err)
			return
		}
		metrics.CPU = cpuMetrics
	}()

	// Run GPU metrics collection
	wg.Add(1)
	go func() {
		defer wg.Done()
		gpuMetrics, err := p.monitorGPU(ctx)
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			errs = append(errs, err)
			return
		}
		metrics.GPU = gpuMetrics
	}()

	// Run Memory metrics collection
	wg.Add(1)
	go func() {
		defer wg.Done()
		memoryMetrics, err := p.monitorMemory()
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			errs = append(errs, err)
			return
		}
		metrics.Memory = memoryMetrics
	}()

	// Run Screen metrics collection
	wg.Add(1)
	go func() {
		defer wg.Done()
		screenMetrics, err := p.monitorScreen(ctx)
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			errs = append(errs, err)
			return
		}
		metrics.Screen = screenMetrics
	}()

	// Run Uptime metrics collection
	wg.Add(1)
	go func() {
		defer wg.Done()
		uptimeMetrics, err := p.monitorUptime()
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			errs = append(errs, err)
			return
		}
		metrics.Uptime = uptimeMetrics
	}()

	// Run Disk metrics collection
	wg.Add(1)
	go func() {
		defer wg.Done()
		diskMetrics, err := p.monitorDisk(ctx)
		mu.Lock()
		defer mu.Unlock()
		if err != nil {
			errs = append(errs, err)
			return
		}
		metrics.Disk = diskMetrics
	}()

	// Wait for all goroutines to complete
	wg.Wait()

	// Apply CPU temperature to GPU temperature
	metrics.GPU.CurrentTemperature = metrics.CPU.CurrentTemperature
	metrics.GPU.MaxTemperature = metrics.CPU.MaxTemperature

	// Check if any errors occurred
	if len(errs) > 0 {
		return nil, errs[0] // Return the first error
	}

	return metrics, nil
}

func (p *SysResMonitor) monitorCPU(ctx context.Context) (CPUMetrics, error) {
	metrics := CPUMetrics{}

	// Get CPU frequency
	cpuFreq, maxFreq, err := p.getCPUFrequency()
	if err != nil {
		return metrics, err
	}
	metrics.CurrentFrequency = cpuFreq
	metrics.MaxFrequency = maxFreq

	// Get CPU temperature
	cpuTemp, maxTemp, err := p.getCPUTemperature(ctx)
	if err != nil {
		return metrics, err
	}
	metrics.CurrentTemperature = cpuTemp
	metrics.MaxTemperature = maxTemp

	return metrics, nil
}

// getCPUFrequency returns the current and max CPU frequencies in MHz
func (p *SysResMonitor) getCPUFrequency() (current, max float64, err error) {
	// Find all CPU frequency files
	cpuFreqFiles, err := filepath.Glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")
	if err != nil {
		return 0, 0, err
	}

	if len(cpuFreqFiles) == 0 {
		return 0, 0, fmt.Errorf("no CPU frequency files found")
	}

	// Get current frequency (average of all cores)
	var sum int64
	for _, file := range cpuFreqFiles {
		data, err := os.ReadFile(file)
		if err != nil {
			return 0, 0, err
		}

		freq, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
		if err != nil {
			return 0, 0, err
		}
		sum += freq
	}
	current = float64(sum) / float64(len(cpuFreqFiles)) / 1000.0 // Convert to MHz

	// Get max frequency - look for cpuinfo_max_freq
	maxFreqFiles, _ := filepath.Glob("/sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq")
	if len(maxFreqFiles) > 0 {
		data, err := os.ReadFile(maxFreqFiles[0])
		if err != nil {
			return 0, 0, err
		}

		maxFreq, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
		if err != nil {
			return 0, 0, err
		}
		max = float64(maxFreq) / 1000.0 // Convert to MHz
	}

	return current, max, nil
}

// getCPUTemperature tries to get the CPU temperature from lm-sensors
func (p *SysResMonitor) getCPUTemperature(ctx context.Context) (current, max float64, err error) {
	cmd := exec.CommandContext(ctx, "sensors", "-u")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		p.logger.Error("Failed to get CPU temperature", zap.String("stderr", stderr.String()), zap.Error(err))
		return 0, 0, err
	}

	// Parse the output
	lines := strings.Split(string(output), "\n")
	var inPackage bool
	for _, line := range lines {
		if strings.HasPrefix(line, "Package id 0:") {
			inPackage = true
			continue
		}
		if inPackage && line == "" {
			inPackage = false
		}
		if inPackage && strings.Contains(line, "temp1_input:") {
			fields := strings.Fields(line)
			if len(fields) < 2 {
				p.logger.Error("Failed to parse current CPU temperature", zap.String("line", line))
				continue
			}
			current, err = strconv.ParseFloat(fields[1], 64)
			if err != nil {
				return 0, 0, err
			}
		}
		if inPackage && strings.Contains(line, "temp1_max:") {
			fields := strings.Fields(line)
			if len(fields) < 2 {
				p.logger.Error("Failed to parse max CPU temperature", zap.String("line", line))
				continue
			}
			max, err = strconv.ParseFloat(fields[1], 64)
			if err != nil {
				return 0, 0, err
			}
		}
	}

	return current, max, nil
}

func (p *SysResMonitor) monitorGPU(ctx context.Context) (GPUMetrics, error) {
	metrics := GPUMetrics{}

	// Get GPU frequency
	currentFreq, maxFreq, err := p.getIntelGPUFreq(ctx)
	if err != nil {
		return metrics, err
	}
	metrics.CurrentFrequency = currentFreq
	metrics.MaxFrequency = maxFreq

	return metrics, nil
}

// getIntelGPUFreq gets Intel GPU frequency using intel_gpu_top
func (p *SysResMonitor) getIntelGPUFreq(ctx context.Context) (current, max float64, err error) {
	// Get the current frequency
	cmd := exec.CommandContext(ctx, "timeout", "1s", "sudo", "intel_gpu_top", "-J", "-s", "1000")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if exitErr, ok := err.(*exec.ExitError); !ok || exitErr.ExitCode() != 124 {
		if err != nil {
			p.logger.Error("Failed to get Intel GPU frequency", zap.String("stderr", stderr.String()), zap.Error(err))
		}
		return 0, 0, err
	}

	outputString := string(output)
	if strings.HasPrefix(outputString, "[") && !strings.HasSuffix(outputString, "]") {
		outputString = outputString + "]"
	}

	var result []struct {
		Frequency struct {
			Actual float64 `json:"actual"`
		} `json:"frequency"`
	}
	err = json.Unmarshal([]byte(outputString), &result)
	if err != nil {
		return 0, 0, err
	}
	if len(result) == 0 {
		return 0, 0, fmt.Errorf("no GPU frequency found")
	}

	current = result[0].Frequency.Actual

	// Discover the card name using `ls /sys/class/drm/`
	cmd = exec.CommandContext(ctx, "ls", "/sys/class/drm/")
	cmd.Stderr = &stderr
	output, err = cmd.Output()
	if err != nil {
		p.logger.Error("Failed to get Intel GPU frequency", zap.String("stderr", stderr.String()), zap.Error(err))
		return 0, 0, err
	}
	lines := strings.Split(string(output), "\n")
	var card string
	for _, line := range lines {
		regex := regexp.MustCompile(`^card[0-9]+`)
		if regex.MatchString(line) {
			card = regex.FindString(line)
			break
		}
	}

	// Get the max frequency
	cmd = exec.CommandContext(ctx, "cat", "/sys/class/drm/"+card+"/gt_max_freq_mhz")
	cmd.Stderr = &stderr
	output, err = cmd.Output()
	if err != nil {
		p.logger.Error("Failed to get Intel GPU frequency", zap.String("stderr", stderr.String()), zap.Error(err))
		return 0, 0, err
	}
	max, err = strconv.ParseFloat(strings.TrimSpace(string(output)), 64)
	if err != nil {
		return 0, 0, err
	}

	return current, max, nil
}

func (p *SysResMonitor) monitorMemory() (MemoryMetrics, error) {
	metrics := MemoryMetrics{}

	// Get memory usage
	used, total, err := p.getMemoryStats()
	if err != nil {
		return metrics, err
	}
	metrics.UsedCapacity = used
	metrics.MaxCapacity = total

	return metrics, nil
}

// getMemoryStats returns the memory usage statistics
func (p *SysResMonitor) getMemoryStats() (used, total float64, err error) {
	file, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, 0, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	var memTotal, memAvailable int64

	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "MemTotal:") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				memTotal, _ = strconv.ParseInt(fields[1], 10, 64)
			}
		} else if strings.HasPrefix(line, "MemAvailable:") {
			fields := strings.Fields(line)
			if len(fields) >= 2 {
				memAvailable, _ = strconv.ParseInt(fields[1], 10, 64)
			}
		}
	}

	memUsed := memTotal - memAvailable
	total = float64(memTotal) / 1024.0 // Convert to MB
	used = float64(memUsed) / 1024.0   // Convert to MB

	return used, total, nil
}

func (p *SysResMonitor) monitorUptime() (float64, error) {
	// Read the uptime file
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0, err
	}

	// Parse the uptime value (first value in the file)
	fields := strings.Fields(string(data))
	if len(fields) < 1 {
		return 0, fmt.Errorf("unexpected format in /proc/uptime")
	}

	// Convert uptime to float (seconds)
	uptimeSec, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, err
	}

	return uptimeSec, nil
}

func (p *SysResMonitor) monitorScreen(ctx context.Context) (ScreenMetrics, error) {
	metrics := ScreenMetrics{}

	// Resolution and refresh rate
	cmd := exec.CommandContext(ctx, "wlr-randr")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		p.logger.Error("Failed to get screen metrics", zap.String("stderr", stderr.String()), zap.Error(err))
		return metrics, err
	}

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "current") {
			fields := strings.Fields(line)
			if len(fields) < 3 {
				return metrics, fmt.Errorf("unexpected format in wlr-randr output")
			}

			// resolution
			dimensions := strings.Split(fields[0], "x")
			if len(dimensions) != 2 {
				return metrics, fmt.Errorf("unexpected format in wlr-randr output")
			}
			metrics.Width, err = strconv.Atoi(dimensions[0])
			if err != nil {
				return metrics, err
			}
			metrics.Height, err = strconv.Atoi(dimensions[1])
			if err != nil {
				return metrics, err
			}

			// refresh rate
			refreshRate, err := strconv.ParseFloat(fields[2], 64)
			if err != nil {
				return metrics, err
			}
			metrics.RefreshRate = refreshRate

			break
		}
	}

	return metrics, nil
}

func (p *SysResMonitor) monitorDisk(ctx context.Context) (DiskMetrics, error) {
	metrics := DiskMetrics{}

	// Get total/used capacity
	total, used, available, err := p.getDiskStats(ctx)
	if err != nil {
		return metrics, err
	}
	metrics.TotalCapacity = total
	metrics.UsedCapacity = used
	metrics.AvailableCapacity = available

	// Get breakdown
	breakdown, err := p.getDiskBreakdown(ctx)
	if err != nil {
		return metrics, err
	}
	metrics.Breakdown = breakdown

	return metrics, nil
}

func (p *SysResMonitor) getDiskStats(ctx context.Context) (total, used, available float64, err error) {
	cmd := exec.CommandContext(ctx, "df", "-k", "/")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		p.logger.Error("Failed to get disk stats", zap.String("stderr", stderr.String()), zap.Error(err))
		return 0, 0, 0, err
	}

	lines := strings.Split(string(output), "\n")
	if len(lines) < 2 {
		return 0, 0, 0, fmt.Errorf("unexpected format in df output")
	}

	fields := strings.Fields(lines[1])
	if len(fields) < 5 {
		return 0, 0, 0, fmt.Errorf("unexpected format in df output")
	}

	total, err = strconv.ParseFloat(fields[1], 64)
	if err != nil {
		return 0, 0, 0, err
	}

	used, err = strconv.ParseFloat(fields[2], 64)
	if err != nil {
		return 0, 0, 0, err
	}

	available, err = strconv.ParseFloat(fields[3], 64)
	if err != nil {
		return 0, 0, 0, err
	}

	return total, used, available, nil
}

func (p *SysResMonitor) getDiskBreakdown(ctx context.Context) (map[string]float64, error) {
	cmd := exec.CommandContext(ctx, "bash", "-c", "du -s /* 2>/dev/null || true")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		p.logger.Error("Failed to get disk breakdown", zap.String("stderr", stderr.String()), zap.Error(err))
		return nil, err
	}

	lines := strings.Split(string(output), "\n")
	metrics := make(map[string]float64)
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}

		total, err := strconv.ParseFloat(fields[0], 64)
		if err != nil {
			return nil, err
		}

		metrics[fields[1]] = total
	}

	return metrics, nil
}

func (p *SysResMonitor) notifyHandlers(ctx context.Context, metrics *SysMetrics) {
	p.Lock()
	handlers := make([]MonitorHandler, len(p.handlers))
	copy(handlers, p.handlers)
	p.Unlock()

	for _, handler := range handlers {
		go func(h MonitorHandler) {
			select {
			case <-ctx.Done():
				return
			case <-p.doneChan:
				return
			default:
				h(metrics)
			}
		}(handler)
	}
}

func (p *SysResMonitor) OnMonitor(handler MonitorHandler) {
	p.Lock()
	defer p.Unlock()

	p.handlers = append(p.handlers, handler)
}

func (p *SysResMonitor) RemoveMonitorHandler(handler MonitorHandler) {
	p.Lock()
	defer p.Unlock()

	for i, h := range p.handlers {
		if fmt.Sprintf("%p", h) == fmt.Sprintf("%p", handler) {
			p.handlers = append(p.handlers[:i], p.handlers[i+1:]...)
			return
		}
	}
}

func (p *SysResMonitor) Stop() {
	select {
	case <-p.doneChan:
		return
	default:
		close(p.doneChan)
	}

	p.logger.Info("SysResMonitor stopped")
}
