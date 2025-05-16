package main

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"

	"github.com/feral-file/godbus"
	"go.uber.org/zap"
)

var CmdOK = struct {
	OK bool `json:"ok"`
}{
	OK: true,
}

type Command struct {
	Command   RelayerCmd
	Arguments map[string]interface{}
}

type Device struct {
	ID       string `json:"device_id"`
	Name     string `json:"device_name"`
	Platform int    `json:"platform"`
}

type CommandHandler struct {
	sync.Mutex
	cdp    *CDPClient
	dbus   *godbus.DBusClient
	logger *zap.Logger

	lastSysMetrics []byte
}

func NewCommandHandler(cdp *CDPClient, dbus *godbus.DBusClient, logger *zap.Logger) *CommandHandler {
	return &CommandHandler{
		cdp:    cdp,
		dbus:   dbus,
		logger: logger,
	}
}

func (c *CommandHandler) saveLastSysMetrics(metrics []byte) {
	c.Lock()
	defer c.Unlock()
	c.lastSysMetrics = metrics
}

func (c *CommandHandler) Execute(ctx context.Context, cmd Command) (interface{}, error) {
	c.logger.Info("Executing command", zap.String("command", string(cmd.Command)))

	var err error
	var bytes []byte

	bytes, err = json.Marshal(cmd.Arguments)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	var result interface{}
	switch cmd.Command {
	case RELAYER_CMD_CONNECT:
		result, err = c.connect(bytes)
	case RELAYER_CMD_SHOW_PAIRING_QR_CODE:
		result, err = c.showPairingQRCode(ctx, bytes)
	case RELAYER_CMD_SYS_METRICS:
		c.Lock()
		defer c.Unlock()
		return c.lastSysMetrics, nil
	default:
		return nil, fmt.Errorf("invalid command: %s", cmd)
	}

	return result, err
}

func (c *CommandHandler) connect(args []byte) (interface{}, error) {
	var cmdArgs struct {
		Device         Device `json:"clientDevice"`
		PrimaryAddress string `json:"primaryAddress"`
	}
	err := json.Unmarshal(args, &cmdArgs)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	state := GetState()
	state.ConnectedDevice = &cmdArgs.Device
	err = state.Save()
	if err != nil {
		return nil, fmt.Errorf("failed to save state: %s", err)
	}

	return CmdOK, nil
}

func (c *CommandHandler) showPairingQRCode(ctx context.Context, args []byte) (interface{}, error) {
	var cmdArgs struct {
		Show bool `json:"show"`
	}
	err := json.Unmarshal(args, &cmdArgs)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	err = c.dbus.RetryableSend(ctx,
		godbus.DBusPayload{
			Interface: DBUS_INTERFACE,
			Path:      DBUS_PATH,
			Member:    DBUS_SETUPD_EVENT_SHOW_PAIRING_QR_CODE,
			Body:      []interface{}{cmdArgs.Show},
		})
	return CmdOK, nil
}
