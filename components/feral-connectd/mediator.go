package main

import (
	"context"
	"fmt"

	"go.uber.org/zap"
)

type Mediator struct {
	relayer      *RelayerClient
	dbus         *DBusClient
	cdp          *CDPClient
	cmd          *CommandHandler
	profiler     *Profiler
	logger       *zap.Logger
	connectivity *Connectivity
}

func NewMediator(
	relayer *RelayerClient,
	dbus *DBusClient,
	cdp *CDPClient,
	cmd *CommandHandler,
	connectivity *Connectivity,
	profiler *Profiler,
	logger *zap.Logger) *Mediator {
	return &Mediator{
		relayer:      relayer,
		dbus:         dbus,
		cdp:          cdp,
		cmd:          cmd,
		connectivity: connectivity,
		profiler:     profiler,
		logger:       logger,
	}
}

func (m *Mediator) Start() {
	m.dbus.OnBusSignal(m.handleDBusSignal)
	m.relayer.OnRelayerMessage(m.handleRelayerMessage)
	m.connectivity.OnConnectivityChange(m.handleConnectivityChange)
	m.profiler.OnProfile(m.handleProfile)
}

func (m *Mediator) Stop() {
	m.profiler.RemoveProfileHandler(m.handleProfile)
	m.connectivity.RemoveConnectivityChange(m.handleConnectivityChange)
	m.relayer.RemoveRelayerMessage(m.handleRelayerMessage)
	m.dbus.RemoveBusSignal(m.handleDBusSignal)
}

func (m *Mediator) handleDBusSignal(
	ctx context.Context,
	payload DBusPayload) ([]interface{}, error) {
	if payload.Member.IsACK() {
		return nil, nil
	}

	m.logger.Info(
		"Handle DBus signal",
		zap.String("interface", payload.Interface),
		zap.String("path", string(payload.Path)),
		zap.String("member", payload.Member.String()),
		zap.Any("body", payload.Body),
	)

	switch payload.Member {
	case EVENT_SETUPD_WIFI_CONNECTED:
		// Connect to the relayer
		err := m.relayer.RetryableConnect(ctx)
		if err != nil {
			m.logger.Error("Failed to connect to relayer", zap.Error(err))
		}

		// Wait for the relayer to be connected
		if !GetState().WaitForRelayerChanReady(ctx) {
			m.logger.Error("Relayer channel is not ready")
			return nil, fmt.Errorf("relayer channel is not ready")
		}

		// Send the locationID and topicID to the setupd
		relayer := GetState().Relayer
		err = m.dbus.RetryableSend(ctx, DBusPayload{
			Interface: DBUS_INTERFACE,
			Path:      DBUS_PATH,
			Member:    EVENT_CONNECTD_RELAYER_CONFIGURED,
			Body: []interface{}{
				relayer.LocationID,
				relayer.TopicID,
			},
		})
		if err != nil {
			m.logger.Error("Failed to send DBus signal", zap.Error(err), zap.String("interface", DBUS_INTERFACE), zap.String("path", DBUS_PATH), zap.String("member", EVENT_CONNECTD_RELAYER_CONFIGURED.String()))
			return nil, err
		}

		return []interface{}{
			relayer.LocationID,
			relayer.TopicID,
		}, nil

	default:
		m.logger.Warn("Unknown signal", zap.String("member", payload.Member.String()))
	}

	return nil, nil
}

func (m *Mediator) handleRelayerMessage(ctx context.Context, payload RelayerPayload) error {
	m.logger.Info("Received relayer message", zap.Any("payload", payload))

	switch payload.MessageID {
	case RELAYER_MESSAGE_ID_SYSTEM:
		locationID := payload.Message.LocationID
		topicID := payload.Message.TopicID
		if locationID == nil || topicID == nil {
			m.logger.Error("Payload doesn't contain locationID or topicID", zap.Any("payload", payload))
			return fmt.Errorf("payload doesn't contain locationID or topicID")
		}

		// Save state
		state := GetState()
		state.Relayer.LocationID = *locationID
		state.Relayer.TopicID = *topicID
		err := state.Save()
		if err != nil {
			m.logger.Error("Failed to persist state", zap.Error(err))
			return err
		}
	default:
		cmd := payload.Message.Command
		if cmd == nil {
			m.logger.Warn("Received relayer message with no command", zap.Any("payload", payload))
			return nil
		}

		if cmd.CDPCmd() {
			p, err := payload.JSON()
			if err != nil {
				m.logger.Error("Failed to marshal payload", zap.Error(err))
				return err
			}

			result, err := m.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
				"expression": fmt.Sprintf("window.handleCDPRequest(%s)", string(p)),
			})
			if err != nil {
				m.logger.Error("Failed to send CDP request", zap.Error(err))
				return err
			}

			return m.relayer.Send(ctx, result)
		} else {
			result, err := m.cmd.Execute(ctx,
				Command{
					Command:   *cmd,
					Arguments: payload.Message.Args,
				})
			if err != nil {
				m.logger.Error("Failed to execute command", zap.Error(err))
				return err
			}

			return m.relayer.Send(ctx,
				map[string]interface{}{
					"messageID": payload.MessageID,
					"message":   result,
				})
		}
	}

	return nil
}

func (m *Mediator) handleConnectivityChange(ctx context.Context, connected bool) {
	m.logger.Info("Connectivity changed", zap.Bool("connected", connected))

	// Send the connectivity change to web app
	_, err := m.cdp.SendCDPRequest(
		CDP_METHOD_EVALUATE,
		map[string]interface{}{
			"expression": fmt.Sprintf("window.handleConnectivityChange(%t)", connected),
		})
	if err != nil {
		m.logger.Error("Failed to send CDP request", zap.Error(err))
	}

	// Reconnect the relayer if it's not already connected
	if connected && !m.relayer.IsConnected() {
		err := m.relayer.RetryableConnect(ctx)
		if err != nil {
			m.logger.Error("Failed to reconnect to relayer", zap.Error(err))
			panic(err)
		}
	}
}

func (m *Mediator) handleProfile(profile *Profile) {
	// TODO broadcast dbus signal
}
