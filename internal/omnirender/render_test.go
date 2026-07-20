package omnirender

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMachineClassUsesLibvirtAutoprovisionProviderData(t *testing.T) {
	docs := MachineClassDocuments(Config{
		MachineClass: "lab",
		ProviderID:   "libvirt",
		StoragePool:  "omni-domains",
		NetworkName:  "default",
	})

	if got := docs[0]["metadata"].(map[string]any)["id"]; got != "lab" {
		t.Fatalf("machine class id = %v, want lab", got)
	}

	spec := docs[0]["spec"].(map[string]any)
	if got := spec["installImage"]; got != "ghcr.io/syscode-labs/talos-images/installer:v1.13.6" {
		t.Fatalf("installImage = %v, want installer:v1.13.6", got)
	}
	autoprovision := spec["autoprovision"].(map[string]any)
	if got := autoprovision["providerid"]; got != "libvirt" {
		t.Fatalf("providerid = %v, want libvirt", got)
	}

	providerData := autoprovision["providerdata"].(string)
	for _, want := range []string{
		"storage_pool: \"omni-domains\"",
		"network_interfaces:",
		"network_name: \"default\"",
	} {
		if !strings.Contains(providerData, want) {
			t.Fatalf("providerdata missing %q:\n%s", want, providerData)
		}
	}
	// Nodes join via routed tailnet (bookofshadows subnet route), not an early
	// tailscale extension — the boot schematic must carry no tailscale.
	if strings.Contains(providerData, "tailscale") {
		t.Fatalf("providerdata should not reference tailscale:\n%s", providerData)
	}
}

