package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"net/url"
	"os"
	"time"

	"github.com/syscode-labs/omni-on-unraid/internal/omnihealth"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error
	switch os.Args[1] {
	case "compose-env":
		err = runComposeEnv(os.Args[2:])
	case "tls":
		err = runTLS(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "omni-health: %v\n", err)
		os.Exit(1)
	}
}

func runComposeEnv(args []string) error {
	fs := flag.NewFlagSet("compose-env", flag.ExitOnError)
	path := fs.String("path", "generated/compose.env", "generated compose.env path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	return omnihealth.ValidateComposeEnv(*path)
}

func runTLS(args []string) error {
	fs := flag.NewFlagSet("tls", flag.ExitOnError)
	domain := fs.String("domain", "", "Omni DNS name")
	webAddr := fs.String("web-addr", "", "Omni web/API address host:port")
	machineAddr := fs.String("machine-api-addr", "", "Omni machine API address host:port")
	machineURL := fs.String("machine-api-url", "", "Omni machine API advertised URL")
	timeout := fs.Duration("timeout", 10*time.Second, "per-check timeout")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *domain == "" {
		return fmt.Errorf("--domain is required")
	}
	if *webAddr == "" {
		*webAddr = *domain + ":443"
	}
	if *machineAddr == "" && *machineURL != "" {
		resolved, err := machineAddressFromURL(*machineURL)
		if err != nil {
			return err
		}
		*machineAddr = resolved
	}
	machineServerName := *domain
	if *machineURL != "" {
		resolved, err := machineServerNameFromURL(*machineURL)
		if err != nil {
			return err
		}
		machineServerName = resolved
	}
	if *machineAddr == "" {
		*machineAddr = *domain + ":8090"
	}

	ctx := context.Background()
	checks := []omnihealth.TLSCheck{
		{
			Name:       "web-api",
			Address:    *webAddr,
			ServerName: *domain,
			SendSNI:    true,
			Timeout:    *timeout,
		},
		{
			Name:       "machine-api-no-sni",
			Address:    *machineAddr,
			ServerName: machineServerName,
			SendSNI:    false,
			Timeout:    *timeout,
		},
	}
	for _, check := range checks {
		if err := check.Run(ctx); err != nil {
			return err
		}
		fmt.Printf("ok: %s %s\n", check.Name, check.Address)
	}
	return nil
}

func machineServerNameFromURL(rawURL string) (string, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return "", fmt.Errorf("parse machine API URL %q: %w", rawURL, err)
	}
	if parsed.Hostname() == "" {
		return "", fmt.Errorf("machine API URL %q missing host", rawURL)
	}
	return parsed.Hostname(), nil
}

func machineAddressFromURL(rawURL string) (string, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return "", fmt.Errorf("parse machine API URL %q: %w", rawURL, err)
	}
	if parsed.Host == "" {
		return "", fmt.Errorf("machine API URL %q missing host", rawURL)
	}
	if parsed.Port() != "" {
		return parsed.Host, nil
	}
	return net.JoinHostPort(parsed.Hostname(), "8090"), nil
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: omni-health <compose-env|tls> [flags]")
}
