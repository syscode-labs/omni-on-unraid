package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/syscode-labs/omni-on-unraid/internal/githubapp"
	"github.com/syscode-labs/omni-on-unraid/internal/omnirender"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	if err := omnirender.LoadDotEnv(".env"); err != nil {
		return err
	}

	var req githubapp.TokenRequest
	var permissionsJSON string
	var repositoriesCSV string
	var output string
	var outputFile string
	var envName string
	var registry string
	var dockerUsername string

	flags := flag.NewFlagSet("github-app-token", flag.ContinueOnError)
	flags.StringVar(&req.AppID, "app-id", env("GITHUB_APP_ID", env("GITHUB_APP_CLIENT_ID", "")), "GitHub App ID or client ID")
	flags.StringVar(&req.InstallationID, "installation-id", env("GITHUB_APP_INSTALLATION_ID", ""), "GitHub App installation ID")
	flags.StringVar(&req.PrivateKeyPath, "private-key-file", env("GITHUB_APP_PRIVATE_KEY_FILE", ""), "GitHub App private key PEM file")
	flags.StringVar(&req.APIURL, "api-url", env("GITHUB_API_URL", githubapp.DefaultAPIURL), "GitHub API URL")
	flags.StringVar(&repositoriesCSV, "repositories", env("GITHUB_APP_TOKEN_REPOSITORIES", ""), "comma-separated repository names to scope token")
	flags.StringVar(&permissionsJSON, "permissions", env("GITHUB_APP_TOKEN_PERMISSIONS", `{"packages":"write","contents":"read","metadata":"read"}`), "installation token permissions JSON")
	flags.StringVar(&output, "output", "token", "output mode: token, env, docker-config")
	flags.StringVar(&outputFile, "output-file", "", "output file for env or docker-config mode")
	flags.StringVar(&envName, "env-name", "GITHUB_TOKEN", "variable name for env mode")
	flags.StringVar(&registry, "registry", env("GITHUB_APP_DOCKER_REGISTRY", "ghcr.io"), "registry for docker-config mode")
	flags.StringVar(&dockerUsername, "docker-username", env("GITHUB_APP_DOCKER_USERNAME", "x-access-token"), "username for docker-config mode")
	if err := flags.Parse(os.Args[1:]); err != nil {
		return err
	}

	req.Repositories = csv(repositoriesCSV)
	if permissionsJSON != "" {
		if err := json.Unmarshal([]byte(permissionsJSON), &req.Permissions); err != nil {
			return fmt.Errorf("parse permissions JSON: %w", err)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	token, err := githubapp.InstallationToken(ctx, nil, req)
	if err != nil {
		return err
	}

	switch output {
	case "token":
		fmt.Println(token.Token)
	case "env":
		if outputFile == "" {
			return fmt.Errorf("--output-file is required for env output")
		}
		return os.WriteFile(outputFile, []byte(fmt.Sprintf("%s=%s\n", envName, token.Token)), 0o600)
	case "docker-config":
		if outputFile == "" {
			return fmt.Errorf("--output-file is required for docker-config output")
		}
		return githubapp.WriteDockerConfig(outputFile, registry, dockerUsername, token.Token)
	default:
		return fmt.Errorf("unknown output mode: %s", output)
	}
	return nil
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func csv(value string) []string {
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			values = append(values, part)
		}
	}
	return values
}
