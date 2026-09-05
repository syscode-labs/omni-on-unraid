package providerartifact_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckProviderArtifactUsesExactComposeImageAndFailsClosed(t *testing.T) {
	repoRoot := findRepoRoot(t)
	cases := []struct {
		name      string
		image     string
		status    string
		failure   string
		wantOK    bool
		wantError string
	}{
		{name: "available tag", image: "ghcr.io/example/provider:v1.2.3", status: "0", wantOK: true},
		{name: "available digest", image: "ghcr.io/example/provider@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", status: "0", wantOK: true},
		{name: "missing artifact", image: "ghcr.io/example/provider:v1.2.3", status: "1", failure: "manifest unknown", wantError: "unavailable or inaccessible"},
		{name: "registry authentication failure", image: "ghcr.io/example/provider:v1.2.3", status: "1", failure: "unauthorized", wantError: "unavailable or inaccessible"},
		{name: "registry network failure", image: "ghcr.io/example/provider:v1.2.3", status: "1", failure: "dial tcp: network unreachable", wantError: "unavailable or inaccessible"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			script := copyArtifactScript(t, repoRoot, root)
			fakeDocker := writeFakeDocker(t, root)
			if err := os.WriteFile(filepath.Join(root, ".env"), nil, 0o600); err != nil {
				t.Fatal(err)
			}

			cmd := exec.Command("bash", script)
			cmd.Dir = root
			cmd.Env = append(os.Environ(),
				"DOCKER_BIN="+fakeDocker,
				"FAKE_DOCKER_IMAGE="+tc.image,
				"FAKE_DOCKER_MANIFEST_STATUS="+tc.status,
				"FAKE_DOCKER_FAILURE="+tc.failure,
				"FAKE_DOCKER_LOG="+filepath.Join(root, "docker.args"),
				"OMNI_PROVIDER_ARTIFACT_TIMEOUT_SECONDS=3",
			)
			output, err := cmd.CombinedOutput()
			if tc.wantOK && err != nil {
				t.Fatalf("artifact check failed: %v\n%s", err, output)
			}
			if !tc.wantOK {
				if err == nil {
					t.Fatalf("artifact check unexpectedly passed:\n%s", output)
				}
				if !strings.Contains(string(output), tc.wantError) {
					t.Fatalf("error did not fail closed as expected:\n%s", output)
				}
				if !strings.Contains(string(output), tc.failure) {
					t.Fatalf("registry failure detail was not retained:\n%s", output)
				}
			}

			args, readErr := os.ReadFile(filepath.Join(root, "docker.args"))
			if readErr != nil {
				t.Fatal(readErr)
			}
			if !strings.Contains(string(args), "manifest inspect "+tc.image) {
				t.Fatalf("manifest check did not use exact configured image %q:\n%s", tc.image, args)
			}
		})
	}
}

func TestCheckProviderArtifactHonorsComposeFileOverride(t *testing.T) {
	repoRoot := findRepoRoot(t)
	root := t.TempDir()
	script := copyArtifactScript(t, repoRoot, root)
	fakeDocker := writeFakeDocker(t, root)
	if err := os.WriteFile(filepath.Join(root, ".env"), nil, 0o600); err != nil {
		t.Fatal(err)
	}

	override := filepath.Join(root, "provider.override.yml")
	cmd := exec.Command("bash", script)
	cmd.Dir = root
	cmd.Env = append(os.Environ(),
		"DOCKER_BIN="+fakeDocker,
		"FAKE_DOCKER_IMAGE=ghcr.io/example/provider:overridden",
		"FAKE_DOCKER_MANIFEST_STATUS=0",
		"FAKE_DOCKER_LOG="+filepath.Join(root, "docker.args"),
		"OMNI_PROVIDER_COMPOSE_FILE="+override,
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("artifact check with override failed: %v\n%s", err, output)
	}

	args, err := os.ReadFile(filepath.Join(root, "docker.args"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(args), "--file "+override) {
		t.Fatalf("compose override was not used:\n%s", args)
	}
}

func copyArtifactScript(t *testing.T, repoRoot, root string) string {
	t.Helper()
	source := filepath.Join(repoRoot, "scripts", "check-provider-artifact.sh")
	contents, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "scripts", "check-provider-artifact.sh")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, contents, 0o755); err != nil {
		t.Fatal(err)
	}
	return target
}

func writeFakeDocker(t *testing.T, root string) string {
	t.Helper()
	path := filepath.Join(root, "docker")
	contents := `#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
if [[ " $* " == *" config --images omni-infra-provider-libvirt "* ]]; then
  printf '%s\n' "$FAKE_DOCKER_IMAGE"
  exit 0
fi
if [[ " $* " == *" manifest inspect "* ]]; then
  if [ "$FAKE_DOCKER_MANIFEST_STATUS" -ne 0 ]; then
    echo "$FAKE_DOCKER_FAILURE" >&2
  fi
  exit "$FAKE_DOCKER_MANIFEST_STATUS"
fi
echo "unexpected docker invocation: $*" >&2
exit 2
`
	if err := os.WriteFile(path, []byte(contents), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func findRepoRoot(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("could not find repository root")
		}
		dir = parent
	}
}
