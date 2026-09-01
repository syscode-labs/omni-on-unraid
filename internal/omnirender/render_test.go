package omnirender

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMachineClassUsesLibvirtAutoprovisionProviderData(t *testing.T) {
	docs, err := MachineClassDocuments(Config{
		MachineClass: "lab",
		ProviderID:   "libvirt",
		StoragePool:  "omni-domains",
		NetworkName:  "default",
		TalosVersion: "v1.14.0-beta.1",
	})
	if err != nil {
		t.Fatalf("MachineClassDocuments returned error: %v", err)
	}

	if got := docs[0]["metadata"].(map[string]any)["id"]; got != "lab" {
		t.Fatalf("machine class id = %v, want lab", got)
	}

	spec := docs[0]["spec"].(map[string]any)
	if _, ok := spec["installImage"]; ok {
		t.Fatalf("MachineClass must not contain unsupported installImage: %v", spec)
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

func TestMachineClassRejectsTalosInstallerDrift(t *testing.T) {
	_, err := MachineClassDocuments(Config{
		MachineClass: "unraid-cp",
		TalosVersion: "v1.14.0-beta.1",
		InstallImage: "ghcr.io/syscode-labs/talos-images/installer:v1.13.7-libvirt",
	})
	if err == nil || !strings.Contains(err.Error(), "does not match Talos version") {
		t.Fatalf("MachineClassDocuments error = %v, want version/image drift error", err)
	}
}

func TestMachineClassGeneratedYAMLMatchesUnraidFixtures(t *testing.T) {
	for _, tc := range []struct {
		name  string
		class string
	}{
		{name: "control-plane", class: "unraid-cp"},
		{name: "worker", class: "unraid-worker"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			docs, err := MachineClassDocuments(Config{
				MachineClass: tc.class,
				TalosVersion: "v1.14.0-beta.1",
			})
			if err != nil {
				t.Fatalf("MachineClassDocuments returned error: %v", err)
			}

			var rendered strings.Builder
			if err := WriteYAML(&rendered, docs); err != nil {
				t.Fatalf("WriteYAML returned error: %v", err)
			}
			fixture, err := os.ReadFile(filepath.Join("testdata", "machineclass-"+tc.name+".yaml"))
			if err != nil {
				t.Fatalf("read fixture: %v", err)
			}
			if rendered.String() != string(fixture) {
				t.Fatalf("generated YAML differs from fixture:\n--- generated\n%s--- fixture\n%s", rendered.String(), fixture)
			}
		})
	}
}

func TestClusterDefaultsToThreeSchedulableControlPlanes(t *testing.T) {
	docs, err := ClusterDocuments(Config{
		ClusterName:       "lab",
		MachineClass:      "lab",
		TalosVersion:      "v1.13.7",
		KubernetesVersion: "v1.36.3",
	})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}

	if got := docs[0]["kind"]; got != "Cluster" {
		t.Fatalf("first doc kind = %v, want Cluster", got)
	}
	if got := docs[0]["name"]; got != "lab" {
		t.Fatalf("cluster name = %v, want lab", got)
	}
	extensions := docs[0]["systemExtensions"].([]string)
	if len(extensions) != 1 || extensions[0] != "syscode-labs/talos-ext-firecracker" {
		t.Fatalf("systemExtensions = %v, want syscode-labs/talos-ext-firecracker", extensions)
	}
	clusterPatches := docs[0]["patches"].([]map[string]any)
	for _, want := range []string{
		"omni/patches/cni-none.yaml",
		"omni/patches/disable-kube-proxy.yaml",
		"omni/patches/inline-manifests.yaml",
		"omni/patches/harbor-registry-mirror.yaml",
		"omni/patches/imp-node-labels.yaml",
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
	var installImagePatch map[string]any
	for _, patch := range clusterPatches {
		if patch["name"] == "custom-install-image" {
			installImagePatch = patch
			break
		}
	}
	if installImagePatch == nil {
		t.Fatalf("cluster patches must include install-image: %v", clusterPatches)
	}
	installInline := installImagePatch["inline"].(map[string]any)
	machine := installInline["machine"].(map[string]any)
	install := machine["install"].(map[string]any)
	if got := install["image"]; got != "ghcr.io/syscode-labs/talos-images/installer:v1.13.7-libvirt" {
		t.Fatalf("install image = %v, want v1.13.7 libvirt installer", got)
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
	docs, err := ClusterDocuments(Config{TalosVersion: "v1.13.7", KubernetesVersion: "v1.36.3"})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}

	for _, patch := range docs[0]["patches"].([]map[string]any) {
		if patch["name"] == "tailscale-auth" {
			t.Fatalf("no tailscale auth patch should ever be emitted: %v", patch)
		}
	}
}

func TestClusterRequiresTalosAndKubernetesVersions(t *testing.T) {
	if _, err := ClusterDocuments(Config{}); err == nil {
		t.Fatal("ClusterDocuments with no versions set should return an error, got nil")
	}
	if _, err := ClusterDocuments(Config{TalosVersion: "v1.13.7"}); err == nil {
		t.Fatal("ClusterDocuments with no kubernetes version should return an error, got nil")
	}
	if _, err := MachineClassDocuments(Config{}); err == nil {
		t.Fatal("MachineClassDocuments with no talos version should return an error, got nil")
	}
}

func TestClusterOmitsMinorGatedPatchesForOtherTalosMinor(t *testing.T) {
	docs, err := ClusterDocuments(Config{TalosVersion: "v1.13.7", KubernetesVersion: "v1.36.3"})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}

	for _, patch := range docs[0]["patches"].([]map[string]any) {
		if file, ok := patch["file"].(string); ok && strings.Contains(file, "/1.14/") {
			t.Fatalf("v1.13 cluster must not receive a 1.14-only patch: %v", patch)
		}
	}
}

