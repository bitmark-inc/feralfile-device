package main

import (
	"bufio"
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

const (
	PROFILER_INTERVAL = 1 * time.Second
)

type CPUProfile struct {
	MaxFrequency       float64 `json:"max_frequency"`
	CurrentFrequency   float64 `json:"current_frequency"`
	MaxTemperature     float64 `json:"max_temperature"`
	CurrentTemperature float64 `json:"current_temperature"`
}

type GPUProfile struct {
	MaxFrequency       float64 `json:"max_frequency"`
	CurrentFrequency   float64 `json:"current_frequency"`
	CurrentTemperature float64 `json:"current_temperature"`
	MaxTemperature     float64 `json:"max_temperature"`
}

type MemoryProfile struct {
	MaxCapacity  float64 `json:"max_capacity"`
	UsedCapacity float64 `json:"used_capacity"`
}

func (p MemoryProfile) CapacityPercent() float64 {
	return p.UsedCapacity / p.MaxCapacity
}

type ScreenProfile struct {
	Width  int `json:"width"`
	Height int `json:"height"`
}

type Profile struct {
	CPU    CPUProfile    `json:"cpu"`
	GPU    GPUProfile    `json:"gpu"`
	Memory MemoryProfile `json:"memory"`
	Screen ScreenProfile `json:"screen"`
	Uptime float64       `json:"uptime"`
}

type ProfileHandler func(profile *Profile)

type Profiler struct {
	sync.Mutex

	ctx         context.Context
	logger      *zap.Logger
	lastProfile *Profile
	handlers    []ProfileHandler
	doneChan    chan struct{}
}

func NewProfiler(ctx context.Context, logger *zap.Logger) *Profiler {
	return &Profiler{
		ctx:      ctx,
		logger:   logger,
		handlers: []ProfileHandler{},
		doneChan: make(chan struct{}),
	}
}

func (p *Profiler) LastProfile() *Profile {
	p.Lock()
	defer p.Unlock()

	return p.lastProfile
}

func (p *Profiler) Start() {
	go p.run()
}

func (p *Profiler) run() {
	p.logger.Info("Profiler started in the background")

	ticker := time.NewTicker(PROFILER_INTERVAL)
	defer ticker.Stop()

	for {
		select {
		case <-p.doneChan:
			p.logger.Info("Profiler stopped")
			return
		case <-p.ctx.Done():
			p.logger.Info("Profiler stopped because context was cancelled")
			return
		case <-ticker.C:
			p.logger.Debug("Profiling system")
			profile, err := p.profile()
			if err != nil {
				p.logger.Error("Failed to profile system", zap.Error(err))
				continue
			}
			p.notifyHandlers(profile)
			p.lastProfile = profile
		}
	}
}

func (p *Profiler) profile() (*Profile, error) {
	profile := &Profile{
		CPU:    CPUProfile{},
		GPU:    GPUProfile{},
		Memory: MemoryProfile{},
		Screen: ScreenProfile{},
		Uptime: 0,
	}

	// CPU profile
	cpuProfile, err := p.profileCPU()
	if err != nil {
		return nil, err
	}
	profile.CPU = cpuProfile

	// GPU profile
	gpuProfile, err := p.profileGPU()
	if err != nil {
		return nil, err
	}
	profile.GPU = gpuProfile

	// Memory profile
	memoryProfile, err := p.profileMemory()
	if err != nil {
		return nil, err
	}
	profile.Memory = memoryProfile

	// Screen profile
	screenProfile, err := p.profileScreen()
	if err != nil {
		return nil, err
	}
	profile.Screen = screenProfile

	// Uptime profile
	uptimeProfile, err := p.profileUptime()
	if err != nil {
		return nil, err
	}
	profile.Uptime = uptimeProfile

	return profile, nil
}

func (p *Profiler) profileCPU() (CPUProfile, error) {
	cpuProfile := CPUProfile{}

	// Get CPU frequency
	currentFreq, maxFreq, err := p.getCPUFrequency()
	if err != nil {
		return cpuProfile, err
	}
	cpuProfile.CurrentFrequency = currentFreq
	cpuProfile.MaxFrequency = maxFreq

	// Get CPU temperature
	currentTemp, maxTemp, err := p.getCPUTemperature()
	if err != nil {
		return cpuProfile, err
	}
	cpuProfile.CurrentTemperature = currentTemp
	cpuProfile.MaxTemperature = maxTemp

	return cpuProfile, nil
}

// getCPUFrequency returns the current and max CPU frequencies in MHz
func (p *Profiler) getCPUFrequency() (current, max float64, err error) {
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
func (p *Profiler) getCPUTemperature() (current, max float64, err error) {
	cmd := exec.Command("sensors", "-u")
	output, err := cmd.Output()
	if err != nil {
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

func (p *Profiler) profileGPU() (GPUProfile, error) {
	gpuProfile := GPUProfile{}

	// Get GPU frequency
	currentFreq, maxFreq, err := p.getIntelGPUFreq()
	if err != nil {
		return gpuProfile, err
	}
	gpuProfile.CurrentFrequency = currentFreq
	gpuProfile.MaxFrequency = maxFreq

	// Get GPU temperature
	currentTemp, maxTemp, err := p.getCPUTemperature()
	if err != nil {
		return gpuProfile, err
	}
	gpuProfile.CurrentTemperature = currentTemp
	gpuProfile.MaxTemperature = maxTemp

	return gpuProfile, nil
}

// getIntelGPUFreq gets Intel GPU frequency using intel_gpu_top
func (p *Profiler) getIntelGPUFreq() (current, max float64, err error) {
	// Get the current frequency
	cmd := exec.Command("timeout", "1s", "sudo", "intel_gpu_top", "-J", "-s", "1000")
	output, err := cmd.Output()
	if exitErr, ok := err.(*exec.ExitError); !ok || exitErr.ExitCode() != 124 {
		return 0, 0, err
	}

	outputString := string(output)
	if !strings.HasSuffix(outputString, "]") {
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
	cmd = exec.Command("ls", "/sys/class/drm/")
	output, err = cmd.Output()
	if err != nil {
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
	cmd = exec.Command("cat", "/sys/class/drm/"+card+"/gt_max_freq_mhz")
	output, err = cmd.Output()
	if err != nil {
		return 0, 0, err
	}
	max, err = strconv.ParseFloat(strings.TrimSpace(string(output)), 64)
	if err != nil {
		return 0, 0, err
	}

	return current, max, nil
}

func (p *Profiler) profileMemory() (MemoryProfile, error) {
	memoryProfile := MemoryProfile{}

	// Get memory usage
	used, total, err := p.getMemoryStats()
	if err != nil {
		return memoryProfile, err
	}
	memoryProfile.UsedCapacity = used
	memoryProfile.MaxCapacity = total

	return memoryProfile, nil
}

// getMemoryStats returns the memory usage statistics
func (p *Profiler) getMemoryStats() (used, total float64, err error) {
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

func (p *Profiler) profileUptime() (float64, error) {
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

func (p *Profiler) profileScreen() (ScreenProfile, error) {
	screenProfile := ScreenProfile{}

	cmd := exec.Command("wlr-randr")
	output, err := cmd.Output()
	if err != nil {
		return screenProfile, err
	}

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "current") {
			fields := strings.Fields(line)
			if len(fields) < 1 {
				return screenProfile, fmt.Errorf("unexpected format in wlr-randr output")
			}

			dimensions := strings.Split(fields[0], "x")
			if len(dimensions) != 2 {
				return screenProfile, fmt.Errorf("unexpected format in wlr-randr output")
			}
			screenProfile.Width, err = strconv.Atoi(dimensions[0])
			if err != nil {
				return screenProfile, err
			}
			screenProfile.Height, err = strconv.Atoi(dimensions[1])
			if err != nil {
				return screenProfile, err
			}

			break
		}
	}
	return screenProfile, nil
}

func (p *Profiler) notifyHandlers(profile *Profile) {
	p.Lock()
	handlers := make([]ProfileHandler, len(p.handlers))
	copy(handlers, p.handlers)
	p.Unlock()

	for _, handler := range handlers {
		go func(h ProfileHandler) {
			h(profile)
		}(handler)
	}
}

func (p *Profiler) OnProfile(handler ProfileHandler) {
	p.Lock()
	defer p.Unlock()

	p.handlers = append(p.handlers, handler)
}

func (p *Profiler) RemoveProfileHandler(handler ProfileHandler) {
	p.Lock()
	defer p.Unlock()

	for i, h := range p.handlers {
		if fmt.Sprintf("%p", h) == fmt.Sprintf("%p", handler) {
			p.handlers = append(p.handlers[:i], p.handlers[i+1:]...)
			return
		}
	}
}

func (p *Profiler) Stop() {
	select {
	case <-p.doneChan:
		return
	default:
		close(p.doneChan)
	}

	p.logger.Info("Profiler stopped")
}
