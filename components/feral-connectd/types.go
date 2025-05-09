package main

// Artwork

type Swap struct {
	Id              string `json:"id"`
	BlockchainType  string `json:"blockchainType"`
	ContractAddress string `json:"contractAddress"`
	Token           string `json:"token"`
}

type ArtworkMetadata struct {
	PreviewCloudFlareURL  *string `json:"previewCloudFlareURL"`
	AlternativePreviewURI *string `json:"alternativePreviewURI"`
}

type Artwork struct {
	Id             string  `json:"id"`
	SeriesID       *string `json:"seriesID"`
	PreviewURI     *string `json:"previewURI"`
	PreviewDisplay *struct {
		HLS  *string `json:"HLS"`
		DASH *string `json:"DASH"`
	} `json:"previewDisplay"`
	PreviewMIMEType *string          `json:"previewMIMEType"`
	Metadata        *ArtworkMetadata `json:"metadata"`
	Swap            *Swap            `json:"swap"`
	SuccessfulSwap  *Swap            `json:"successfulSwap"`
}

// Indexer Token
type IndexerToken struct {
	Id              string `json:"id"`
	ContractAddress string `json:"contractAddress"`
	IndexID         string `json:"indexID"`
	Source          string `json:"source"`
	Asset           *Asset `json:"asset"`
}

type Asset struct {
	StaticPreviewURLLandscape *string          `json:"staticPreviewURLLandscape"`
	StaticPreviewURLPortrait  *string          `json:"staticPreviewURLPortrait"`
	Attributes                *AssetAttributes `json:"attributes"`
	Metadata                  *AssetMetadata   `json:"metadata"`
}

type AssetMetadata struct {
	Project *ProjectMetadata `json:"project"`
}

type AssetAttributes struct {
	Configuration *AssetConfiguration `json:"configuration"`
}

type AssetConfiguration struct {
	Scaling         *string `json:"scaling"`
	BackgroundColor *string `json:"backgroundColor"`
	MarginLeft      *int    `json:"marginLeft"`
	MarginRight     *int    `json:"marginRight"`
	MarginTop       *int    `json:"marginTop"`
	MarginBottom    *int    `json:"marginBottom"`
	AutoPlay        *bool   `json:"autoPlay"`
	Looping         *bool   `json:"looping"`
	Interactable    *bool   `json:"interactable"`
	Overridable     *bool   `json:"overridable"`
}

type ProjectMetadata struct {
	Latest *IndexerArtwork `json:"latest"`
}

type IndexerArtwork struct {
	Medium     *string `json:"medium"`
	PreviewURL *string `json:"previewURL"`
}

// Websocket request, response

type ExhibitionCatalog string

const (
	Home           ExhibitionCatalog = "home"
	CuratorNote    ExhibitionCatalog = "curatorNote"
	Resource       ExhibitionCatalog = "resource"
	ResourceDetail ExhibitionCatalog = "resourceDetail"
	ArtworkCatalog ExhibitionCatalog = "artwork"
)

type PlayArtwork struct {
	Id       string `json:"id"`
	Duration int    `json:"duration"`
	Token    struct {
		Id string `json:"id"`
	} `json:"token"`
}

type Request struct {
}

type CheckStatusRequest struct {
	Request
}

type CastListArtworkRequest struct {
	Request
	StartTime int           `json:"startTime"`
	Artworks  []PlayArtwork `json:"artworks"`
}

type PauseCastingRequest struct {
	Request
}

type ResumeCastingRequest struct {
	Request
}

type NextArtworkRequest struct {
	Request
}

type PreviousArtworkRequest struct {
	Request
}

type UpdateDurationRequest struct {
	Request
	Artworks []PlayArtwork `json:"artworks"`
}

type CastExhibitionRequest struct {
	Request
	ExhibitionId string            `json:"exhibitionId"`
	CatalogId    string            `json:"catalogId"`
	Catalog      ExhibitionCatalog `json:"catalog"`
}

type CastDailyRequest struct {
	Request
}

type Response struct {
	Ok bool `json:"ok"`
}

type DeviceInfo struct {
	DeviceName string `json:"device_name"`
	DeviceId   string `json:"device_id"`
}

type CheckStatusResponse struct {
	Ok              bool        `json:"ok"`
	ConnectedDevice *DeviceInfo `json:"connectedDevice"`

	ExhibitionId *string            `json:"exhibitionId"`
	Catalog      *ExhibitionCatalog `json:"catalog"`
	CatalogId    *string            `json:"catalogId"`

	Artworks  *[]PlayArtwork `json:"artworks"`
	StartTime *int           `json:"startTime"`
	Index     *int           `json:"index"`
	IsPaused  *bool          `json:"isPaused"`

	DisplayKey *string `json:"displayKey"`
}