func TestClusterV13PatchSetIsExactlyTheBaseFour(t *testing.T) {
	// omni/patches/ is a flat directory shared with other consumers. The base
	// patch set must stay explicit rather than a directory glob, or unraid-lab
	// would silently pick up patches that were never part of its rendered set.
	docs, err := ClusterDocuments(Config{TalosVersion: "v1.13.7", KubernetesVersion: "v1.36.3"})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}

	clusterPatches := docs[0]["patches"].([]map[string]any)
	filePatches := []string{
		"omni/patches/cni-none.yaml",
		"omni/patches/disable-kube-proxy.yaml",
		"omni/patches/inline-manifests.yaml",
		"omni/patches/harbor-registry-mirror.yaml",
		"omni/patches/imp-node-labels.yaml",
	}
	if len(clusterPatches) != len(filePatches)+1 {
		t.Fatalf("v1.13 cluster patches = %v, want base files plus custom-install-image", clusterPatches)
	}
	for i, w := range filePatches {
		if got := clusterPatches[i]["file"]; got != w {
			t.Fatalf("patch[%d] = %v, want %q", i, got, w)
		}
	}
	install := clusterPatches[len(clusterPatches)-1]
	if install["name"] != "custom-install-image" {
		t.Fatalf("last patch = %v, want custom-install-image", install)
	}
}

func TestClusterIncludesCustomInstallImagePatch(t *testing.T) {
	// MachineClass.installImage is stripped by Omni, so the cluster template
	// must carry the installer as a machine.install.image config patch.
	docs, err := ClusterDocuments(Config{TalosVersion: "v1.14.0-rc.1", KubernetesVersion: "v1.36.3"})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}

	var patch map[string]any
	for _, p := range docs[0]["patches"].([]map[string]any) {
		if p["name"] == "custom-install-image" {
			patch = p
			break
		}
	}
	if patch == nil {
		t.Fatalf("cluster patches missing custom-install-image: %v", docs[0]["patches"])
	}

	machine := patch["inline"].(map[string]any)["machine"].(map[string]any)
	install := machine["install"].(map[string]any)
	want := "ghcr.io/syscode-labs/talos-images/installer:v1.14.0-rc.1-libvirt"
	if got := install["image"]; got != want {
		t.Fatalf("install image = %v, want %q", got, want)
	}
}

func TestClusterIncludesMinorGatedPatchesForMatchingTalosMinor(t *testing.T) {
	docs, err := ClusterDocuments(Config{TalosVersion: "v1.14.0", KubernetesVersion: "v1.36.3"})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}

	for _, want := range []string{
		"omni/patches/1.14/runtime-compat.yaml",
		"omni/patches/1.14/workload-isolation.yaml",
	} {
		found := false
		for _, patch := range docs[0]["patches"].([]map[string]any) {
			if patch["file"] == want {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("v1.14 cluster missing minor-gated patch %q", want)
		}
	}
}

