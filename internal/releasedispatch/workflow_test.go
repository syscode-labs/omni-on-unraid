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
	if strings.Count(text, "uses: actions/setup-go@v5") != 2 ||
		strings.Count(text, "go-version-file: go.mod") != 2 {
		t.Fatal("both release jobs that execute Go must install the go.mod toolchain")
	}
	if !strings.Contains(text, "mise install go") || !strings.Contains(text, "mise exec -- go version") {
		t.Fatal("private rollout runner must verify its mise-managed Go runtime before mutation")
	}
}
