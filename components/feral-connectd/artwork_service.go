package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"

	"github.com/Khan/genqlient/graphql"
)

const (
	limitPerPage            = 50
	cloudFlareHostingDomain = "imagedelivery.net"
	ipfsGateway             = "https://ipfs.io/ipfs/"
)

type ArtworkService struct {
	httpClient    *http.Client
	graphqlClient graphql.Client
}

func NewArtworkService(httpClient *http.Client, graphqlClient graphql.Client) *ArtworkService {
	return &ArtworkService{
		httpClient:    httpClient,
		graphqlClient: graphqlClient,
	}
}

func (s *ArtworkService) GetArtworkDetail(artworkID string, includeSeries bool, includeSuccessfulSwap bool) (*Artwork, error) {
	path := fmt.Sprintf("/api/artworks/%s", artworkID)
	params := url.Values{}

	if includeSeries {
		params.Add("includeSeries", "true")
	}

	if includeSuccessfulSwap {
		params.Add("includeSuccessfulSwap", "true")
	}

	queryString := params.Encode()
	fullPath := path
	if queryString != "" {
		fullPath = fmt.Sprintf("%s?%s", path, queryString)
	}

	req, err := http.NewRequest("GET", fullPath, nil)
	if err != nil {
		return nil, fmt.Errorf("error creating request: %w", err)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("error making request: %w", err)
	}
	defer resp.Body.Close()

	var result struct {
		Result *Artwork `json:"result"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("error decoding response: %w", err)
	}

	artwork := result.Result

	return artwork, nil
}

func (s *ArtworkService) GetArtworkPreview(artwork *Artwork) string {
	var previewURL string

	if artwork.Metadata != nil {
		if artwork.Metadata.AlternativePreviewURI != nil && *artwork.Metadata.AlternativePreviewURI != "" {
			previewURL = *artwork.Metadata.AlternativePreviewURI
		} else if artwork.Metadata.PreviewCloudFlareURL != nil && *artwork.Metadata.PreviewCloudFlareURL != "" {
			previewURL = *artwork.Metadata.PreviewCloudFlareURL
		}
	}

	if previewURL == "" && artwork.PreviewDisplay != nil && artwork.PreviewDisplay.HLS != nil {
		previewURL = *artwork.PreviewDisplay.HLS
	}

	if previewURL == "" && artwork.PreviewURI != nil {
		previewURL = *artwork.PreviewURI
	}

	if previewURL == "" {
		return ""
	}

	return s.transformPreviewSrc(previewURL)
}

func (s *ArtworkService) QueryIndexerToken(id string) (*IndexerToken, error) {
	tokens, err := s.queryTokensChunk([]string{id})
	if err != nil {
		return nil, err
	}
	if len(tokens) == 0 {
		return nil, nil
	}
	return tokens[0], nil
}

func (s *ArtworkService) QueryTokens(ids []string) ([]*IndexerToken, error) {
	var allTokens []*IndexerToken

	for i := 0; i < len(ids); i += limitPerPage {
		end := i + limitPerPage
		if end > len(ids) {
			end = len(ids)
		}

		idsChunk := ids[i:end]
		tokens, err := s.queryTokensChunk(idsChunk)
		if err != nil {
			return nil, err
		}

		allTokens = append(allTokens, tokens...)
	}

	return allTokens, nil
}

func (s *ArtworkService) QueryTokenConfiguration(tokenId string) (*AssetConfiguration, error) {
	query := fmt.Sprintf(`
		{
			tokens(
				ids: ["%s"]
				burnedIncluded: true
			) {
				asset {
					attributes {
						configuration {
							scaling
							backgroundColor
							marginLeft
							marginRight
							marginTop
							marginBottom
							autoPlay
							looping
							interactable
							overridable
						}
					}
				}
			}
		}
	`, tokenId)

	var result struct {
		Tokens []struct {
			Asset *Asset `json:"asset"`
		} `json:"tokens"`
	}

	err := s.graphqlClient.MakeRequest(query, &result)
	if err != nil {
		return nil, fmt.Errorf("error querying token configuration: %w", err)
	}

	if len(result.Tokens) == 0 {
		return nil, nil
	}

	config := result.Tokens[0].Asset.Attributes.Configuration
	return config, nil
}

func (s *ArtworkService) queryTokensChunk(ids []string) ([]*IndexerToken, error) {
	query := fmt.Sprintf(`
		{
			tokens(
				ids: ["%s"]
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
	`, strings.Join(ids, `","`))

	var result struct {
		Tokens []*IndexerToken `json:"tokens"`
	}

	err := s.graphqlClient.MakeRequest(query, &result)
	if err != nil {
		return nil, fmt.Errorf("error querying tokens chunk: %w", err)
	}

	return result.Tokens, nil
}

func (s *ArtworkService) transformPreviewSrc(src string) string {
	if strings.HasPrefix(src, "https") {
		if strings.Contains(src, cloudFlareHostingDomain) {
			variantSuffix := "/thumbnail"
			if strings.Contains(src, variantSuffix) {
				return src
			}
			return src + "/thumbnailLarge"
		}
		return src
	} else if strings.HasPrefix(src, "ipfs://") {
		return strings.Replace(src, "ipfs://", ipfsGateway, 1)
	} else if strings.Contains(src, "/assets/images/empty_image.svg") {
		return src
	}

	assetURL := os.Getenv("NEXT_PUBLIC_FERAL_FILE_ASSET_URL")
	if assetURL == "" {
		return src
	}
	return fmt.Sprintf("%s/%s", assetURL, src)
}
