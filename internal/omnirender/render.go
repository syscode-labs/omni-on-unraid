package omnirender

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

type Config struct {
	ClusterName                   string
	MachineClass                  string
	ProviderID                    string
	ControlPlanes                 int
	Workers                       int
	KubernetesVersion             string
	TalosVersion                  string
	Cores                         int
	MemoryMB                      int
	DiskGB                        int
	StoragePool                   string
	NetworkName                   string
	OIDCClientID                  string
	OIDCClientName                string
	OIDCCallbackURLs              string
	OIDCLogoutCallbackURLs        string
	ProviderLibvirtURI            string
	InstallImage                  string
	ImageFactoryExternalURL       string
	ImageFactoryRegistry          string
	ImageFactoryNamespace         string
	ImageFactoryCoreRegistry      string
	ImageFactoryExtensionManifest string
	ImageFactoryInsecure          bool
	ImageFactorySigningKey        string
	ImageFactoryCosignKey         string
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
	if c.Cores == 0 {
		// 4 cores x 3 CPs (+ omni-vm, Home Assistant) meant 16 vCPU committed
		// against the Unraid host's 12 physical cores, no cputune fairness —
		// one starved VM's kill-restart storm starved its siblings and took
		// down the whole cluster's control plane. Trimmed 2026-08-10.
		c.Cores = 3
	}
	if c.MemoryMB == 0 {
		// 8192 put too much memory pressure on the Unraid host with 3 CPs
		// running concurrently; trimmed 2026-07-28. Running nodes actually
		// ended up at 4096 (this default was bumped to 6144 without ever
		// resizing them) — realigned to match reality, 2026-08-10.
		c.MemoryMB = 4096
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
	if c.InstallImage == "" {
		// Runtime installer. Tag tracks the Talos version so the two never drift.
		// -libvirt variant: same custom exts (incl. talos-ext-firecracker) plus
		// qemu-guest-agent, which this repo's libvirt-only provider needs.
		// MachineClass.installImage is NOT PERSISTED by Omni (round-trips empty;
		// reconfirmed live on Omni 1.10.0, unraid-cp v14, 2026-08-23 — the field
		// does not exist in MachineClassSpec upstream at all). The value still
		// reaches fresh nodes via the custom-install-image cluster patch in
		// ClusterDocuments. See syscode-labs/omni-on-unraid#7.
		c.InstallImage = "ghcr.io/syscode-labs/talos-images/installer:" + c.TalosVersion + "-libvirt"
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

func ImageFactoryConfig(outputPath string, config Config) error {
	if outputPath == "" {
		return fmt.Errorf("output file path is required")
	}
	if config.ImageFactoryExternalURL == "" {
		config.ImageFactoryExternalURL = os.Getenv("OMNI_IMAGE_FACTORY_ADDRESS")
	}
	if config.ImageFactoryRegistry == "" {
		config.ImageFactoryRegistry = os.Getenv("OMNI_IMAGE_FACTORY_REGISTRY")
	}
	if config.ImageFactoryNamespace == "" {
		config.ImageFactoryNamespace = os.Getenv("OMNI_IMAGE_FACTORY_NAMESPACE")
	}
	if config.ImageFactoryCoreRegistry == "" {
		config.ImageFactoryCoreRegistry = os.Getenv("OMNI_IMAGE_FACTORY_CORE_REGISTRY")
	}
	if config.ImageFactoryExtensionManifest == "" {
		config.ImageFactoryExtensionManifest = os.Getenv("OMNI_IMAGE_FACTORY_EXTENSION_MANIFEST")
	}
	if config.ImageFactorySigningKey == "" {
		config.ImageFactorySigningKey = os.Getenv("OMNI_IMAGE_FACTORY_SIGNING_KEY_PATH")
	}
	if config.ImageFactoryCosignKey == "" {
		config.ImageFactoryCosignKey = os.Getenv("OMNI_IMAGE_FACTORY_COSIGN_PUBLIC_KEY_PATH")
	}
	if envInsecure := os.Getenv("OMNI_IMAGE_FACTORY_INSECURE"); envInsecure != "" {
		config.ImageFactoryInsecure = envInsecure == "true"
	}
	if config.ImageFactoryExternalURL == "" {
		return fmt.Errorf("OMNI_IMAGE_FACTORY_ADDRESS is required")
	}
	if config.ImageFactoryRegistry == "" {
		return fmt.Errorf("OMNI_IMAGE_FACTORY_REGISTRY is required")
	}
	if config.ImageFactoryNamespace == "" {
		config.ImageFactoryNamespace = "syscode-labs/image-factory"
	}
	if config.ImageFactoryCoreRegistry == "" {
		// Upstream Sidero base artifacts stay on public ghcr.io (anonymous
		// pulls); only factory-generated content lives on the internal registry.
		config.ImageFactoryCoreRegistry = "ghcr.io"
	}
	if config.ImageFactorySigningKey == "" {
		return fmt.Errorf("OMNI_IMAGE_FACTORY_SIGNING_KEY_PATH is required")
	}

	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}

	insecure := ""
	if config.ImageFactoryInsecure {
		insecure = `    insecure: true`
	}

	containerSignature := ""
	if config.ImageFactoryCosignKey != "" {
		containerSignature = fmt.Sprintf(`containerSignature:
  publicKeyFile: %s
`, config.ImageFactoryCosignKey)
	}

	extensionManifest := ""
	if config.ImageFactoryExtensionManifest != "" {
		extensionManifest = fmt.Sprintf(`extensionCatalog:
  sources:
    - name: firecracker
      manifest:
        registry: 127.0.0.1:5000
        namespace: custom-image-factory
        repository: %s
        insecure: true
      trust:
        publicKey:
          file: %s
          hashAlgo: sha256
`, config.ImageFactoryExtensionManifest, config.ImageFactoryCosignKey)
	}

	configYAML := fmt.Sprintf(`artifacts:
  core:
    registry: %s
  schematic:
    registry: %s
    namespace: %s
    repository: schematics
%s
  installer:
    internal:
      registry: %s
      namespace: %s
    repository: installer-internal
%s
%s
%s
cache:
  oci:
    registry: %s
    namespace: %s
    repository: cache
%s
  signingKeyPath: %s
http:
  externalURL: %s
metrics:
  addr: ""
`, config.ImageFactoryCoreRegistry, config.ImageFactoryRegistry, config.ImageFactoryNamespace, insecure, config.ImageFactoryRegistry, config.ImageFactoryNamespace, insecure, containerSignature, extensionManifest, config.ImageFactoryRegistry, config.ImageFactoryNamespace, insecure, config.ImageFactorySigningKey, config.ImageFactoryExternalURL)

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
	values := csvValues(csv)
	if len(values) == 0 {
		return nil, fmt.Errorf("at least one value is required")
	}

	return json.Marshal(values)
}

func csvValues(csv string) []string {
	parts := strings.Split(csv, ",")
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		value := strings.TrimSpace(part)
		if value != "" {
			values = append(values, value)
		}
	}

	return values
}

func sqlQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

// requireVersion fails loudly rather than let a caller silently fall back to
// a stale hardcoded default (the bug class this function exists to remove):
// versions must come from versions.yaml in syscode-homelab-gitops-apps, via
// --talos-version / --kubernetes-version.
func requireVersion(label, flag, value string) error {
	if value == "" {
		return fmt.Errorf("%s is required (no default; resolve it from versions.yaml and pass --%s)", label, flag)
	}

	return nil
}

func MachineClassDocuments(config Config) ([]map[string]any, error) {
	config = config.withDefaults()
	if err := requireVersion("talos version", "talos-version", config.TalosVersion); err != nil {
		return nil, err
	}

	return []map[string]any{
		{
			"metadata": map[string]any{
				"namespace": "default",
				"type":      "MachineClasses.omni.sidero.dev",
				"id":        config.MachineClass,
			},
			"spec": map[string]any{
				"installImage": config.InstallImage,
				"autoprovision": map[string]any{
					"providerid":   config.ProviderID,
					"providerdata": providerData(config),
				},
			},
		},
	}, nil
}

func ClusterDocuments(config Config) ([]map[string]any, error) {
	config = config.withDefaults()
	if err := requireVersion("talos version", "talos-version", config.TalosVersion); err != nil {
		return nil, err
	}
	if err := requireVersion("kubernetes version", "kubernetes-version", config.KubernetesVersion); err != nil {
		return nil, err
	}

	clusterPatches, err := clusterPatchFiles(config.TalosVersion)
	if err != nil {
		return nil, err
	}
	// Omni strips MachineClass.spec.installImage (see withDefaults), so the
	// custom installer reaches fresh nodes through a machine.install.image
	// config patch instead. It drives the initial install of a node only;
	// Omni's reconciliation of already-installed nodes against this image is
	// the Phase B schematic gap and is not claimed here.
	if config.InstallImage != "" {
		clusterPatches = append(clusterPatches, map[string]any{
			"name": "custom-install-image",
			"inline": map[string]any{
				"machine": map[string]any{
					"install": map[string]any{
						"image": config.InstallImage,
					},
				},
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

	return docs, nil
}

// clusterPatchFiles returns unraid-lab's base cluster patches (explicit, not
// globbed — omni/patches/ is a flat directory shared with other consumers, so
// globbing it would silently widen what unraid-lab applies) plus
// everything directly in omni/patches/<minor> for the given Talos version
// (applies only when the target Talos minor matches, so a Talos-1.14-only
// patch can never be emitted into a cluster targeting a different minor).
// Minor-dir results are sorted for deterministic output.
const patchesBaseDir = "omni/patches"

var baseClusterPatchFiles = []string{
	"omni/patches/cni-none.yaml",
	"omni/patches/disable-kube-proxy.yaml",
	"omni/patches/inline-manifests.yaml",
	"omni/patches/harbor-registry-mirror.yaml",
	"omni/patches/imp-node-labels.yaml",
}

func clusterPatchFiles(talosVersion string) ([]map[string]any, error) {
	minor, err := talosMinor(talosVersion)
	if err != nil {
		return nil, err
	}

	minorFiles, err := globPatchFiles(filepath.Join(patchesBaseDir, minor))
	if err != nil {
		return nil, err
	}
	sort.Strings(minorFiles)

	files := append(append([]string{}, baseClusterPatchFiles...), minorFiles...)

	patches := make([]map[string]any, 0, len(files))
	for _, file := range files {
		patches = append(patches, map[string]any{"file": file})
	}

	return patches, nil
}

// moduleRoot is the repo root, derived from this source file's own path so
// patch globbing works regardless of the caller's working directory (`go
// run` from the repo root vs. `go test` from this package's directory).
var moduleRoot = func() string {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		return "."
	}

	return filepath.Dir(filepath.Dir(filepath.Dir(thisFile)))
}()

func globPatchFiles(relDir string) ([]string, error) {
	matches, err := filepath.Glob(filepath.Join(moduleRoot, relDir, "*.yaml"))
	if err != nil {
		return nil, fmt.Errorf("glob %s: %w", relDir, err)
	}

	relMatches := make([]string, 0, len(matches))
	for _, match := range matches {
		rel, err := filepath.Rel(moduleRoot, match)
		if err != nil {
			return nil, fmt.Errorf("rel %s: %w", match, err)
		}
		relMatches = append(relMatches, filepath.ToSlash(rel))
	}

	return relMatches, nil
}

// talosMinor derives "1.14" from "v1.14.0" so minor-gated patch dirs
// (omni/patches/1.14/) can be matched against a target Talos version.
func talosMinor(version string) (string, error) {
	trimmed := strings.TrimPrefix(version, "v")
	parts := strings.SplitN(trimmed, ".", 3)
	if len(parts) < 2 || parts[0] == "" || parts[1] == "" {
		return "", fmt.Errorf("cannot derive Talos minor from version %q", version)
	}

	return parts[0] + "." + parts[1], nil
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
