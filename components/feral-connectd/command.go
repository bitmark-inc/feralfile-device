package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"go.uber.org/zap"
)

type Cmd string

const (
	CMD_CHECK_STATUS      Cmd = "checkStatus"
	CMD_CONNECT           Cmd = "connect"
	CMD_CAST_LIST_ARTWORK Cmd = "castListArtwork"
	CMD_CAST_EXHIBITION   Cmd = "castExhibition"
	CMD_CAST_DAILY        Cmd = "castDaily"
)

var CmdOK = struct {
	OK bool `json:"ok"`
}{
	OK: true,
}

type Command struct {
	Command   Cmd
	Arguments map[string]interface{}
}

type Device struct {
	ID       string `json:"device_id"`
	Name     string `json:"device_name"`
	Platform int    `json:"platform"`
}

type CommandHandler struct {
	dataHandler    *DataHandler
	cdp            *CDPClient
	dailyScheduler *time.Timer
	logger         *zap.Logger

	lastCDPCmd *Command
}

type CmdCastArtworkArgs struct {
	StartTime float64 `json:"startTime"`
	Artworks  []struct {
		Duration int `json:"duration"`
		Token    struct {
			Id string `json:"id"`
		} `json:"token"`
	} `json:"artworks"`
}

type CmdCastExhibitionArgs struct {
	ExhibitionID string `json:"exhibitionId"`
	CatalogID    string `json:"catalogId"`
	Catalog      int    `json:"catalog"`
}

func NewCommandHandler(dataHandler *DataHandler, cdp *CDPClient, logger *zap.Logger) *CommandHandler {
	return &CommandHandler{
		dataHandler: dataHandler,
		cdp:         cdp,
		logger:      logger,
	}
}

