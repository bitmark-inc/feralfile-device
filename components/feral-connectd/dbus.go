package main

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"github.com/godbus/dbus/v5"
	"go.uber.org/zap"
)

type DBusMember string

const (
	EVENT_SETUPD_WIFI_CONNECTED       DBusMember = "wifi_connected"
	EVENT_CONNECTD_RELAYER_CONFIGURED DBusMember = "relayer_configured"

	DBUS_INTERFACE = "com.feralfile.connectd.general"
	DBUS_PATH      = "/com/feralfile/connectd"
)

func (e DBusMember) String() string {
	return string(e)
}

func (e DBusMember) ACK() DBusMember {
	return DBusMember(fmt.Sprintf("%s_ACK", e))
}

type BusSignalHandler func(
	ctx context.Context,
	iface string,
	path dbus.ObjectPath,
	member DBusMember,
	body []interface{}) ([]interface{}, error)

type DBusClient struct {
	sync.Mutex

	ctx               context.Context
	relayer           *RelayerClient
	conn              *dbus.Conn
	sigChan           chan *dbus.Signal
	doneChan          chan struct{}
	logger            *zap.Logger
	busSignalHandlers []BusSignalHandler
}

func NewDBusClient(ctx context.Context, logger *zap.Logger, relayer *RelayerClient) *DBusClient {
	return &DBusClient{
		ctx:               ctx,
		relayer:           relayer,
		sigChan:           make(chan *dbus.Signal, 10),
		doneChan:          make(chan struct{}),
		logger:            logger,
		busSignalHandlers: []BusSignalHandler{},
	}
}

func (c *DBusClient) Start() error {
	c.logger.Info("Starting DBusClient")
	conn, err := dbus.SessionBus()
	if err != nil {
		return err
	}
	c.conn = conn
	conn.Signal(c.sigChan)

	err = conn.AddMatchSignalContext(c.ctx,
		dbus.WithMatchPathNamespace(dbus.ObjectPath("/com/feralfile")),
	)

	if err != nil {
		return err
	}

	c.background()

	return nil
}

func (c *DBusClient) background() {
	go func() {
		c.logger.Info("DBusClient background goroutine started")
		for {
			select {
			case <-c.ctx.Done():
				c.logger.Info("Context cancelled, stopping DBusClient")
				c.Stop()
				return
			case <-c.doneChan:
				c.logger.Info("DBusClient stopped")
				return
			case sig := <-c.sigChan:
				if sig == nil {
					c.logger.Warn("Received nil signal")
					continue
				}

				c.logger.Info("Received signal", zap.String("interface", sig.Name))
				if err := c.handleSignalRecv(sig); err != nil {
					c.logger.Error("Failed to handle signal", zap.Error(err))
				}
			}
		}
	}()
}

func (c *DBusClient) OnBusSignal(f BusSignalHandler) {
	c.Lock()
	defer c.Unlock()
	c.busSignalHandlers = append(c.busSignalHandlers, f)
}

func (c *DBusClient) RemoveBusSignal(f BusSignalHandler) {
	c.Lock()
	defer c.Unlock()

	for i, handler := range c.busSignalHandlers {
		if fmt.Sprintf("%p", handler) == fmt.Sprintf("%p", f) {
			c.busSignalHandlers = append(c.busSignalHandlers[:i], c.busSignalHandlers[i+1:]...)
			break
		}
	}
}

func (c *DBusClient) handleSignalRecv(sig *dbus.Signal) error {
	i := strings.LastIndex(sig.Name, ".")
	if i == -1 {
		return fmt.Errorf("invalid signal name: %s", sig.Name)
	}
	iface := sig.Name[:i]
	member := DBusMember(sig.Name[i+1:])

	for _, handler := range c.busSignalHandlers {
		result, err := handler(c.ctx, iface, sig.Path, member, sig.Body)
		if err != nil {
			c.logger.Warn("Failed to handle signal", zap.String("interface", iface), zap.String("member", member.String()), zap.Error(err))
			continue
		}
		if result != nil {
			err = c.ACK(iface, sig.Path, member, result...)
			if err != nil {
				c.logger.Warn("Failed to send ACK", zap.String("interface", iface), zap.String("member", member.String()), zap.Error(err))
			}
		}
	}

	return nil
}

func (c *DBusClient) ACK(
	iface string,
	path dbus.ObjectPath,
	member DBusMember,
	values ...interface{}) error {
	return c.Send(iface, path, member.ACK(), values...)
}

func (c *DBusClient) Send(
	iface string,
	path dbus.ObjectPath,
	member DBusMember,
	values ...interface{}) error {
	c.Lock()
	defer c.Unlock()

	c.logger.Info("Sending signal", zap.String("interface", iface), zap.String("member", member.String()), zap.Any("values", values))
	return c.conn.Emit(path, iface+"."+member.String(), values...)
}

func (c *DBusClient) Stop() error {
	c.Lock()
	defer c.Unlock()

	c.logger.Info("Stopping DBusClient")

	select {
	case <-c.doneChan:
		return nil
	default:
		close(c.doneChan)
	}

	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
		c.logger.Info("DBusClient connection closed")
	}

	return nil
}
