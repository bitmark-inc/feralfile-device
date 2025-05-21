package main

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"sync"
	"time"

	"github.com/feral-file/godbus"
	"go.uber.org/zap"
)

const (
	DBUS_SYS_MONITORD_EVENT_SYSMETRICS  godbus.Member = "sysmetrics"
	DBUS_SYS_MONITORD_EVENT_GPU_HANGING godbus.Member = "gpu_hanging"
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

func (p MemoryMetrics) CapacityPercent() (float64, error) {
	if p.MaxCapacity == 0 {
		return 0, errors.New("Max capacity is 0")
	}
	return p.UsedCapacity / p.MaxCapacity * 100, nil
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

func (p DiskMetrics) UsagePercent() (float64, error) {
	if p.TotalCapacity == 0 {
		return 0, errors.New("Total capacity is 0")
	}
	return p.UsedCapacity / p.TotalCapacity * 100, nil
}

type SysMetrics struct {
	CPU       CPUMetrics    `json:"cpu"`
	GPU       GPUMetrics    `json:"gpu"`
	Memory    MemoryMetrics `json:"memory"`
	Screen    ScreenMetrics `json:"screen"`
	Uptime    float64       `json:"uptime"`
	Disk      DiskMetrics   `json:"disk"`
	Timestamp time.Time     `json:"timestamp"` // Unix timestamp
}

type Mediator struct {
	mu                  sync.Mutex
	isProcessingMetrics bool
	dbus                *godbus.DBusClient
	logger              *zap.Logger
	diskHandler         *DiskHandler
	memoryHandler       *MemoryHandler
	gpuHandler          *GPUHandler
}

func NewMediator(
	dbus *godbus.DBusClient,
	disk *DiskHandler,
	ram *MemoryHandler,
	gpu *GPUHandler,
	logger *zap.Logger) *Mediator {
	return &Mediator{
		dbus:          dbus,
		logger:        logger,
		diskHandler:   disk,
		memoryHandler: ram,
		gpuHandler:    gpu,
	}
}

func (m *Mediator) Start() {
	m.dbus.OnBusSignal(m.handleDBusSignal)
}

func (m *Mediator) Stop() {
	m.dbus.RemoveBusSignal(m.handleDBusSignal)
}

func (m *Mediator) handleDBusSignal(
	ctx context.Context,
	payload godbus.DBusPayload) ([]interface{}, error) {
	if payload.Member.IsACK() {
		return nil, nil
	}

	switch payload.Member {
	case DBUS_SYS_MONITORD_EVENT_GPU_HANGING:
		m.gpuHandler.restartGPU(ctx)
		return nil, nil
	case DBUS_SYS_MONITORD_EVENT_SYSMETRICS:
		if len(payload.Body) != 1 {
			m.logger.Error("Invalid number of arguments", zap.Int("expected", 1), zap.Int("actual", len(payload.Body)))
			return nil, nil
		}

		body, ok := payload.Body[0].([]byte)
		if !ok {
			m.logger.Error("Invalid body type", zap.String("expected", "[]byte"), zap.String("actual", reflect.TypeOf(payload.Body[0]).String()))
			return nil, nil
		}

		var metrics SysMetrics
		if err := json.Unmarshal(body, &metrics); err != nil {
			m.logger.Error("Failed to unmarshal metrics", zap.Error(err))
			return nil, nil
		}

		m.logger.Debug("Received sysmetrics", zap.Any("metrics", metrics))
		// Set timestamp if not present
		if metrics.Timestamp.IsZero() {
			metrics.Timestamp = time.Now()
		}

		// Process metrics for system health monitoring
		m.ProcessMetrics(ctx, &metrics)
	}

	return nil, nil
}

func (m *Mediator) ProcessMetrics(ctx context.Context, metrics *SysMetrics) {
	m.mu.Lock()
	if m.isProcessingMetrics {
		m.mu.Unlock()
		return
	}

	m.isProcessingMetrics = true
	m.mu.Unlock()

	defer func() {
		m.mu.Lock()
		m.isProcessingMetrics = false
		m.mu.Unlock()
	}()

	// Check memory usage
	m.memoryHandler.checkMemoryUsage(ctx, metrics)

	// Check disk usage
	m.diskHandler.checkDiskUsage(ctx, metrics)
}
