package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math"

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
	cdp      *CDPClient
	dbus     *godbus.DBusClient
	profiler *Profiler
	logger   *zap.Logger

	lastCDPCmd *Command

	// Mouse position tracking
	cursorPositionX   float64
	cursorPositionY   float64
	screenWidth       float64
	screenHeight      float64
	screenInitialized bool
}

func NewCommandHandler(cdp *CDPClient, dbus *godbus.DBusClient, profiler *Profiler, logger *zap.Logger) *CommandHandler {
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

	err = c.dbus.RetryableSend(ctx,
		godbus.DBusPayload{
			Interface: DBUS_INTERFACE,
			Path:      DBUS_PATH,
			Member:    DBUS_SETUPD_EVENT_SHOW_PAIRING_QR_CODE,
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
	_, err = c.cdp.SendCDPRequest("Input.dispatchKeyEvent", keyEventParams)
	if err != nil {
		c.logger.Error("Failed to send key via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to send keyboard event: %s", err)
	}

	// For keys that need keyUp events as well (like letters)
	if cmdArgs.Code >= 32 {
		keyEventParams["type"] = "keyUp"
		_, err := c.cdp.SendCDPRequest("Input.dispatchKeyEvent", keyEventParams)
		if err != nil {
			c.logger.Error("Failed to send keyUp via CDP", zap.Error(err))
		}
	}

	return CmdOK, nil
}

func (c *CommandHandler) initializeScreenDimensions(ctx context.Context) error {
	if c.screenInitialized {
		return nil
	}

	// Get screen dimensions using CDP's Runtime.evaluate
	evalParams := map[string]interface{}{
		"expression":    "({width: window.innerWidth, height: window.innerHeight})",
		"returnByValue": true,
	}

	result, err := c.cdp.SendCDPRequest("Runtime.evaluate", evalParams)
	if err != nil {
		c.logger.Error("Failed to get screen dimensions", zap.Error(err))
		// Use default values
		c.screenWidth = 1920
		c.screenHeight = 1080
	} else if result != nil {
		if dimensions, ok := result.(map[string]interface{}); ok {
			if width, ok := dimensions["width"].(float64); ok {
				c.screenWidth = width
			} else {
				c.screenWidth = 1920
			}
			if height, ok := dimensions["height"].(float64); ok {
				c.screenHeight = height
			} else {
				c.screenHeight = 1080
			}
		}
	}

	// Initialize cursor at the center of the screen
	c.cursorPositionX = c.screenWidth / 2
	c.cursorPositionY = c.screenHeight / 2
	c.screenInitialized = true

	c.logger.Info("Screen dimensions initialized",
		zap.Float64("width", c.screenWidth),
		zap.Float64("height", c.screenHeight),
		zap.Float64("cursorX", c.cursorPositionX),
		zap.Float64("cursorY", c.cursorPositionY))

	return nil
}

func (c *CommandHandler) handleMouseDragEvent(ctx context.Context, args []byte) (interface{}, error) {
	// Initialize screen dimensions if not done already
	if err := c.initializeScreenDimensions(ctx); err != nil {
		return nil, err
	}

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
			// Scale the movements and update current position
			c.cursorPositionX += movement.DX * 3
			c.cursorPositionY += movement.DY * 3

			// Ensure position stays within screen bounds
			c.cursorPositionX = math.Max(0, math.Min(c.cursorPositionX, c.screenWidth))
			c.cursorPositionY = math.Max(0, math.Min(c.cursorPositionY, c.screenHeight))

			c.logger.Info("Mouse moved",
				zap.Float64("newX", c.cursorPositionX),
				zap.Float64("newY", c.cursorPositionY))

			// Send mouseMoved event
			moveParams := map[string]interface{}{
				"type":       "mouseMoved",
				"x":          c.cursorPositionX,
				"y":          c.cursorPositionY,
				"button":     "none",
				"buttons":    0,
				"clickCount": 0,
			}

			_, err := c.cdp.SendCDPRequest("Input.dispatchMouseEvent", moveParams)
			if err != nil {
				c.logger.Error("Failed to move mouse via CDP", zap.Error(err))
				return nil, fmt.Errorf("failed to move mouse: %s", err)
			}
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

	// Update the cached position to the start position
	c.cursorPositionX = float64(dragArgs.StartX)
	c.cursorPositionY = float64(dragArgs.StartY)

	// 1. Move to start position
	moveParams := map[string]interface{}{
		"type":       "mouseMoved",
		"x":          c.cursorPositionX,
		"y":          c.cursorPositionY,
		"button":     "none",
		"buttons":    0,
		"clickCount": 0,
	}

	_, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", moveParams)
	if err != nil {
		c.logger.Error("Failed to move mouse to start position via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to move to start position: %s", err)
	}

	// 2. Press mouse button down
	downParams := map[string]interface{}{
		"type":       "mousePressed",
		"x":          c.cursorPositionX,
		"y":          c.cursorPositionY,
		"button":     "left",
		"buttons":    1,
		"clickCount": 1,
	}

	_, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", downParams)
	if err != nil {
		c.logger.Error("Failed to press mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to press mouse button: %s", err)
	}

	// Update cached position to end position
	c.cursorPositionX = float64(dragArgs.EndX)
	c.cursorPositionY = float64(dragArgs.EndY)

	// 3. Move to end position
	dragParams := map[string]interface{}{
		"type":       "mouseMoved",
		"x":          c.cursorPositionX,
		"y":          c.cursorPositionY,
		"button":     "left",
		"buttons":    1,
		"clickCount": 0,
	}

	_, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", dragParams)
	if err != nil {
		c.logger.Error("Failed to drag mouse via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to drag mouse: %s", err)
	}

	// 4. Release mouse button
	upParams := map[string]interface{}{
		"type":       "mouseReleased",
		"x":          c.cursorPositionX,
		"y":          c.cursorPositionY,
		"button":     "left",
		"buttons":    0,
		"clickCount": 1,
	}

	_, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", upParams)
	if err != nil {
		c.logger.Error("Failed to release mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to release mouse button: %s", err)
	}

	return CmdOK, nil
}

func (c *CommandHandler) handleMouseTapEvent(ctx context.Context, args []byte) (interface{}, error) {
	// Initialize screen dimensions if not done already
	if err := c.initializeScreenDimensions(ctx); err != nil {
		return nil, err
	}

	c.logger.Info("Mouse tap event at current position",
		zap.Float64("x", c.cursorPositionX),
		zap.Float64("y", c.cursorPositionY))

	// 1. Press mouse button at current position
	downParams := map[string]interface{}{
		"type":       "mousePressed",
		"x":          c.cursorPositionX,
		"y":          c.cursorPositionY,
		"button":     "left",
		"buttons":    1,
		"clickCount": 1,
	}

	_, err := c.cdp.SendCDPRequest("Input.dispatchMouseEvent", downParams)
	if err != nil {
		c.logger.Error("Failed to press mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to press mouse button: %s", err)
	}

	// 2. Release mouse button
	upParams := map[string]interface{}{
		"type":       "mouseReleased",
		"x":          c.cursorPositionX,
		"y":          c.cursorPositionY,
		"button":     "left",
		"buttons":    0,
		"clickCount": 1,
	}

	_, err = c.cdp.SendCDPRequest("Input.dispatchMouseEvent", upParams)
	if err != nil {
		c.logger.Error("Failed to release mouse button via CDP", zap.Error(err))
		return nil, fmt.Errorf("failed to release mouse button: %s", err)
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
