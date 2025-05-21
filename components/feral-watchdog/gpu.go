package main

import (
	"context"
	"sync"
	"time"

	"go.uber.org/zap"
)

const (
	REBOOT_DELAY = 15 * time.Second
)

type GPUHandler struct {
	mu              sync.Mutex
	logger          *zap.Logger
	commandHandler  *CommandHandler
	rebootTimer     *time.Timer
	rebootScheduled bool
}

func NewGPUHandler(logger *zap.Logger, commandHandler *CommandHandler) *GPUHandler {
	return &GPUHandler{
		logger:          logger,
		commandHandler:  commandHandler,
		rebootScheduled: false,
	}
}

func (g *GPUHandler) scheduleGPUReboot(ctx context.Context) {
	g.mu.Lock()
	defer g.mu.Unlock()

	// If a reboot is already scheduled, ignore this request
	if g.rebootScheduled {
		g.logger.Info("GPU: reboot already scheduled, ignoring request")
		return
	}

	g.logger.Info("GPU: scheduling reboot")
	g.rebootScheduled = true

	// Create a timer to reboot after 15 seconds
	g.rebootTimer = time.AfterFunc(REBOOT_DELAY, func() {
		select {
		case <-ctx.Done():
			g.logger.Info("GPU: context cancelled, skipping reboot")
			g.cancelReboot(ctx)
		default:
			g.mu.Lock()
			g.rebootScheduled = false
			g.rebootTimer = nil
			g.mu.Unlock()
			g.logger.Info("GPU: executing reboot")
			g.commandHandler.rebootSystem(ctx)
		}
	})
}

func (g *GPUHandler) handleGPURecovery(ctx context.Context) {
	g.mu.Lock()
	isRebootScheduled := g.rebootScheduled
	g.mu.Unlock()

	if isRebootScheduled {
		g.cancelReboot(ctx)
		g.restartKiosk(ctx)
	}
}

func (g *GPUHandler) cancelReboot(ctx context.Context) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if !g.rebootScheduled {
		g.logger.Info("GPU: no reboot scheduled, nothing to cancel")
		return
	}

	g.logger.Info("GPU: cancelling scheduled reboot")
	if g.rebootTimer == nil {
		g.logger.Warn("GPU: timer is nil, cannot cancel")
		return
	}

	stopped := g.rebootTimer.Stop()
	if !stopped {
		g.logger.Warn("GPU: timer already fired, cannot cancel")
		return
	}

	g.rebootScheduled = false
	g.rebootTimer = nil
}

func (g *GPUHandler) restartKiosk(ctx context.Context) {
	g.logger.Info("GPU: restarting kiosk")
	g.commandHandler.restartKiosk(ctx)
}
