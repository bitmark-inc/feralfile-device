package main

import (
	"context"
	"encoding/json"
	"fmt"
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
	dataHandler *DataHandler
	cdp         *CDPClient
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
		return c.castExhibition(ctx, bytes)
	case CMD_CAST_DAILY:
		return c.castDaily()
	default:
		return nil, fmt.Errorf("invalid command: %s", cmd)
	}
}

func (c *Command) checkStatus() (interface{}, error) {
	return nil, nil
}

func (c *Command) castListArtwork(ctx context.Context, args []byte) (interface{}, error) {
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

	type CDPArgs struct {
		URL      string
		MIMEType string
		Mode     string
		Duration int
	}
	var cdpArgs []CDPArgs
	for _, token := range tokens {
		cdpArgs = append(cdpArgs, CDPArgs{
			URL:      token.Asset.Metadata.Project.Latest.PreviewURL,
			MIMEType: token.Asset.Metadata.Project.Latest.MIMEType,
			Mode:     "fit",
			Duration: indexIDDurationMap[token.IndexID],
		})
	}

	// TODO: handle multiple artworks playing
	err = c.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": fmt.Sprintf(
			`window.handleCDPRequest({
                            command: "setArtwork",
                            params: {
                                url: "%s",
                                mimeType: "%s",
                                mode: "%s",
                            },
                        });`,
			cdpArgs[0].URL,
			cdpArgs[0].MIMEType,
			cdpArgs[0].Mode,
		),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to send CDP request: %s", err)
	}

	return CmdOK, nil
}

func (c *Command) castExhibition(ctx context.Context, args []byte) (interface{}, error) {
	return nil, nil
}

func (c *Command) castDaily() (interface{}, error) {
	return nil, nil
}
