package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/hasura/go-graphql-client"
	"go.uber.org/zap"
)

const (
	PAGE_SIZE       = 50
	CF_IMAGE_DOMAIN = "imagedelivery.net"
	IPFS_GATEWAY    = "https://ipfs.io/ipfs/"
	IPFS_SCHEME     = "ipfs://"
)

type FeralFileConfig struct {
	Endpoint string `json:"endpoint"`
	AssetURL string `json:"assetURL"`
}

type FeralFileClient struct {
	endpoint   string
	httpClient *http.Client
	logger     *zap.Logger
}

type FeralFileError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e FeralFileError) Error() string {
	return fmt.Sprintf("FeralFileError: %d %s", e.Code, e.Message)
}

func NewFeralFileClient(endpoint string, logger *zap.Logger) *FeralFileClient {
	return &FeralFileClient{
		endpoint: endpoint,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
		logger: logger,
	}
}

func (c *FeralFileClient) request(
	ctx context.Context,
	method string,
	path string,
	body interface{},
	response interface{},
) error {
	jsonBody, err := json.Marshal(body)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(
		ctx,
		method,
		c.endpoint+path,
		bytes.NewBuffer(jsonBody))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	res, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode >= 300 || res.StatusCode < 200 {
		var error FeralFileError
		if err := json.NewDecoder(res.Body).Decode(&error); err != nil {
			c.logger.Error("failed to decode error", zap.Error(err))
			return fmt.Errorf("unknown error: status code: %d", res.StatusCode)
		}
		return error
	}

	return json.NewDecoder(res.Body).Decode(response)
}

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
	Index          *int    `json:"index"`
	Name           *string `json:"name"`
	PreviewURI     *string `json:"previewURI"`
	PreviewDisplay *struct {
		HLS  *string `json:"HLS"`
		DASH *string `json:"DASH"`
	} `json:"previewDisplay"`
	PreviewMIMEType *string          `json:"previewMIMEType"`
	ThumbnailURI    *string          `json:"thumbnailURI"`
	MintedAt        *string          `json:"mintedAt"`
	Metadata        *ArtworkMetadata `json:"metadata"`
	ArtistAlias     *string          `json:"artistAlias"`
	Swap            *Swap            `json:"swap"`
	SuccessfulSwap  *Swap            `json:"successfulSwap"`
}

type Daily struct {
	ID              string `json:"id"`
	Blockchain      string `json:"blockchain"`
	ContractAddress string `json:"contractAddress"`
	TokenID         string `json:"tokenID"`
}

func (a *Artwork) GetPreviewURL() string {
	var previewURL string
	if a.Metadata != nil {
		if !EmptyOrNilString(a.Metadata.AlternativePreviewURI) {
			previewURL = *a.Metadata.AlternativePreviewURI
		} else if !EmptyOrNilString(a.Metadata.PreviewCloudFlareURL) {
			previewURL = *a.Metadata.PreviewCloudFlareURL
		}
	}

	if previewURL == "" && a.PreviewDisplay != nil && !EmptyOrNilString(a.PreviewDisplay.HLS) {
		previewURL = *a.PreviewDisplay.HLS
	}

	if previewURL == "" && !EmptyOrNilString(a.PreviewURI) {
		previewURL = *a.PreviewURI
	}

	if previewURL == "" {
		return ""
	}

	return transformPreviewURL(previewURL)
}

func transformPreviewURL(url string) string {
	if strings.HasPrefix(url, "https") {
		if strings.Contains(url, CF_IMAGE_DOMAIN) {
			if strings.Contains(url, "/thumbnail") {
				return url
			}
			return url + "/thumbnailLarge"
		}
		return url
	}

	if strings.HasPrefix(url, IPFS_SCHEME) {
		return strings.Replace(url, IPFS_SCHEME, IPFS_GATEWAY, 1)
	}

	if strings.Contains(url, "/assets/images/empty_image.svg") {
		return url
	}

	return fmt.Sprintf("%s/%s", config.FeralFile.AssetURL, url)
}

func (c *FeralFileClient) GetArtwork(ctx context.Context, id string) (*Artwork, error) {
	var artwork Artwork
	if err := c.request(
		ctx,
		http.MethodGet,
		fmt.Sprintf("/api/artworks/%s?includeSuccessfulSwap=true",
			id),
		nil,
		&artwork); err != nil {
		return nil, err
	}
	return &artwork, nil
}

func (c *FeralFileClient) GetDaily(ctx context.Context, date time.Time) ([]Daily, error) {
	var resp struct {
		Dailies []Daily `json:"result"`
	}
	if err := c.request(
		ctx,
		http.MethodGet,
		fmt.Sprintf("/api/dailies/date/%s", date.Format("2006-01-02")),
		nil,
		&resp,
	); err != nil {
		return nil, err
	}
	return resp.Dailies, nil
}

type IndexerConfig struct {
	Endpoint string `json:"endpoint"`
}

type IndexerClient struct {
	endpoint string
	graphql  *graphql.Client
	logger   *zap.Logger
}

func NewIndexerClient(endpoint string, logger *zap.Logger) *IndexerClient {
	httpClient := &http.Client{
		Timeout: 15 * time.Second,
	}
	return &IndexerClient{
		endpoint: endpoint,
		graphql:  graphql.NewClient(endpoint, httpClient),
		logger:   logger,
	}
}

func (c *IndexerClient) request(
	ctx context.Context,
	query string,
	variables map[string]interface{},
	response interface{}) error {
	if err := c.graphql.Exec(ctx, query, response, variables); err != nil {
		c.logger.Error("failed to execute query", zap.Error(err))
		return err
	}
	return nil
}

type Token struct {
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
	Latest *struct {
		Medium     string `json:"medium"`
		MIMEType   string `json:"mimeType"`
		PreviewURL string `json:"previewURL"`
	} `json:"latest"`
}

func (c *IndexerClient) GetTokens(ctx context.Context, indexIDs []string) ([]Token, error) {
	var tokens []Token
	for i := 0; i < len(indexIDs); i += PAGE_SIZE {
		batch := indexIDs[i:min(i+PAGE_SIZE, len(indexIDs))]
		batchTokens, err := c.getTokens(ctx, batch)
		if err != nil {
			return nil, err
		}
		tokens = append(tokens, batchTokens...)
	}
	return tokens, nil
}

func (c *IndexerClient) getTokens(ctx context.Context, indexIDs []string) ([]Token, error) {
	query := `
		{
			tokens(
				ids: $indexIDs
				burnedIncluded: true
			) {
				id
				contractAddress
				indexID
				source
				asset {
					thumbnailID
					staticPreviewURLLandscape
					staticPreviewURLPortrait
					metadata {
						project {
							latest {
								medium
								previewURL
							}
						}
					}
				}
			}
		}
	`

	variables := map[string]interface{}{
		"indexIDs": indexIDs,
	}

	var response struct {
		Tokens []Token `json:"tokens"`
	}

	if err := c.request(ctx, query, variables, &response); err != nil {
		return nil, err
	}

	return response.Tokens, nil
}

type DataHandler struct {
	FF *FeralFileClient
	IC *IndexerClient
}

func NewDataHandler(ffEndpoint string, icEndpoint string, logger *zap.Logger) *DataHandler {
	return &DataHandler{
		FF: NewFeralFileClient(ffEndpoint, logger),
		IC: NewIndexerClient(icEndpoint, logger),
	}
}