func TestClusterAddsWorkersWhenRequested(t *testing.T) {
	docs, err := ClusterDocuments(Config{Workers: 2, TalosVersion: "v1.13.7", KubernetesVersion: "v1.36.3"})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}

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

	docs, err := ClusterDocuments(Config{ClusterName: "lab", TalosVersion: "v1.13.7", KubernetesVersion: "v1.36.3"})
	if err != nil {
		t.Fatalf("ClusterDocuments returned error: %v", err)
	}
	if err := WriteYAML(&out, docs); err != nil {
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
	t.Setenv("OMNI_DOMAIN", "")

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

func TestPocketIDOIDCClientSQLUsesTailnetDomainOnly(t *testing.T) {
	t.Setenv("OMNI_DOMAIN", "omni.lab.ts.net")
	t.Setenv("OMNI_PUBLIC_DOMAIN", "omni.example.com")

	sql, err := PocketIDOIDCClientSQL(Config{})
	if err != nil {
		t.Fatalf("PocketIDOIDCClientSQL returned error: %v", err)
	}

	want := `'["https://omni.lab.ts.net/oidc/consume"]'::jsonb`
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
		"core:\n    registry: ghcr.io",
		"registry: registry.example.ts.net:5000",
		"namespace: syscode-labs/image-factory",
		"repository: schematics",
		"repository: installer-internal",
		"repository: cache",
		"signingKeyPath: /keys/cache-signing.key",
		"externalURL: https://factory.example.ts.net",
		"metrics:\n  addr: \"\"",
	} {
		if !strings.Contains(config, want) {
			t.Fatalf("image-factory config missing %q:\n%s", want, config)
		}
	}
	for _, absent := range []string{
		"external:",
		"repository: installer\n",
		"insecure: true",
		"containerSignature:",
		"publicKeyFile:",
	} {
		if strings.Contains(config, absent) {
			t.Fatalf("image-factory config should not contain %q:\n%s", absent, config)
		}
	}
}

func TestImageFactoryConfigDoesNotOverrideGlobalSignatureTrust(t *testing.T) {
	outputPath := filepath.Join(t.TempDir(), "config.yaml")

	err := ImageFactoryConfig(outputPath, Config{
		ImageFactoryExternalURL: "https://factory.example.ts.net",
		ImageFactoryRegistry:    "127.0.0.1:5000",
		ImageFactoryNamespace:   "syscode-labs/omni-image-factory",
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
	config := string(configYAML)
	if strings.Contains(config, "containerSignature:") {
		t.Fatalf("image-factory config must retain Sidero's keyless default trust:\n%s", config)
	}
}

func TestImageFactoryConfigEmitsReplacementExtensionManifest(t *testing.T) {
	outputPath := filepath.Join(t.TempDir(), "config.yaml")

	err := ImageFactoryConfig(outputPath, Config{
		ImageFactoryExternalURL:       "https://factory.example.ts.net",
		ImageFactoryRegistry:          "127.0.0.1:5000",
		ImageFactorySigningKey:        "/keys/cache-signing.key",
		ImageFactoryCosignKey:         "/keys/cosign.pub",
		ImageFactoryExtensionManifest: "syscode-labs/talos-extensions-composite",
	})
	if err != nil {
		t.Fatalf("ImageFactoryConfig returned error: %v", err)
	}

	configYAML, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("ReadFile image-factory config: %v", err)
	}
	config := string(configYAML)
	for _, want := range []string{
		"- name: sidero\n      manifest:\n        registry: ghcr.io\n        repository: siderolabs/extensions",
		"- name: firecracker\n      manifest:\n        registry: 127.0.0.1:5000\n        repository: custom-image-factory/syscode-labs/talos-extensions-composite",
		"publicKey:\n          file: /keys/cosign.pub",
	} {
		if !strings.Contains(config, want) {
			t.Fatalf("image-factory config missing %q:\n%s", want, config)
		}
	}
	if strings.Index(config, "artifacts:\n  core:\n    registry: ghcr.io\n  schematic:") > strings.Index(config, "extensionCatalog:") {
		t.Fatalf("artifacts.schematic must not be nested under extensionCatalog:\n%s", config)
	}
	if !strings.Contains(config, "artifacts:\n  core:\n    registry: ghcr.io\n  schematic:\n    registry: 127.0.0.1:5000") {
		t.Fatalf("image-factory config missing top-level artifacts.schematic:\n%s", config)
	}
}

func TestImageFactoryConfigInsecureInternalRegistry(t *testing.T) {
	outputPath := filepath.Join(t.TempDir(), "config.yaml")

	err := ImageFactoryConfig(outputPath, Config{
		ImageFactoryExternalURL:  "https://factory.example.ts.net",
		ImageFactoryRegistry:     "127.0.0.1:5000",
		ImageFactoryNamespace:    "syscode-labs/omni-image-factory",
		ImageFactoryCoreRegistry: "ghcr.io",
		ImageFactoryInsecure:     true,
		ImageFactorySigningKey:   "/keys/cache-signing.key",
		ImageFactoryCosignKey:    "/keys/cosign.pub",
	})
	if err != nil {
		t.Fatalf("ImageFactoryConfig returned error: %v", err)
	}

	configYAML, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("ReadFile omni-image-factory config: %v", err)
	}
	config := string(configYAML)
	if got := strings.Count(config, "insecure: true"); got != 3 {
		t.Fatalf("insecure: true count = %d, want 3 (schematic/internal installer/cache):\n%s", got, config)
	}
	if strings.Contains(config, "repository: installer\n") {
		t.Fatalf("installer.external block should be omitted:\n%s", config)
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
