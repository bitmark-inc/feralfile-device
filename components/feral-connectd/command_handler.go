package main

import (
	"encoding/json"
	"fmt"

	"go.uber.org/zap"
)

// define command enum
type Command string

const (
	CheckStatus     Command = "checkStatus"
	CastListArtwork Command = "castListArtwork"
	PauseCasting    Command = "pauseCasting"
	ResumeCasting   Command = "resumeCasting"
	NextArtwork     Command = "nextArtwork"
	PreviousArtwork Command = "previousArtwork"
	UpdateDuration  Command = "updateDuration"
	CastExhibition  Command = "castExhibition"
	CastDaily       Command = "castDaily"
)

// CommandHandler handles CDP commands
type CommandHandler struct {
	cdp    *CDPClient
	logger *zap.Logger
}

// NewCommandHandler creates a new command handler
func NewCommandHandler(cdp *CDPClient, logger *zap.Logger) *CommandHandler {
	return &CommandHandler{
		cdp:    cdp,
		logger: logger,
	}
}

// HandleWSMessage processes incoming commands
func (h *CommandHandler) HandleWSMessage(message map[string]interface{}) {
	command, ok := message["command"].(string)
	if !ok {
		h.logger.Error("No command found in message", zap.Any("message", message))
		return
	}

	request := message["request"].(map[string]interface{})

	switch Command(command) {
	case CheckStatus:
		h.checkStatus(CheckStatusRequest{})
	case CastListArtwork:
		req := CastListArtworkRequest{
			StartTime: int(request["startTime"].(float64)),
			Artworks:  make([]PlayArtwork, 0),
		}
		if artworks, ok := request["artworks"].([]interface{}); ok {
			for _, a := range artworks {
				artwork := a.(map[string]interface{})
				req.Artworks = append(req.Artworks, PlayArtwork{
					Id:       artwork["id"].(string),
					Duration: int(artwork["duration"].(float64)),
					Token: struct {
						Id string `json:"id"`
					}{
						Id: artwork["token"].(map[string]interface{})["id"].(string),
					},
				})
			}
		}
		h.castListArtwork(req)
	case PauseCasting:
		h.pauseCasting(PauseCastingRequest{})
	case ResumeCasting:
		h.resumeCasting(ResumeCastingRequest{})
	case NextArtwork:
		h.nextArtwork(NextArtworkRequest{})
	case PreviousArtwork:
		h.previousArtwork(PreviousArtworkRequest{})
	case UpdateDuration:
		req := UpdateDurationRequest{
			Artworks: make([]PlayArtwork, 0),
		}
		if artworks, ok := request["artworks"].([]interface{}); ok {
			for _, a := range artworks {
				artwork := a.(map[string]interface{})
				req.Artworks = append(req.Artworks, PlayArtwork{
					Id:       artwork["id"].(string),
					Duration: int(artwork["duration"].(float64)),
				})
			}
		}
		h.updateDuration(req)
	case CastExhibition:
		req := CastExhibitionRequest{
			ExhibitionId: request["exhibitionId"].(string),
			CatalogId:    request["catalogId"].(string),
			Catalog:      ExhibitionCatalog(request["catalog"].(string)),
		}
		h.castExhibition(req)
	case CastDaily:
		h.castDaily(CastDailyRequest{})
	default:
		h.logger.Error("Unknown command", zap.String("command", command))
	}
}

