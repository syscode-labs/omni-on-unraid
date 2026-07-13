package omnirender

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Config struct {
	ClusterName            string
	MachineClass           string
	ProviderID             string
	ControlPlanes          int
	Workers                int
	KubernetesVersion      string
	TalosVersion           string
	Cores                  int
	MemoryMB               int
	DiskGB                 int
	StoragePool            string
	NetworkName            string
	OIDCClientID           string
	OIDCClientName         string
	OIDCCallbackURLs       string
	OIDCLogoutCallbackURLs string
	ProviderLibvirtURI     string
	SystemExtensions       []string
	NodesTailscaleAuthKey  string
}

func (c Config) withDefaults() Config {
	if c.ClusterName == "" {
		c.ClusterName = "unraid-lab"
	}
	if c.MachineClass == "" {
		c.MachineClass = "unraid-lab"
	}
	if c.ProviderID == "" {
		c.ProviderID = "libvirt"
	}
	if c.ControlPlanes == 0 {
		c.ControlPlanes = 3
	}
	if c.KubernetesVersion == "" {
		c.KubernetesVersion = "v1.34.5"
	}
	if c.TalosVersion == "" {
		c.TalosVersion = "v1.12.4"
	}
	if c.Cores == 0 {
		c.Cores = 4
	}
	if c.MemoryMB == 0 {
		c.MemoryMB = 8192
	}
	if c.DiskGB == 0 {
		c.DiskGB = 40
	}
	if c.StoragePool == "" {
		c.StoragePool = "omni-domains"
	}
	if c.NetworkName == "" {
		c.NetworkName = "default"
	}
	if len(c.SystemExtensions) == 0 {
		c.SystemExtensions = []string{"siderolabs/tailscale"}
	}
	if c.NodesTailscaleAuthKey == "" {
		c.NodesTailscaleAuthKey = os.Getenv("NODES_TAILSCALE_AUTHKEY")
	}

	return c
}

func PocketIDOIDCClientSQL(config Config) (string, error) {
	config = config.withOIDCDefaults()

	callbackURLs, err := jsonList(config.OIDCCallbackURLs)
	if err != nil {
		return "", fmt.Errorf("callback URLs: %w", err)
	}
	logoutCallbackURLs, err := jsonList(config.OIDCLogoutCallbackURLs)
	if err != nil {
		return "", fmt.Errorf("logout callback URLs: %w", err)
	}

	return fmt.Sprintf(`-- Pocket-ID OIDC client state required by Omni.
-- Omni is a confidential OIDC client and does not use PKCE for CLI public-key auth.
UPDATE oidc_clients
SET
  name = %s,
  callback_urls = %s::jsonb,
  logout_callback_urls = %s::jsonb,
  is_public = false,
  pkce_enabled = false
WHERE id = %s;

DO $$
BEGIN
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pocket-ID OIDC client %% does not exist. Create it once with the client secret, then apply this file.', %s;
  END IF;
END $$;
`, sqlQuote(config.OIDCClientName), sqlQuote(string(callbackURLs)), sqlQuote(string(logoutCallbackURLs)), sqlQuote(config.OIDCClientID), sqlQuote(config.OIDCClientID)), nil
}

func (c Config) withOIDCDefaults() Config {
	if c.OIDCClientID == "" {
		c.OIDCClientID = "omni"
	}
	if c.OIDCClientName == "" {
		c.OIDCClientName = "Omni"
	}
	if c.OIDCCallbackURLs == "" {
		c.OIDCCallbackURLs = os.Getenv("OMNI_OIDC_CALLBACK_URLS")
	}
	if c.OIDCCallbackURLs == "" {
		c.OIDCCallbackURLs = oidcURLList("/oidc/consume")
	}
	if c.OIDCLogoutCallbackURLs == "" {
		c.OIDCLogoutCallbackURLs = os.Getenv("OMNI_OIDC_LOGOUT_CALLBACK_URLS")
	}
	if c.OIDCLogoutCallbackURLs == "" {
		c.OIDCLogoutCallbackURLs = oidcURLList("/")
	}

	return c
}

