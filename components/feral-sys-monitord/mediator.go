package main

import (
	"github.com/feral-file/godbus"
	"go.uber.org/zap"
)

type Mediator struct {
	dbus    *godbus.DBusClient
	monitor *Monitor
	logger  *zap.Logger
}

func NewMediator(
	dbus *godbus.DBusClient,
	monitor *Monitor,
	logger *zap.Logger) *Mediator {
	return &Mediator{
		dbus:    dbus,
		monitor: monitor,
		logger:  logger,
	}
}

func (p *Mediator) Start() {
	p.monitor.OnMonitor(p.handleSysMetrics)
}

func (p *Mediator) Stop() {
	p.monitor.RemoveMonitorHandler(p.handleSysMetrics)
}

func (p *Mediator) handleSysMetrics(metrics *SysMetrics) {
	p.logger.Debug("Received metrics", zap.Any("metrics", metrics))

	// Send a DBus signal
	err := p.dbus.Send(godbus.DBusPayload{
		Interface: DBUS_INTERFACE,
		Path:      DBUS_PATH,
		Member:    DBUS_EVENT_SYSMETRICS,
		Body:      []interface{}{metrics},
	})
	if err != nil {
		p.logger.Error("Failed to send DBus signal", zap.Error(err))
	}
}
