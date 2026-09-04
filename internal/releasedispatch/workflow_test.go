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
	if !strings.Contains(text, "runs-on: [self-hosted, omni-runner]") {
		t.Fatal("release rollout must remain pinned to the omni-runner label")
	}
	if !strings.Contains(text, "runs-on: ubuntu-latest") {
		t.Fatal("release callback must remain on a GitHub-hosted runner")
	}
}
