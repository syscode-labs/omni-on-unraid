package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"strings"
	"testing"
)

const acceptedRequest = `{"release_id":"talos-v1.14.0","source_repo":"syscode-labs/syscode-homelab-gitops-apps","source_sha":"0123456789abcdef0123456789abcdef01234567","sender_repo":"syscode-labs/talos-release-controller","talos_version":"v1.14.0","kubernetes_version":"v1.36.3","idempotency_key":"talos-v1.14.0","build_run_id":123,"artifacts":{"unraid":{"ref":"ghcr.io/syscode-labs/talos-images/installer:v1.14.0-libvirt","digest":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"},"oci":{"ref":"ghcr.io/syscode-labs/talos-images/installer:v1.14.0","digest":"sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210","image_ocid":"ocid1.image.oc1.example"}}}`

func TestExecutableResultProducerEmitsBoundPreMutationCallback(t *testing.T) {
	command := exec.Command("go", "run", ".")
	command.Stdin = strings.NewReader(acceptedRequest)
	command.Env = append(os.Environ(),
		"GITHUB_RUN_ID=456",
		"GITHUB_SERVER_URL=https://github.com",
		"GITHUB_REPOSITORY=syscode-labs/omni-on-unraid",
		"OUTCOME=failure",
		"ATTEMPT_STATE=failed_pre_mutation",
	)
	output, err := command.Output()
	if err != nil {
		t.Fatalf("run callback producer: %v", err)
	}
	var envelope struct {
		EventType     string                 `json:"event_type"`
		ClientPayload map[string]interface{} `json:"client_payload"`
	}
	if err := json.Unmarshal(output, &envelope); err != nil {
		t.Fatalf("decode callback: %v", err)
	}
	if envelope.EventType != "talos-release-result" || len(envelope.ClientPayload) != 10 {
		t.Fatalf("unexpected callback envelope: %#v", envelope)
	}
	if envelope.ClientPayload["attempt_state"] != "failed_pre_mutation" || envelope.ClientPayload["build_run_id"] != float64(123) {
		t.Fatalf("callback did not preserve retry and artifact correlation: %#v", envelope.ClientPayload)
	}
}