func (h *CommandHandler) checkStatus(request CheckStatusRequest) {
	h.logger.Info("Checking status")
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": `
	          window.handleCDPRequest({
							command: "checkStatus",
						});
	      `,
	})
	if err != nil {
		h.logger.Error("Failed to send checkStatus command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Check status response", zap.Any("response", resp))
}

func (h *CommandHandler) castListArtwork(request CastListArtworkRequest) {
	// Extract asset IDs from artworks
	assetIds := make([]string, 0, len(request.Artworks))
	for _, artwork := range request.Artworks {
		if artwork.Token.Id != "" {
			assetIds = append(assetIds, artwork.Token.Id)
		}
	}

	// Get NFT tokens
	artworks, err := h.getNFTTokens(assetIds)
	if err != nil {
		h.logger.Error("Failed to get NFT tokens", zap.Error(err))
		return
	}

	h.logger.Info("Artworks", zap.Any("artworks", artworks))

	artworksJSON, err := json.Marshal(request.Artworks)
	if err != nil {
		h.logger.Error("Failed to marshal artworks", zap.Error(err))
		return
	}

	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": fmt.Sprintf(`
			window.handleCDPRequest({
				command: "castListArtwork",
				params: {
					startTime: %d,
					artworks: %s
				}
			});
		`, request.StartTime, string(artworksJSON)),
	})
	if err != nil {
		h.logger.Error("Failed to send castListArtwork command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Cast list artwork response", zap.Any("response", resp))
}

func (h *CommandHandler) pauseCasting(request PauseCastingRequest) {
	h.logger.Info("Pausing casting")
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": `
	          window.handleCDPRequest({
							command: "pauseCasting",
						});
	      `,
	})
	if err != nil {
		h.logger.Error("Failed to send pauseCasting command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Pause casting response", zap.Any("response", resp))
}

func (h *CommandHandler) resumeCasting(request ResumeCastingRequest) {
	h.logger.Info("Resuming casting")
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": `
	          window.handleCDPRequest({
							command: "resumeCasting",
						});
	      `,
	})
	if err != nil {
		h.logger.Error("Failed to send resumeCasting command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Resume casting response", zap.Any("response", resp))
}

func (h *CommandHandler) nextArtwork(request NextArtworkRequest) {
	h.logger.Info("Next artwork")
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": `
	          window.handleCDPRequest({
							command: "nextArtwork",
						});
	      `,
	})
	if err != nil {
		h.logger.Error("Failed to send nextArtwork command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Next artwork response", zap.Any("response", resp))
}

func (h *CommandHandler) previousArtwork(request PreviousArtworkRequest) {
	h.logger.Info("Previous artwork")
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": `
	          window.handleCDPRequest({
							command: "previousArtwork",
						});
	      `,
	})
	if err != nil {
		h.logger.Error("Failed to send previousArtwork command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Previous artwork response", zap.Any("response", resp))
}

func (h *CommandHandler) updateDuration(request UpdateDurationRequest) {
	h.logger.Info("Updating duration")
	artworksJSON, err := json.Marshal(request.Artworks)
	if err != nil {
		h.logger.Error("Failed to marshal artworks", zap.Error(err))
		return
	}
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": fmt.Sprintf(`
	          window.handleCDPRequest({
							command: "updateDuration",
							params: {
								artworks: %s
							},
						});
	      `, string(artworksJSON)),
	})
	if err != nil {
		h.logger.Error("Failed to send updateDuration command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Update duration response", zap.Any("response", resp))
}

func (h *CommandHandler) castExhibition(request CastExhibitionRequest) {
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": fmt.Sprintf(`
			window.handleCDPRequest({
				command: "castExhibition",
				params: {
					exhibitionId: "%s",
					catalogId: "%s",
					catalog: "%s"
				}
			});
		`, request.ExhibitionId, request.CatalogId, request.Catalog),
	})
	if err != nil {
		h.logger.Error("Failed to send castExhibition command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Cast exhibition response", zap.Any("response", resp))
}

func (h *CommandHandler) castDaily(request CastDailyRequest) {
	resp, err := h.cdp.SendCDPRequest(CDP_METHOD_EVALUATE, map[string]interface{}{
		"expression": `
	          window.handleCDPRequest({
							command: "castDaily",
						});
	      `,
	})
	if err != nil {
		h.logger.Error("Failed to send castDaily command to Chrome", zap.Error(err))
		return
	}
	h.logger.Info("Cast daily response", zap.Any("response", resp))
}

func (h *CommandHandler) getNFTTokens(ids []string) ([]PlayArtwork, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	return []PlayArtwork{}, nil
}
