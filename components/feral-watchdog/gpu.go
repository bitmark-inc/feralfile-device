package main

import (
	"context"
	"sync"

	"go.uber.org/zap"
)

type GPUHandler struct {
	mu             sync.Mutex
	logger         *zap.Logger
	commandHandler *CommandHandler
}

func NewGPUHandler(logger *zap.Logger, commandHandler *CommandHandler) *GPUHandler {
	return &GPUHandler{
		logger:         logger,
		commandHandler: commandHandler,
	}
}

func (g *GPUHandler) restartGPU(ctx context.Context) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.commandHandler.rebootSystem(ctx)
}
