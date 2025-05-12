package main

import (
	"context"
	"fmt"

	"github.com/godbus/dbus/v5"
	"go.uber.org/zap"
)

type Mediator struct {
	relayer *RelayerClient
	dbus    *DBusClient
	cdp     *CDPClient
	cmd     *CommandHandler
	logger  *zap.Logger
}

func NewMediator(
	relayer *RelayerClient,
	dbus *DBusClient,
	cdp *CDPClient,
	cmd *CommandHandler,
	logger *zap.Logger) *Mediator {
	return &Mediator{
		relayer: relayer,
		dbus:    dbus,
		cdp:     cdp,
		cmd:     cmd,
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
	member DBusMember,
	body []interface{}) ([]interface{}, error) {
	m.logger.Info(
		"Received DBus signal",
		zap.String("interface", iface),
		zap.String("path", string(path)),
		zap.String("member", member.String()),
		zap.Any("body", body),
	)

	switch member {
	case EVENT_SETUPD_WIFI_CONNECTED:
		// Connect to the relayer
		err := m.relayer.RetriableConnect(ctx)
		if err != nil {
			m.logger.Error("Failed to connect to relayer", zap.Error(err))
			return nil, err
		}

		// Wait for the relayer to be connected
		if !GetState().WaitForRelayerChanReady(ctx) {
			m.logger.Error("Failed to connect to relayer")
			return nil, fmt.Errorf("failed to connect to relayer")
		}

		// Send the locationID and topicID to the setupd
		relayer := GetState().Relayer
		return []interface{}{
			relayer.LocationID,
			relayer.TopicID,
		}, nil

	default:
		m.logger.Warn("Unknown signal", zap.String("member", member.String()))
	}

	return nil, nil
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

		state := GetState()
		state.Relayer.LocationID = locationID
		state.Relayer.TopicID = topicID

		// Save state
		err := state.Save()
		if err != nil {
			m.logger.Error("Failed to persist state", zap.Error(err))
			return err
		}
	default:
		cmd, ok := message["command"].(string)
		if !ok {
			m.logger.Error("Invalid message", zap.Any("data", data))
			return fmt.Errorf("invalid message")
		}

		req, ok := message["request"].(map[string]interface{})
		if !ok {
			m.logger.Error("Invalid message", zap.Any("data", data))
			return fmt.Errorf("invalid message")
		}

		// Execute command
		result, err := m.cmd.Execute(ctx,
			Command{
				Command:   Cmd(cmd),
				Arguments: req,
			})
		if err != nil {
			m.logger.Error("Failed to execute command", zap.Error(err))
			return err
		}

		// Send result to relayer
		err = m.relayer.Send(ctx,
			map[string]interface{}{
				"messageID": messageID,
				"message":   result,
			})
		if err != nil {
			m.logger.Error("Failed to send acknowledgement to relayer", zap.Error(err))
			return err
		}
	}

	return nil
}