func TestClusterDefaultsToThreeSchedulableControlPlanes(t *testing.T) {
	docs := ClusterDocuments(Config{
		ClusterName:  "lab",
		MachineClass: "lab",
	})

	if got := docs[0]["kind"]; got != "Cluster" {
		t.Fatalf("first doc kind = %v, want Cluster", got)
	}
	if got := docs[0]["name"]; got != "lab" {
		t.Fatalf("cluster name = %v, want lab", got)
	}
	if _, ok := docs[0]["systemExtensions"]; ok {
		t.Fatalf("systemExtensions should be omitted when none set, got %v", docs[0]["systemExtensions"])
	}
	clusterPatches := docs[0]["patches"].([]map[string]any)
	for _, want := range []string{
		"omni/patches/cni-none.yaml",
		"omni/patches/disable-kube-proxy.yaml",
		"omni/patches/inline-manifests.yaml",
	} {
		found := false
		for _, patch := range clusterPatches {
			if patch["file"] == want {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("cluster patches missing %q: %v", want, clusterPatches)
		}
	}
	for _, patch := range clusterPatches {
		if patch["name"] == "install-image" {
			t.Fatalf("cluster must not patch install image; Omni does not treat it as organic image drift: %v", patch)
		}
	}

	controlPlane := docs[1]
	if got := controlPlane["kind"]; got != "ControlPlane" {
		t.Fatalf("second doc kind = %v, want ControlPlane", got)
	}

	machineClass := controlPlane["machineClass"].(map[string]any)
	if got := machineClass["size"]; got != 3 {
		t.Fatalf("control plane size = %v, want 3", got)
	}

	patches := controlPlane["patches"].([]map[string]any)
	inline := patches[0]["inline"].(map[string]any)
	cluster := inline["cluster"].(map[string]any)
	if got := cluster["allowSchedulingOnControlPlanes"]; got != true {
		t.Fatalf("allowSchedulingOnControlPlanes = %v, want true", got)
	}

	if len(docs) != 2 {
		t.Fatalf("doc count = %d, want 2", len(docs))
	}
}

func TestClusterEmitsNoTailscaleAuthPatch(t *testing.T) {
	// Early tailscale is gone: nodes reach tailnet-only Omni via the bookofshadows
	// subnet route, so no ExtensionServiceConfig auth patch is ever rendered.
	docs := ClusterDocuments(Config{})

	for _, patch := range docs[0]["patches"].([]map[string]any) {
		if patch["name"] == "tailscale-auth" {
			t.Fatalf("no tailscale auth patch should ever be emitted: %v", patch)
		}
	}
}

func TestClusterAddsWorkersWhenRequested(t *testing.T) {
	docs := ClusterDocuments(Config{Workers: 2})

	workers := docs[2]
	if got := workers["kind"]; got != "Workers" {
		t.Fatalf("worker doc kind = %v, want Workers", got)
	}
	if got := workers["name"]; got != "worker" {
		t.Fatalf("worker name = %v, want worker", got)
	}
	machineClass := workers["machineClass"].(map[string]any)
	if got := machineClass["size"]; got != 2 {
		t.Fatalf("worker size = %v, want 2", got)
	}
}

func TestWriteYAMLUsesMultiDocumentOutput(t *testing.T) {
	var out strings.Builder

	if err := WriteYAML(&out, ClusterDocuments(Config{ClusterName: "lab"})); err != nil {
		t.Fatalf("WriteYAML returned error: %v", err)
	}

	rendered := out.String()
	if !strings.Contains(rendered, "---\nkind: Cluster\n") {
		t.Fatalf("rendered YAML missing Cluster document:\n%s", rendered)
	}
	if !strings.Contains(rendered, "---\nkind: ControlPlane\n") {
		t.Fatalf("rendered YAML missing ControlPlane document:\n%s", rendered)
	}
}

func TestPocketIDOIDCClientSQLUsesOmniCallbackAndConfidentialClient(t *testing.T) {
	sql, err := PocketIDOIDCClientSQL(Config{})
	if err != nil {
		t.Fatalf("PocketIDOIDCClientSQL returned error: %v", err)
	}

	for _, want := range []string{
		"WHERE id = 'omni';",
		`'["https://omni.example.internal/oidc/consume"]'::jsonb`,
		"is_public = false",
		"pkce_enabled = false",
	} {
		if !strings.Contains(sql, want) {
			t.Fatalf("SQL missing %q:\n%s", want, sql)
		}
	}
}

func TestPocketIDOIDCClientSQLUsesEnvDomains(t *testing.T) {
	t.Setenv("OMNI_DOMAIN", "omni.lab.ts.net")
	t.Setenv("OMNI_PUBLIC_DOMAIN", "omni.example.com")

	sql, err := PocketIDOIDCClientSQL(Config{})
	if err != nil {
		t.Fatalf("PocketIDOIDCClientSQL returned error: %v", err)
	}

	want := `'["https://omni.lab.ts.net/oidc/consume","https://omni.example.com/oidc/consume"]'::jsonb`
	if !strings.Contains(sql, want) {
		t.Fatalf("SQL missing env callbacks %q:\n%s", want, sql)
	}
}

func TestPocketIDOIDCClientSQLRejectsEmptyCallbacks(t *testing.T) {
	_, err := PocketIDOIDCClientSQL(Config{OIDCCallbackURLs: " , "})
	if err == nil {
		t.Fatal("PocketIDOIDCClientSQL returned nil error for empty callbacks")
	}
}

func TestProviderOverlayUsesEnvLibvirtURI(t *testing.T) {
	t.Setenv("OMNI_PROVIDER_LIBVIRT_URI", "qemu+libssh://omniops@lab-host/system?known_hosts_verify=ignore")
	outputDir := filepath.Join(t.TempDir(), "generated", "omni-vm-libvirt-provider", "overlays", "lab")

	if err := ProviderOverlay(outputDir, Config{}); err != nil {
		t.Fatalf("ProviderOverlay returned error: %v", err)
	}

	configMap, err := os.ReadFile(filepath.Join(outputDir, "config-map-patch.yaml"))
	if err != nil {
		t.Fatalf("ReadFile config-map-patch.yaml: %v", err)
	}
	if !strings.Contains(string(configMap), "qemu+libssh://omniops@lab-host/system?known_hosts_verify=ignore") {
		t.Fatalf("provider config missing libvirt URI:\n%s", string(configMap))
	}
}

func TestProviderConfigUsesEnvLibvirtURI(t *testing.T) {
	t.Setenv("OMNI_PROVIDER_LIBVIRT_URI", "qemu+libssh://omniops@lab-host/system?known_hosts_verify=ignore")
	outputPath := filepath.Join(t.TempDir(), "generated", "provider", "libvirt-config.yaml")

	if err := ProviderConfig(outputPath, Config{}); err != nil {
		t.Fatalf("ProviderConfig returned error: %v", err)
	}

	configYAML, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("ReadFile libvirt-config.yaml: %v", err)
	}
	if !strings.Contains(string(configYAML), "qemu+libssh://omniops@lab-host/system?known_hosts_verify=ignore") {
		t.Fatalf("provider config missing libvirt URI:\n%s", string(configYAML))
	}
}

