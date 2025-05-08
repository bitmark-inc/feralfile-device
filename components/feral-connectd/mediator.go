package main

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/godbus/dbus/v5"
	"go.uber.org/zap"
)

type Mediator struct {
	sync.Mutex

	relayer *RelayerClient
	dbus    *DBusClient
	cdp     *CDPClient
	logger  *zap.Logger
}

func NewMediator(
	relayer *RelayerClient,
	dbus *DBusClient,
	cdp *CDPClient,
	logger *zap.Logger) *Mediator {
	return &Mediator{
		relayer: relayer,
		dbus:    dbus,
		cdp:     cdp,
		logger:  logger,
	}
}

func (m *Mediator) Start() {
	m.dbus.OnBusSignal(m.handleDBusSignal)
	m.relayer.OnRelayerMessage(m.handleRelayerMessage)
}

func (m *Mediator) Stop() {
	m.dbus.RemoveBusSignal(m.handleDBusSignal)
	m.relayer.RemoveRelayerMessage(m.handleRelayerMessage)
}

func (m *Mediator) handleDBusSignal(
	ctx context.Context,
	iface string,
	path dbus.ObjectPath,
	member string,
	body []interface{}) error {
	m.logger.Info(
		"Received DBus signal",
		zap.String("interface", iface),
		zap.String("path", string(path)),
		zap.String("member", member),
		zap.Any("body", body),
	)

	switch member {
	case EVENT_SETUPD_WIFI_CONNECTED, EVENT_STATED_DEVICE_CONNECTED:
		bo := backoff.NewExponentialBackOff()
		bo.InitialInterval = 5 * time.Second
		bo.Multiplier = 2
		bo.MaxElapsedTime = 30 * time.Second

		err := backoff.Retry(func() error {
			return m.relayer.Connect(ctx)
		}, bo)
		if err != nil {
			m.logger.Error("Failed to connect to relayer", zap.Error(err))
			return err
		}
	default:
		return fmt.Errorf("unknown signal: %s", member)
	}

	return nil
}

func (m *Mediator) handleRelayerMessage(ctx context.Context, data map[string]interface{}) error {
	m.logger.Info("Received relayer message", zap.Any("data", data))

	messageID, _ := data["messageID"].(string)
	message, ok := data["message"].(map[string]interface{})
	if !ok {
		m.logger.Error("Invalid message", zap.Any("data", data))
		return fmt.Errorf("invalid message")
	}
	switch messageID {
	case "system":
		// Parse locationID and topicID
		locationID, _ := message["locationID"].(string)
		topicID, _ := message["topicID"].(string)
		if locationID == "" || topicID == "" {
			m.logger.Error("Invalid message", zap.Any("data", data))
			return fmt.Errorf("invalid message")
		}

		config.RelayerConfig.LocationID = locationID
		config.RelayerConfig.TopicID = topicID

		// Persist configuration
		err := PersistConfig(m.logger)
		if err != nil {
			m.logger.Error("Failed to persist configuration", zap.Error(err))
			return err
		}

		// Publish locationID and topicID
		err = m.dbus.Send(
			DBUS_INTERFACE,
			DBUS_PATH,
			EVENT_CONNECTD_RELAYER_CONFIGURED,
			locationID,
			topicID,
		)
		if err != nil {
			m.logger.Error("Failed to send DBus signal", zap.Error(err))
			return err
		}
	default:
		// TODO run cdp
	}

	return nil
}
