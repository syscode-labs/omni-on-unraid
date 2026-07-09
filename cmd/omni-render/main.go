package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/syscode-labs/omni-on-unraid/internal/omnirender"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	if len(os.Args) < 2 {
		return fmt.Errorf("usage: omni-render <machineclass|cluster|pocketid-oidc-sql|provider-overlay|provider-config> [flags]")
	}
	if err := omnirender.LoadDotEnv(".env"); err != nil {
		return err
	}

	command := os.Args[1]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	config := omnirender.Config{}
	output := flags.String("output", "", "output file path")
	outputDir := flags.String("output-dir", "", "output directory path")
	flags.StringVar(&config.ClusterName, "cluster-name", "", "cluster name")
	flags.StringVar(&config.MachineClass, "machine-class", "", "machine class name")
	flags.StringVar(&config.ProviderID, "provider-id", "", "provider ID")
	flags.IntVar(&config.ControlPlanes, "control-planes", 0, "control-plane count")
	flags.IntVar(&config.Workers, "workers", 0, "worker count")
	flags.StringVar(&config.KubernetesVersion, "kubernetes-version", "", "Kubernetes version")
	flags.StringVar(&config.TalosVersion, "talos-version", "", "Talos version")
	flags.IntVar(&config.Cores, "cores", 0, "machine cores")
	flags.IntVar(&config.MemoryMB, "memory-mb", 0, "machine memory in MB")
	flags.IntVar(&config.DiskGB, "disk-gb", 0, "machine disk in GB")
	flags.StringVar(&config.StoragePool, "storage-pool", "", "libvirt storage pool")
	flags.StringVar(&config.NetworkName, "network-name", "", "libvirt network name")
	flags.StringVar(&config.OIDCClientID, "oidc-client-id", "", "Pocket-ID OIDC client ID")
	flags.StringVar(&config.OIDCClientName, "oidc-client-name", "", "Pocket-ID OIDC client display name")
	flags.StringVar(&config.OIDCCallbackURLs, "oidc-callback-urls", "", "comma-separated OIDC callback URLs")
	flags.StringVar(&config.OIDCLogoutCallbackURLs, "oidc-logout-callback-urls", "", "comma-separated OIDC logout callback URLs")
	flags.StringVar(&config.ProviderLibvirtURI, "provider-libvirt-uri", "", "libvirt URI used by the Omni libvirt provider")

	if err := flags.Parse(os.Args[2:]); err != nil {
		return err
	}
	if command == "provider-overlay" {
		return omnirender.ProviderOverlay(*outputDir, config)
	}
	if *output == "" {
		return fmt.Errorf("--output is required")
	}

	var docs []map[string]any
	switch command {
	case "machineclass":
		docs = omnirender.MachineClassDocuments(config)
	case "cluster":
		docs = omnirender.ClusterDocuments(config)
	case "pocketid-oidc-sql":
		sql, err := omnirender.PocketIDOIDCClientSQL(config)
		if err != nil {
			return err
		}

		return os.WriteFile(*output, []byte(sql), 0o600)
	case "provider-config":
		return omnirender.ProviderConfig(*output, config)
	default:
		return fmt.Errorf("unknown command: %s", command)
	}

	file, err := os.Create(*output)
	if err != nil {
		return err
	}
	defer file.Close()

	return omnirender.WriteYAML(file, docs)
}