func ProviderOverlay(outputDir string, config Config) error {
	if outputDir == "" {
		return fmt.Errorf("output directory is required")
	}
	if config.ProviderLibvirtURI == "" {
		config.ProviderLibvirtURI = os.Getenv("OMNI_PROVIDER_LIBVIRT_URI")
	}
	if config.ProviderLibvirtURI == "" {
		return fmt.Errorf("OMNI_PROVIDER_LIBVIRT_URI is required")
	}

	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		return err
	}

	basePath := filepath.ToSlash(filepath.Join(relToRepoRoot(outputDir), "k8s/omni-vm-libvirt-provider/base"))
	kustomization := fmt.Sprintf(`apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - %s
patches:
  - path: config-map-patch.yaml
`, basePath)
	if err := os.WriteFile(filepath.Join(outputDir, "kustomization.yaml"), []byte(kustomization), 0o644); err != nil {
		return err
	}

	configMap := fmt.Sprintf(`apiVersion: v1
kind: ConfigMap
metadata:
  name: omni-infra-provider-libvirt-config
  namespace: omni-infra-provider
data:
  config.yaml: |
    libvirt:
      uri: %s
`, config.ProviderLibvirtURI)

	return os.WriteFile(filepath.Join(outputDir, "config-map-patch.yaml"), []byte(configMap), 0o600)
}

func ProviderConfig(outputPath string, config Config) error {
	if outputPath == "" {
		return fmt.Errorf("output file path is required")
	}
	if config.ProviderLibvirtURI == "" {
		config.ProviderLibvirtURI = os.Getenv("OMNI_PROVIDER_LIBVIRT_URI")
	}
	if config.ProviderLibvirtURI == "" {
		return fmt.Errorf("OMNI_PROVIDER_LIBVIRT_URI is required")
	}

	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}

	configYAML := fmt.Sprintf(`libvirt:
  uri: %s
`, config.ProviderLibvirtURI)

	return os.WriteFile(outputPath, []byte(configYAML), 0o600)
}

func LoadDotEnv(path string) error {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if key == "" {
			continue
		}
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		os.Setenv(key, trimEnvValue(value))
	}

	return scanner.Err()
}

func oidcURLList(path string) string {
	domains := []string{}
	for _, envName := range []string{"OMNI_DOMAIN", "OMNI_PUBLIC_DOMAIN"} {
		domain := strings.TrimSpace(os.Getenv(envName))
		if domain != "" {
			domains = append(domains, domain)
		}
	}
	if len(domains) == 0 {
		domains = append(domains, "omni.example.internal")
	}

	urls := make([]string, 0, len(domains))
	for _, domain := range domains {
		urls = append(urls, "https://"+domain+path)
	}

	return strings.Join(urls, ",")
}

func relToRepoRoot(outputDir string) string {
	depth := len(strings.Split(filepath.Clean(outputDir), string(os.PathSeparator)))
	parts := make([]string, 0, depth)
	for range depth {
		parts = append(parts, "..")
	}

	return filepath.Join(parts...)
}

func trimEnvValue(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 2 {
		if (value[0] == '"' && value[len(value)-1] == '"') || (value[0] == '\'' && value[len(value)-1] == '\'') {
			return value[1 : len(value)-1]
		}
	}

	return value
}

func jsonList(csv string) ([]byte, error) {
	parts := strings.Split(csv, ",")
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		value := strings.TrimSpace(part)
		if value != "" {
			values = append(values, value)
		}
	}
	if len(values) == 0 {
		return nil, fmt.Errorf("at least one value is required")
	}

	return json.Marshal(values)
}

func sqlQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

func MachineClassDocuments(config Config) []map[string]any {
	config = config.withDefaults()

	return []map[string]any{
		{
			"metadata": map[string]any{
				"namespace": "default",
				"type":      "MachineClasses.omni.sidero.dev",
				"id":        config.MachineClass,
			},
			"spec": map[string]any{
				"autoprovision": map[string]any{
					"providerid":   config.ProviderID,
					"providerdata": providerData(config),
				},
			},
		},
	}
}

func ClusterDocuments(config Config) []map[string]any {
	config = config.withDefaults()

	clusterPatches := []map[string]any{
		{"file": "omni/patches/cni-none.yaml"},
		{"file": "omni/patches/disable-kube-proxy.yaml"},
		{"file": "omni/patches/inline-manifests.yaml"},
	}
	if config.NodesTailscaleAuthKey != "" {
		clusterPatches = append(clusterPatches, map[string]any{
			"name": "tailscale-auth",
			"inline": map[string]any{
				"apiVersion":  "v1alpha1",
				"kind":        "ExtensionServiceConfig",
				"name":        "tailscale",
				"environment": []string{"TS_AUTHKEY=" + config.NodesTailscaleAuthKey},
			},
		})
	}

	docs := []map[string]any{
		{
			"kind": "Cluster",
			"name": config.ClusterName,
			"kubernetes": map[string]any{
				"version": config.KubernetesVersion,
			},
			"talos": map[string]any{
				"version": config.TalosVersion,
			},
			"systemExtensions": config.SystemExtensions,
			"features": map[string]any{
				"diskEncryption": false,
			},
			"patches": clusterPatches,
		},
		{
			"kind": "ControlPlane",
			"machineClass": map[string]any{
				"name": config.MachineClass,
				"size": config.ControlPlanes,
			},
			"patches": []map[string]any{
				{
					"name": "cp-schedulable",
					"inline": map[string]any{
						"cluster": map[string]any{
							"allowSchedulingOnControlPlanes": true,
						},
					},
				},
			},
		},
	}

	if config.Workers > 0 {
		docs = append(docs, map[string]any{
			"kind": "Workers",
			"name": "worker",
			"machineClass": map[string]any{
				"name": config.MachineClass,
				"size": config.Workers,
			},
		})
	}

	return docs
}