func TestImageFactoryConfigUsesEnv(t *testing.T) {
	t.Setenv("OMNI_IMAGE_FACTORY_ADDRESS", "https://factory.example.ts.net")
	t.Setenv("OMNI_IMAGE_FACTORY_REGISTRY", "registry.example.ts.net:5000")
	t.Setenv("OMNI_IMAGE_FACTORY_SIGNING_KEY_PATH", "/keys/cache-signing.key")
	t.Setenv("OMNI_IMAGE_FACTORY_COSIGN_PUBLIC_KEY_PATH", "/keys/cosign.pub")
	outputPath := filepath.Join(t.TempDir(), "generated", "image-factory", "config.yaml")

	if err := ImageFactoryConfig(outputPath, Config{}); err != nil {
		t.Fatalf("ImageFactoryConfig returned error: %v", err)
	}

	configYAML, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("ReadFile image-factory config: %v", err)
	}
	config := string(configYAML)
	for _, want := range []string{
		"registry: registry.example.ts.net:5000",
		"namespace: syscode-labs/image-factory",
		"repository: schematics",
		"repository: installer",
		"repository: cache",
		"publicKeyFile: /keys/cosign.pub",
		"signingKeyPath: /keys/cache-signing.key",
		"externalURL: https://factory.example.ts.net",
	} {
		if !strings.Contains(config, want) {
			t.Fatalf("image factory config missing %q:\n%s", want, config)
		}
	}
}

func TestImageFactoryConfigUsesCustomNamespace(t *testing.T) {
	outputPath := filepath.Join(t.TempDir(), "config.yaml")

	err := ImageFactoryConfig(outputPath, Config{
		ImageFactoryExternalURL: "https://factory.example.ts.net",
		ImageFactoryRegistry:    "ghcr.io",
		ImageFactoryNamespace:   "syscode-labs/talos-factory",
		ImageFactorySigningKey:  "/keys/cache-signing.key",
		ImageFactoryCosignKey:   "/keys/cosign.pub",
	})
	if err != nil {
		t.Fatalf("ImageFactoryConfig returned error: %v", err)
	}

	configYAML, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("ReadFile image-factory config: %v", err)
	}
	if !strings.Contains(string(configYAML), "namespace: syscode-labs/talos-factory") {
		t.Fatalf("image factory config missing custom namespace:\n%s", configYAML)
	}
}

func TestImageFactoryConfigRequiresAddress(t *testing.T) {
	err := ImageFactoryConfig(filepath.Join(t.TempDir(), "config.yaml"), Config{})
	if err == nil || !strings.Contains(err.Error(), "OMNI_IMAGE_FACTORY_ADDRESS is required") {
		t.Fatalf("ImageFactoryConfig error = %v, want missing address", err)
	}
}
