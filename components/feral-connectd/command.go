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

	// Prepare CDP command to dispatch a key event
	keyEventParams := map[string]interface{}{
		"type":                  "keyDown",
		"windowsVirtualKeyCode": cmdArgs.Code,
		"key":                   keyName,
		"text":                  keyName,
		"unmodifiedText":        keyName,
		"nativeVirtualKeyCode":  cmdArgs.Code,
	}

	// Send key directly via CDP
	result, err := c.cdp.SendCDPRequest("Input.dispatchKeyEvent", keyEventParams)
	if err != nil {
		c.logger.Error("Failed to send key via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to send keyboard event: %s", err)
	}
	c.logger.Info("KeyDown result", zap.Any("result", result))

	// For keys that need keyUp events as well (like letters)
	if cmdArgs.Code >= 32 {
		keyEventParams["type"] = "keyUp"
		upResult, err := c.cdp.SendCDPRequest("Input.dispatchKeyEvent", keyEventParams)
		if err != nil {
			c.logger.Error("Failed to send keyUp via CDP", zap.Error(err))
		} else {
			c.logger.Info("KeyUp result", zap.Any("result", upResult))
		}
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
		// Use relative movements based on cursor offsets
		var x, y float64 = 100, 100 // Default starting position

		// Apply movements sequentially
		for _, movement := range cursorArgs.CursorOffsets {
			x += movement.DX * 3
			y += movement.DY * 3

			// Send mouseMoved event
			moveParams := map[string]interface{}{
				"type":       "mouseMoved",
				"x":          x,
				"y":          y,
				"button":     "none",
				"buttons":    0,
				"clickCount": 0,
			}

			result, err := c.cdp.SendCDPRequest("Input.dispatchMouseEvent", moveParams)
			if err != nil {
				c.logger.Error("Failed to send mouse move via CDP", zap.Error(err))
				return nil, fmt.Errorf("failed to move mouse: %s", err)
			}
			c.logger.Info("MouseMove result", zap.Any("result", result))
		}

		return CmdOK, nil
	}

	// Standard drag event with absolute coordinates
	var dragArgs struct {
		StartX int `json:"startX"`
		StartY int `json:"startY"`
		EndX   int `json:"endX"`
		EndY   int `json:"endY"`
	}

	if err := json.Unmarshal(args, &dragArgs); err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	// 1. Move to start position
	moveParams := map[string]interface{}{
		"type":       "mouseMoved",
		"x":          float64(dragArgs.StartX),
		"y":          float64(dragArgs.StartY),
		"button":     "none",
		"buttons":    0,
		"clickCount": 0,
	}

	result, err := c.cdp.SendCDPRequest("Input.dispatchMouseEvent", moveParams)
	if err != nil {
		c.logger.Error("Failed to move mouse to start position via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to move to start position: %s", err)
	}
	c.logger.Info("MouseMove to start result", zap.Any("result", result))

	// 2. Press mouse button down
	downParams := map[string]interface{}{
		"type":       "mousePressed",
		"x":          float64(dragArgs.StartX),
		"y":          float64(dragArgs.StartY),
		"button":     "left",
		"buttons":    1,
		"clickCount": 1,
	}

	result, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", downParams)
	if err != nil {
		c.logger.Error("Failed to press mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to press mouse button: %s", err)
	}
	c.logger.Info("MouseDown result", zap.Any("result", result))

	// 3. Move to end position
	dragParams := map[string]interface{}{
		"type":       "mouseMoved",
		"x":          float64(dragArgs.EndX),
		"y":          float64(dragArgs.EndY),
		"button":     "left",
		"buttons":    1,
		"clickCount": 0,
	}

	result, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", dragParams)
	if err != nil {
		c.logger.Error("Failed to drag mouse via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to drag mouse: %s", err)
	}
	c.logger.Info("MouseDrag result", zap.Any("result", result))

	// 4. Release mouse button
	upParams := map[string]interface{}{
		"type":       "mouseReleased",
		"x":          float64(dragArgs.EndX),
		"y":          float64(dragArgs.EndY),
		"button":     "left",
		"buttons":    0,
		"clickCount": 1,
	}

	result, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", upParams)
	if err != nil {
		c.logger.Error("Failed to release mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to release mouse button: %s", err)
	}
	c.logger.Info("MouseUp result", zap.Any("result", result))

	return CmdOK, nil
}

func (c *CommandHandler) handleMouseTapEvent(ctx context.Context, args []byte) (interface{}, error) {
	// Fixed position for click (center of screen)
	x, y := 100, 100
	button := "left"

	c.logger.Info("Mouse tap event")

	// 1. Press mouse button
	downParams := map[string]interface{}{
		"type":       "mousePressed",
		"x":          float64(x),
		"y":          float64(y),
		"button":     button,
		"buttons":    1,
		"clickCount": 1,
	}

	result, err := c.cdp.SendCDPRequest("Input.dispatchMouseEvent", downParams)
	if err != nil {
		c.logger.Error("Failed to press mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to press mouse button: %s", err)
	}
	c.logger.Info("MouseDown result", zap.Any("result", result))

	// 2. Release mouse button
	upParams := map[string]interface{}{
		"type":       "mouseReleased",
		"x":          float64(x),
		"y":          float64(y),
		"button":     button,
		"buttons":    0,
		"clickCount": 1,
	}

	result, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", upParams)
	if err != nil {
		c.logger.Error("Failed to release mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to release mouse button: %s", err)
	}
	c.logger.Info("MouseUp result", zap.Any("result", result))

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
