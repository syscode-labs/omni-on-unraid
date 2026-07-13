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
	systemExtensions := docs[0]["systemExtensions"].([]string)
	if len(systemExtensions) != 1 || systemExtensions[0] != "siderolabs/tailscale" {
		t.Fatalf("systemExtensions = %v, want [siderolabs/tailscale]", systemExtensions)
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

func TestClusterAddsTailscaleAuthPatchWhenNodeAuthKeyIsSet(t *testing.T) {
	docs := ClusterDocuments(Config{NodesTailscaleAuthKey: "redacted-test-key"})

	patches := docs[0]["patches"].([]map[string]any)
	tailscalePatch := patches[len(patches)-1]
	if got := tailscalePatch["name"]; got != "tailscale-auth" {
		t.Fatalf("last patch name = %v, want tailscale-auth", got)
	}

	inline := tailscalePatch["inline"].(map[string]any)
	for key, want := range map[string]string{
		"apiVersion": "v1alpha1",
		"kind":       "ExtensionServiceConfig",
		"name":       "tailscale",
	} {
		if got := inline[key]; got != want {
			t.Fatalf("inline[%s] = %v, want %s", key, got, want)
		}
	}

	environment := inline["environment"].([]string)
	if len(environment) != 1 || environment[0] != "TS_AUTHKEY=redacted-test-key" {
		t.Fatalf("environment = %v, want TS_AUTHKEY entry", environment)
	}
}

func TestClusterOmitsTailscaleAuthPatchWhenNodeAuthKeyIsUnset(t *testing.T) {
	docs := ClusterDocuments(Config{})

	for _, patch := range docs[0]["patches"].([]map[string]any) {
		if patch["name"] == "tailscale-auth" {
			t.Fatalf("tailscale auth patch should be omitted when node auth key is unset: %v", patch)
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
