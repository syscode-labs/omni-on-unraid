package githubapp

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestJWTUsesGitHubAppClaims(t *testing.T) {
	keyPath := writeTestKey(t)

	token, err := JWT(TokenRequest{
		AppID:          "12345",
		InstallationID: "67890",
		PrivateKeyPath: keyPath,
		Now:            time.Unix(1_700_000_000, 0),
	})
	if err != nil {
		t.Fatalf("JWT returned error: %v", err)
	}

	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("JWT parts = %d, want 3", len(parts))
	}

	var header map[string]string
	if err := decodeSegment(parts[0], &header); err != nil {
		t.Fatalf("decode header: %v", err)
	}
	if header["alg"] != "RS256" {
		t.Fatalf("alg = %q, want RS256", header["alg"])
	}

	var claims map[string]any
	if err := decodeSegment(parts[1], &claims); err != nil {
		t.Fatalf("decode claims: %v", err)
	}
	if claims["iss"] != "12345" {
		t.Fatalf("iss = %v, want 12345", claims["iss"])
	}
	if got := int64(claims["iat"].(float64)); got != 1_699_999_940 {
		t.Fatalf("iat = %d, want 1699999940", got)
	}
	if got := int64(claims["exp"].(float64)); got != 1_700_000_600 {
		t.Fatalf("exp = %d, want 1700000600", got)
	}
}

func TestWriteDockerConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")

	if err := WriteDockerConfig(path, "ghcr.io", "x-access-token", "ghs_example"); err != nil {
		t.Fatalf("WriteDockerConfig returned error: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	var config struct {
		Auths map[string]struct {
			Auth string `json:"auth"`
		} `json:"auths"`
	}
	if err := json.Unmarshal(data, &config); err != nil {
		t.Fatalf("Unmarshal docker config: %v", err)
	}
	auth := config.Auths["ghcr.io"].Auth
	decoded, err := base64.StdEncoding.DecodeString(auth)
	if err != nil {
		t.Fatalf("DecodeString auth: %v", err)
	}
	if string(decoded) != "x-access-token:ghs_example" {
		t.Fatalf("auth = %q, want x-access-token:ghs_example", decoded)
	}
}

func writeTestKey(t *testing.T) string {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("GenerateKey: %v", err)
	}
	block := &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}
	path := filepath.Join(t.TempDir(), "app.pem")
	if err := os.WriteFile(path, pem.EncodeToMemory(block), 0o600); err != nil {
		t.Fatalf("WriteFile key: %v", err)
	}
	return path
}

func decodeSegment(segment string, target any) error {
	data, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, target)
}
