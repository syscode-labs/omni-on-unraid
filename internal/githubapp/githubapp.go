package githubapp

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const DefaultAPIURL = "https://api.github.com"

type TokenRequest struct {
	AppID          string
	InstallationID string
	PrivateKeyPath string
	APIURL         string
	Repositories   []string
	Permissions    map[string]string
	Now            time.Time
}

type TokenResponse struct {
	Token       string            `json:"token"`
	ExpiresAt   time.Time         `json:"expires_at"`
	Permissions map[string]string `json:"permissions"`
}

func InstallationToken(ctx context.Context, client *http.Client, req TokenRequest) (TokenResponse, error) {
	if client == nil {
		client = http.DefaultClient
	}
	jwt, err := JWT(req)
	if err != nil {
		return TokenResponse{}, err
	}

	body := map[string]any{}
	if len(req.Repositories) > 0 {
		body["repositories"] = req.Repositories
	}
	if len(req.Permissions) > 0 {
		body["permissions"] = req.Permissions
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return TokenResponse{}, err
	}

	apiURL := strings.TrimRight(valueOrDefault(req.APIURL, DefaultAPIURL), "/")
	url := fmt.Sprintf("%s/app/installations/%s/access_tokens", apiURL, req.InstallationID)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return TokenResponse{}, err
	}
	httpReq.Header.Set("Accept", "application/vnd.github+json")
	httpReq.Header.Set("Authorization", "Bearer "+jwt)
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-GitHub-Api-Version", "2026-03-10")

	resp, err := client.Do(httpReq)
	if err != nil {
		return TokenResponse{}, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return TokenResponse{}, err
	}
	if resp.StatusCode != http.StatusCreated {
		return TokenResponse{}, fmt.Errorf("create installation token: %s: %s", resp.Status, strings.TrimSpace(string(respBody)))
	}

	var token TokenResponse
	if err := json.Unmarshal(respBody, &token); err != nil {
		return TokenResponse{}, err
	}
	if token.Token == "" {
		return TokenResponse{}, errors.New("create installation token: empty token in response")
	}
	return token, nil
}

func JWT(req TokenRequest) (string, error) {
	if req.AppID == "" {
		return "", errors.New("GITHUB_APP_ID is required")
	}
	if req.InstallationID == "" {
		return "", errors.New("GITHUB_APP_INSTALLATION_ID is required")
	}
	if req.PrivateKeyPath == "" {
		return "", errors.New("GITHUB_APP_PRIVATE_KEY_FILE is required")
	}

	keyPEM, err := os.ReadFile(req.PrivateKeyPath)
	if err != nil {
		return "", err
	}
	key, err := parsePrivateKey(keyPEM)
	if err != nil {
		return "", err
	}

	now := req.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	header := map[string]string{"alg": "RS256", "typ": "JWT"}
	payload := map[string]any{
		"iat": now.Add(-60 * time.Second).Unix(),
		"exp": now.Add(10 * time.Minute).Unix(),
		"iss": req.AppID,
	}

	headerJSON, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	unsigned := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(payloadJSON)
	digest := sha256.Sum256([]byte(unsigned))
	signature, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		return "", err
	}

	return unsigned + "." + base64.RawURLEncoding.EncodeToString(signature), nil
}

func WriteDockerConfig(path, registry, username, token string) error {
	if path == "" {
		return errors.New("docker config output path is required")
	}
	if registry == "" {
		return errors.New("docker registry is required")
	}
	if username == "" {
		return errors.New("docker username is required")
	}
	if token == "" {
		return errors.New("token is required")
	}

	config := map[string]any{
		"auths": map[string]any{
			registry: map[string]string{
				"auth": base64.StdEncoding.EncodeToString([]byte(username + ":" + token)),
			},
		},
	}
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')

	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

func parsePrivateKey(keyPEM []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(keyPEM)
	if block == nil {
		return nil, errors.New("private key PEM block not found")
	}
	if key, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return key, nil
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	rsaKey, ok := key.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("private key is not RSA")
	}
	return rsaKey, nil
}

func valueOrDefault(value, fallback string) string {
	if value != "" {
		return value
	}
	return fallback
}
