package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

type Cmd string

const (
	CMD_CHECK_STATUS      Cmd = "checkStatus"
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
	dataHandler    *DataHandler
	cdp            *CDPClient
	dailyScheduler *time.Timer
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

func NewCommand(dataHandler *DataHandler, cdp *CDPClient) *Command {
	return &Command{
		dataHandler: dataHandler,
		cdp:         cdp,
	}
}

func (c *Command) Execute(ctx context.Context, cmd Cmd, args map[string]interface{}) (interface{}, error) {
	bytes, err := json.Marshal(args)
	if err != nil {
		return nil, fmt.Errorf("invalid arguments: %s", err)
	}

	switch cmd {
	case CMD_CHECK_STATUS:
		return c.checkStatus()
	case CMD_CAST_LIST_ARTWORK:
		return c.castListArtwork(ctx, bytes)
	case CMD_CAST_EXHIBITION:
		return c.castExhibition(bytes)
	case CMD_CAST_DAILY:
		return c.castDaily(ctx)
	default:
		return nil, fmt.Errorf("invalid command: %s", cmd)
	}
}

func (c *Command) checkStatus() (interface{}, error) {
	return nil, nil
}

func (c *Command) castListArtwork(ctx context.Context, args []byte) (interface{}, error) {
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

func (c *Command) castExhibition(args []byte) (interface{}, error) {
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

	err = c.cdp.SendCDPRequest(CDP_METHOD_EVALUATE,
		map[string]interface{}{
			"expression": fmt.Sprintf(
				`window.handleCDPRequest({
				command: "castExhibition",
				params: {
					exhibitionId: "%s",
					catalogId: "%s",
					catalog: %d,
				},
			});`,
				cmdArgs.ExhibitionID,
				cmdArgs.CatalogID,
				cmdArgs.Catalog,
			),
		})
	if err != nil {
		return nil, fmt.Errorf("failed to send CDP request: %s", err)
	}

	return CmdOK, nil
}

func (c *Command) castDaily(ctx context.Context) (interface{}, error) {
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
		indexIDs = append(indexIDs, daily.TokenID)
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

func (c *Command) cdpPlayArtwork(args CdpPlayArtworkArgs) error {
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
