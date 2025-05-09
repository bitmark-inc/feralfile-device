package main

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"github.com/godbus/dbus/v5"
	"go.uber.org/zap"
)

const (
	EVENT_SETUPD_WIFI_CONNECTED       = "wifi_connected"
	EVENT_STATED_DEVICE_CONNECTED     = "device_connected"
	EVENT_CONNECTD_RELAYER_CONFIGURED = "relayer_configured"

	DBUS_INTERFACE = "com.feralfile.connectd.general"
	DBUS_PATH      = "/com/feralfile/connectd"
)

type BusSignalHandler func(ctx context.Context, iface string, path dbus.ObjectPath, member string, body []interface{}) error

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
				if sig != nil {
					c.logger.Info("Received signal", zap.String("interface", sig.Name))
					if err := c.handleSignalRecv(sig); err != nil {
						c.logger.Error("Failed to handle signal", zap.Error(err))
					}
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
	member := sig.Name[i+1:]

	for _, handler := range c.busSignalHandlers {
		if err := handler(c.ctx, iface, sig.Path, member, sig.Body); err != nil {
			c.logger.Warn("Failed to handle signal", zap.String("interface", iface), zap.String("member", member), zap.Error(err))
		}
	}

	return nil
}

func (c *DBusClient) Send(
	iface string,
	path dbus.ObjectPath,
	member string,
	values ...interface{}) error {
	c.Lock()
	defer c.Unlock()

	return c.conn.Emit(path, iface+"."+member, values...)
}

func (c *DBusClient) Stop() error {
	c.Lock()
	defer c.Unlock()

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