func (c *CommandHandler) Execute(ctx context.Context, cmd Command) (interface{}, error) {
	var err error
	var bytes []byte
	defer func() {
		if err == nil && cmd.Command != CMD_CHECK_STATUS {
			c.lastCDPCmd = &cmd
		}
	}()

	bytes, err = json.Marshal(cmd.Arguments)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	var result interface{}
	switch cmd.Command {
	case CMD_CHECK_STATUS:
		result, err = c.checkStatus()
	case CMD_CONNECT:
		result, err = c.connect(bytes)
	case CMD_CAST_LIST_ARTWORK:
		result, err = c.castListArtwork(ctx, bytes)
	case CMD_CAST_EXHIBITION:
		result, err = c.castExhibition(ctx, bytes)
	case CMD_CAST_DAILY:
		result, err = c.castDaily(ctx)
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
	c.logger.Info("Checking status...")
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

func (c *CommandHandler) castListArtwork(ctx context.Context, args []byte) (interface{}, error) {
	c.logger.Info("Casting list artwork...", zap.Any("args", args))

	// Cancel any scheduled daily task
	if c.dailyScheduler != nil {
		c.dailyScheduler.Stop()
		c.dailyScheduler = nil
	}

	var cmdArgs CmdCastArtworkArgs
	err := json.Unmarshal(args, &cmdArgs)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	var indexIDs []string
	indexIDDurationMap := make(map[string]int)
	for _, artwork := range cmdArgs.Artworks {
		indexID := artwork.Token.Id
		indexIDs = append(indexIDs, indexID)
		indexIDDurationMap[indexID] = artwork.Duration
	}

	tokens, err := c.dataHandler.IC.getTokens(ctx, indexIDs)
	if err != nil {
		return nil, fmt.Errorf("failed to get tokens: %s", err)
	}
	if len(tokens) == 0 {
		return nil, fmt.Errorf("no tokens found")
	}

	var cdpArgs []CdpPlayArtworkArgs
	for _, token := range tokens {
		cdpArgs = append(cdpArgs, CdpPlayArtworkArgs{
			URL:      token.Asset.Metadata.Project.Latest.PreviewURL,
			MIMEType: token.Asset.Metadata.Project.Latest.MIMEType,
			Mode:     "fit",
		})
	}

	// TODO: handle multiple artworks playing
	err = c.cdpPlayArtwork(cdpArgs[0])
	if err != nil {
		return nil, fmt.Errorf("failed to play artwork: %s", err)
	}

	return CmdOK, nil
}

type ConnectArgs struct {
	Device         Device `json:"clientDevice"`
	PrimaryAddress string `json:"primaryAddress"`
}

func (c *CommandHandler) connect(args []byte) (interface{}, error) {
	c.logger.Info("Device connected...", zap.Any("args", args))

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

func (c *CommandHandler) castExhibition(ctx context.Context, args []byte) (interface{}, error) {
	c.logger.Info("Casting exhibition...", zap.Any("args", args))

	// Cancel any scheduled daily task
	if c.dailyScheduler != nil {
		c.dailyScheduler.Stop()
		c.dailyScheduler = nil
	}

	var cmdArgs CmdCastExhibitionArgs
	err := json.Unmarshal(args, &cmdArgs)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	// TODO: temporary disabled
	if cmdArgs.Catalog != 4 {
		return nil, fmt.Errorf("temporary disabled: %d", cmdArgs.Catalog)
	}

	artwork, err := c.dataHandler.FF.GetArtwork(ctx, cmdArgs.CatalogID)
	if err != nil {
		return nil, fmt.Errorf("failed to get artwork: %s", err)
	}
	if artwork == nil {
		return nil, fmt.Errorf("artwork not found")
	}
	if artwork.PreviewMIMEType == nil {
		return nil, fmt.Errorf("artwork preview MIME type not found")
	}

	cdpArgs := CdpPlayArtworkArgs{
		URL:      artwork.GetPreviewURL(),
		MIMEType: *artwork.PreviewMIMEType,
		Mode:     "fit",
	}

	err = c.cdpPlayArtwork(cdpArgs)
	if err != nil {
		return nil, fmt.Errorf("failed to play artwork: %s", err)
	}

	return CmdOK, nil
}

func (c *CommandHandler) castDaily(ctx context.Context) (interface{}, error) {
	// Cancel any existing scheduled task
	if c.dailyScheduler != nil {
		c.dailyScheduler.Stop()
		c.dailyScheduler = nil
	}

	now := time.Now()
	date := time.Date(now.Year(), now.Month(), now.Day(), 2, 0, 0, 0, now.Location())
	nextDate := date.AddDate(0, 0, 1)

	// Schedule for the next day at 2am
	duration := nextDate.Sub(now)
	c.dailyScheduler = time.AfterFunc(duration, func() {
		_, _ = c.castDaily(ctx)
	})

	dailies, err := c.dataHandler.FF.GetDaily(ctx, date)
	if err != nil {
		return nil, fmt.Errorf("failed to get daily: %s", err)
	}

	if len(dailies) == 0 {
		return nil, fmt.Errorf("no daily found")
	}

	var indexIDs []string
	for _, daily := range dailies {
		indexIDs = append(indexIDs, GetIndexID(daily.Blockchain, daily.ContractAddress, daily.TokenID))
	}

	tokens, err := c.dataHandler.IC.getTokens(ctx, indexIDs)
	if err != nil {
		return nil, fmt.Errorf("failed to get tokens: %s", err)
	}
	if len(tokens) == 0 {
		return nil, fmt.Errorf("no tokens found")
	}

	var cdpArgs []CdpPlayArtworkArgs
	for _, token := range tokens {
		cdpArgs = append(cdpArgs, CdpPlayArtworkArgs{
			URL:      token.Asset.Metadata.Project.Latest.PreviewURL,
			MIMEType: token.Asset.Metadata.Project.Latest.MIMEType,
			Mode:     "fit",
		})
	}

	// TODO: handle multiple daily playing
	err = c.cdpPlayArtwork(cdpArgs[0])
	if err != nil {
		return nil, fmt.Errorf("failed to play daily: %s", err)
	}

	return CmdOK, nil
}

type CdpPlayArtworkArgs struct {
	URL      string
	MIMEType string
	Mode     string
}

func (c *CommandHandler) cdpPlayArtwork(args CdpPlayArtworkArgs) error {
	err := c.cdp.SendCDPRequest(CDP_METHOD_EVALUATE,
		map[string]interface{}{
			"expression": fmt.Sprintf(
				`window.handleCDPRequest({
					command: "setArtwork",
					params: {
						url: "%s",
						mimeType: "%s",
						mode: "%s",
					},
				});`,
				args.URL,
				args.MIMEType,
				args.Mode,
			),
		})
	if err != nil {
		return fmt.Errorf("failed to send CDP request: %s", err)
	}

	return nil
}
