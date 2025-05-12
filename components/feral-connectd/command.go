package main

import (
	"context"
	"encoding/json"
	"fmt"

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
	cdp    *CDPClient
	logger *zap.Logger

	lastCDPCmd *Command
}

func NewCommandHandler(cdp *CDPClient, logger *zap.Logger) *CommandHandler {
	return &CommandHandler{
		cdp:    cdp,
		logger: logger,
	}
}

func (c *CommandHandler) Execute(ctx context.Context, cmd Command) (interface{}, error) {
	c.logger.Info("Executing command", zap.String("command", string(cmd.Command)))

	var err error
	var bytes []byte
	defer func() {
		if err == nil && cmd.Command.CDPCmd() {
			c.lastCDPCmd = &cmd
		}
	}()

	bytes, err = json.Marshal(cmd.Arguments)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	var result interface{}
	switch cmd.Command {
	case RELAYER_CMD_CHECK_STATUS:
		result, err = c.checkStatus()
	case RELAYER_CMD_CONNECT:
		result, err = c.connect(bytes)
	default:
		return nil, fmt.Errorf("invalid command: %s", cmd)
	}

	return result, err
}

type CheckStatusResp struct {
	Device   *Device                `json:"device"`
	Command  *Command               `json:"lastCDPCmd"`
	CDPState map[string]interface{} `json:"cdpState"`
}

func (c *CommandHandler) checkStatus() (interface{}, error) {
	return &struct {
		OK    bool             `json:"ok"`
		State *CheckStatusResp `json:"state"`
	}{
		OK: true,
		State: &CheckStatusResp{
			Device:   GetState().ConnectedDevice,
			Command:  c.lastCDPCmd,
			CDPState: nil, // TODO: implement later after the prototype is done
		},
	}, nil
}

type ConnectArgs struct {
	Device         Device `json:"clientDevice"`
	PrimaryAddress string `json:"primaryAddress"`
}

func (c *CommandHandler) connect(args []byte) (interface{}, error) {
	var cmdArgs ConnectArgs
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
