package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"

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
	cdp      *CDPClient
	dbus     *DBusClient
	profiler *Profiler
	logger   *zap.Logger

	lastCDPCmd *Command
}

func NewCommandHandler(cdp *CDPClient, dbus *DBusClient, profiler *Profiler, logger *zap.Logger) *CommandHandler {
	return &CommandHandler{
		cdp:      cdp,
		dbus:     dbus,
		profiler: profiler,
		logger:   logger,
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
	case RELAYER_CMD_CONNECT:
		result, err = c.connect(bytes)
	case RELAYER_CMD_SHOW_PAIRING_QR_CODE:
		result, err = c.showPairingQRCode(ctx, bytes)
	case RELAYER_CMD_PROFILE:
		result = c.profiler.LastProfile()
	case RELAYER_CMD_KEYBOARD_EVENT:
		result, err = c.handleKeyboardEvent(ctx, bytes)
	case RELAYER_CMD_MOUSE_DRAG_EVENT:
		result, err = c.handleMouseDragEvent(ctx, bytes)
	case RELAYER_CMD_MOUSE_TAP_EVENT:
		result, err = c.handleMouseTapEvent(ctx, bytes)
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

	err = c.dbus.RetryableSend(ctx, DBusPayload{
		Interface: DBUS_INTERFACE,
		Path:      DBUS_PATH,
		Member:    EVENT_SETUPD_SHOW_PAIRING_QR_CODE,
		Body:      []interface{}{cmdArgs.Show},
	})
	return CmdOK, nil
}

func (c *CommandHandler) handleKeyboardEvent(ctx context.Context, args []byte) (interface{}, error) {
	var cmdArgs struct {
		Code int `json:"code"`
	}

	err := json.Unmarshal(args, &cmdArgs)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	keyName := ""
	if cmdArgs.Code >= 32 && cmdArgs.Code <= 126 {
		keyName = string(rune(cmdArgs.Code))
	} else {
		keyName = c.mapToYdoKey(cmdArgs.Code)
	}

	c.logger.Info("Keyboard event", zap.Int("code", cmdArgs.Code), zap.String("key", keyName))

	cmd := exec.CommandContext(ctx, "ydotool", "key", keyName)
	output, err := cmd.CombinedOutput()
	if err != nil {
		c.logger.Error("Failed to send keyboard event", zap.Error(err), zap.ByteString("output", output))
		return nil, fmt.Errorf("failed to send keyboard event: %s", err)
	}

	return CmdOK, nil
}

func (c *CommandHandler) handleMouseDragEvent(ctx context.Context, args []byte) (interface{}, error) {
	// Try to parse as cursor offsets format first
	var cursorArgs struct {
		CursorOffsets []struct {
			DX float64 `json:"dx"`
			DY float64 `json:"dy"`
		} `json:"cursorOffsets"`
	}

	err := json.Unmarshal(args, &cursorArgs)
	if err == nil && len(cursorArgs.CursorOffsets) > 0 {
		// Handle cursor offsets format (relative movements)
		for _, movement := range cursorArgs.CursorOffsets {
			moveX := int(movement.DX * 3)
			moveY := int(movement.DY * 3)

			cmd := exec.CommandContext(ctx, "ydotool", "mousemove_relative", "--",
				strconv.Itoa(moveX), strconv.Itoa(moveY))
			if err := cmd.Run(); err != nil {
				c.logger.Error("Failed to move mouse relatively", zap.Error(err))
				return nil, fmt.Errorf("failed to move mouse: %s", err)
			}
		}
		return CmdOK, nil
	}

	// Standard drag event
	var dragArgs struct {
		StartX int `json:"startX"`
		StartY int `json:"startY"`
		EndX   int `json:"endX"`
		EndY   int `json:"endY"`
	}

	if err := json.Unmarshal(args, &dragArgs); err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	// Move to start position
	cmd := exec.CommandContext(ctx, "ydotool", "mousemove",
		strconv.Itoa(dragArgs.StartX), strconv.Itoa(dragArgs.StartY))
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("failed to move to start position: %s", err)
	}

	// Press mouse button
	cmd = exec.CommandContext(ctx, "ydotool", "mousedown", "1")
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("failed to press mouse button: %s", err)
	}

	// Move to end position
	cmd = exec.CommandContext(ctx, "ydotool", "mousemove",
		strconv.Itoa(dragArgs.EndX), strconv.Itoa(dragArgs.EndY))
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("failed to move to end position: %s", err)
	}

	// Release mouse button
	cmd = exec.CommandContext(ctx, "ydotool", "mouseup", "1")
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("failed to release mouse button: %s", err)
	}

	return CmdOK, nil
}

func (c *CommandHandler) handleMouseTapEvent(ctx context.Context, args []byte) (interface{}, error) {
	// Just click at the current position
	cmd := exec.CommandContext(ctx, "ydotool", "click", "1")
	if err := cmd.Run(); err != nil {
		c.logger.Error("Failed to click", zap.Error(err))
		return nil, fmt.Errorf("failed to click: %s", err)
	}
	return CmdOK, nil
}

func (c *CommandHandler) mapToYdoKey(keyCode int) string {
	switch keyCode {
	case 32:
		return "space"
	case 9:
		return "tab"
	case 13:
		return "return"
	case 27:
		return "escape"
	case 8:
		return "backspace"
	case 37:
		return "left"
	case 38:
		return "up"
	case 39:
		return "right"
	case 40:
		return "down"
	default:
		c.logger.Warn("Unhandled key code", zap.Int("code", keyCode))
		return ""
	}
}
