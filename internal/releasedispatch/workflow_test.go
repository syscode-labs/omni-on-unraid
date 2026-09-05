package releasedispatch

import (
	"os"
	"strings"
	"testing"
)

func TestReleaseDispatchKeepsDedicatedRunnerAndHostedCallback(t *testing.T) {
	workflow, err := os.ReadFile("../../.github/workflows/release-dispatch.yml")
	if err != nil {
		t.Fatalf("read release dispatch workflow: %v", err)
	}
	text := string(workflow)
	if !strings.Contains(text, "runs-on:\n      group: omni-runner\n      labels: self-hosted") {
		t.Fatal("release rollout must remain pinned to the omni-runner group")
	}
	if !strings.Contains(text, "runs-on: ubuntu-latest") {
		t.Fatal("release callback must remain on a GitHub-hosted runner")
	}
	if strings.Count(text, "uses: actions/setup-go@v5") != 1 ||
		strings.Count(text, "go-version-file: go.mod") != 1 {
		t.Fatal("the hosted callback Go job must install the go.mod toolchain")
	}
	const miseSetup = "uses: jdx/mise-action@c2a87611a18de5b3828c5652fe268e992400cb5c # v4.3.0\n        with:\n          install: false"
	if !strings.Contains(text, miseSetup) {
		t.Fatal("private rollout runner must explicitly install mise without installing every mise.toml tool")
	}
	if strings.Contains(text, "test -x \"$HOME/.local/bin/mise\"") {
		t.Fatal("release runtime receipt must not assert an obsolete mise shim path")
	}
	miseConfig, err := os.ReadFile("../../mise.toml")
	if err != nil {
		t.Fatalf("read mise config: %v", err)
	}
	if strings.Contains(string(miseConfig), "{{.State.Running}}") {
		t.Fatal("provider status task must not embed a Docker Go template that mise parses as its own template")
	}
	const runtimeInstall = "mise install omnictl yq \"kubectl@${RELEASE_KUBERNETES_VERSION}\" \"talosctl@${RELEASE_TALOS_VERSION}\""
	if strings.Index(text, miseSetup) > strings.Index(text, runtimeInstall) {
		t.Fatal("mise must be installed before the rollout runtime receipt uses it")
	}
	if strings.Index(text, "cat \"$validated\" >> \"$GITHUB_ENV\"") > strings.Index(text, runtimeInstall) {
		t.Fatal("the runtime receipt must run after validated release versions are exported")
	}
	if !strings.Contains(text, runtimeInstall) ||
		!strings.Contains(text, "mise exec \"kubectl@${RELEASE_KUBERNETES_VERSION}\" -- kubectl version --client") ||
		!strings.Contains(text, "mise exec \"talosctl@${RELEASE_TALOS_VERSION}\" -- talosctl version --client") {
		t.Fatal("private rollout runner must install and execute the exact non-OpenTofu release runtime")
	}
	for _, selection := range []string{
		"MISE_TALOSCTL_VERSION=\"$RELEASE_TALOS_VERSION\"",
		"MISE_KUBECTL_VERSION=\"$RELEASE_KUBERNETES_VERSION\"",
	} {
		if strings.Count(text, selection) < 4 {
			t.Fatalf("payload-derived runtime selection must cover the receipt and every release stage: %q", selection)
		}
	}
	for _, persisted := range []string{
		"printf 'MISE_TALOSCTL_VERSION=%s\\n' \"$MISE_TALOSCTL_VERSION\" >> \"$GITHUB_ENV\"",
		"printf 'MISE_KUBECTL_VERSION=%s\\n' \"$MISE_KUBECTL_VERSION\" >> \"$GITHUB_ENV\"",
	} {
		if strings.Count(text, persisted) != 1 {
			t.Fatalf("payload-derived runtime selection must persist for later workflow steps: %q", persisted)
		}
	}
	for _, stage := range []string{"preflight", "apply", "health"} {
		if strings.Count(text, "mise exec -- mise run omni:release:"+stage) != 1 {
			t.Fatalf("native rollout runner must execute the %s stage exactly once", stage)
		}
	}
	for _, required := range []string{
		"OMNI_ENDPOINT: ${{ secrets.OMNI_ENDPOINT }}",
		"OMNI_SERVICE_ACCOUNT_KEY: ${{ secrets.OMNI_SERVICE_ACCOUNT_KEY }}",
		"OMNI_PROVIDER_COMPOSE_FILE: /opt/omni/omni/provider/docker-compose.yml",
		"OMNI_PROVIDER_PROJECT_NAME: omni-libvirt-provider",
		"OMNI_PROVIDER_CONTAINER: omni-infra-provider-libvirt",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("private rollout must use the approved runtime configuration: %q", required)
		}
	}
	health, err := os.ReadFile("../../scripts/verify-release-health.sh")
	if err != nil {
		t.Fatalf("read release health script: %v", err)
	}
	for _, required := range []string{
		"omnictl kubeconfig -c \"$cluster_name\" --service-account",
		"omnictl talosconfig -c \"$cluster_name\" --force --merge=false",
		"export KUBECONFIG=\"$kubeconfig\"",
	} {
		if !strings.Contains(string(health), required) {
			t.Fatalf("release health must generate fresh service-account evidence: %q", required)
		}
	}
	for _, forbidden := range []string{"ssh ", "/opt/actions-runner/_work", "rsync -a --delete"} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("native rollout must not retain the unsafe remote runtime path: %q", forbidden)
		}
	}
}