func WriteYAML(writer io.Writer, docs []map[string]any) error {
	for _, doc := range docs {
		if _, err := fmt.Fprintln(writer, "---"); err != nil {
			return err
		}
		if err := writeMap(writer, doc, 0); err != nil {
			return err
		}
	}

	return nil
}

func providerData(config Config) string {
	return fmt.Sprintf(`cores: %d
memory: %d
disk_size: %d
storage_pool: "%s"
network_interfaces:
  - driver: "virtio"
    network_name: "%s"
`, config.Cores, config.MemoryMB, config.DiskGB, config.StoragePool, config.NetworkName)
}

func writeMap(writer io.Writer, value map[string]any, indent int) error {
	keys := orderedKeys(value)
	for _, key := range keys {
		if err := writeValue(writer, key, value[key], indent); err != nil {
			return err
		}
	}

	return nil
}

func writeValue(writer io.Writer, key string, value any, indent int) error {
	prefix := strings.Repeat(" ", indent)
	switch typed := value.(type) {
	case map[string]any:
		if _, err := fmt.Fprintf(writer, "%s%s:\n", prefix, key); err != nil {
			return err
		}
		return writeMap(writer, typed, indent+2)
	case []map[string]any:
		if _, err := fmt.Fprintf(writer, "%s%s:\n", prefix, key); err != nil {
			return err
		}
		for _, item := range typed {
			if _, err := fmt.Fprintf(writer, "%s  -", prefix); err != nil {
				return err
			}
			if err := writeInlineOrNestedMap(writer, item, indent+4); err != nil {
				return err
			}
		}
		return nil
	case []string:
		if _, err := fmt.Fprintf(writer, "%s%s:\n", prefix, key); err != nil {
			return err
		}
		for _, item := range typed {
			if _, err := fmt.Fprintf(writer, "%s  - %s\n", prefix, item); err != nil {
				return err
			}
		}
		return nil
	case string:
		if strings.Contains(typed, "\n") {
			if _, err := fmt.Fprintf(writer, "%s%s: |\n", prefix, key); err != nil {
				return err
			}
			for _, line := range strings.Split(strings.TrimSuffix(typed, "\n"), "\n") {
				if _, err := fmt.Fprintf(writer, "%s  %s\n", prefix, line); err != nil {
					return err
				}
			}
			return nil
		}
		_, err := fmt.Fprintf(writer, "%s%s: %s\n", prefix, key, typed)
		return err
	default:
		_, err := fmt.Fprintf(writer, "%s%s: %v\n", prefix, key, typed)
		return err
	}
}

func writeInlineOrNestedMap(writer io.Writer, value map[string]any, indent int) error {
	keys := orderedKeys(value)
	if len(keys) == 0 {
		_, err := fmt.Fprintln(writer)
		return err
	}

	first := keys[0]
	if _, err := fmt.Fprintf(writer, " %s: %v\n", first, value[first]); err != nil {
		return err
	}
	for _, key := range keys[1:] {
		if err := writeValue(writer, key, value[key], indent); err != nil {
			return err
		}
	}

	return nil
}

func orderedKeys(value map[string]any) []string {
	preferred := []string{
		"kind",
		"name",
		"metadata",
		"namespace",
		"type",
		"id",
		"spec",
		"autoprovision",
		"providerid",
		"providerdata",
		"file",
		"apiVersion",
		"kubernetes",
		"talos",
		"systemExtensions",
		"features",
		"machineClass",
		"size",
		"patches",
		"inline",
		"environment",
		"cluster",
		"allowSchedulingOnControlPlanes",
	}

	seen := map[string]bool{}
	keys := make([]string, 0, len(value))
	for _, key := range preferred {
		if _, ok := value[key]; ok {
			keys = append(keys, key)
			seen[key] = true
		}
	}

	rest := make([]string, 0, len(value))
	for key := range value {
		if !seen[key] {
			rest = append(rest, key)
		}
	}
	sort.Strings(rest)

	return append(keys, rest...)
}
