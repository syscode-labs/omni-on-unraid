package releasedispatch

import (
	"strings"
	"testing"
)

const validPayload = `{
  "release_id":"talos-v1.14.0",
  "source_repo":"syscode-labs/syscode-homelab-gitops-apps",
  "source_sha":"0123456789abcdef0123456789abcdef01234567",
  "sender_repo":"syscode-labs/talos-release-controller",
  "talos_version":"v1.14.0",
  "kubernetes_version":"v1.36.3",
  "idempotency_key":"talos-v1.14.0",
  "build_run_id":123,
  "artifacts":{"unraid":{"ref":"ghcr.io/syscode-labs/talos-images/installer:v1.14.0-libvirt","digest":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"},"oci":{"ref":"ghcr.io/syscode-labs/talos-images/installer:v1.14.0","digest":"sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210","image_ocid":"ocid1.image.oc1.example"}}
}`

func TestParseAcceptsControllerImmutableLibvirtArtifact(t *testing.T) {
	request, err := Parse([]byte(validPayload))
	if err != nil {
		t.Fatalf("Parse returned error: %v", err)
	}
	want := "ghcr.io/syscode-labs/talos-images/installer:v1.14.0-libvirt@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	if got := request.InstallerImage(); got != want {
		t.Fatalf("InstallerImage() = %q, want %q", got, want)
	}
}

func TestParseRejectsUntrustedOrMutableReleaseInput(t *testing.T) {
	for name, replacement := range map[string]string{
		"sender":      `"sender_repo":"syscode-labs/attacker"`,
		"source":      `"source_repo":"syscode-labs/attacker"`,
		"idempotency": `"idempotency_key":"different-release"`,
		"digest":      `"digest":"sha256:not-a-digest"`,
		"tag":         `"ref":"ghcr.io/syscode-labs/talos-images/installer:v1.13.0-libvirt"`,
	} {
		t.Run(name, func(t *testing.T) {
			payload := validPayload
			switch name {
			case "sender":
				payload = strings.Replace(payload, `"sender_repo":"syscode-labs/talos-release-controller"`, replacement, 1)
			case "source":
				payload = strings.Replace(payload, `"source_repo":"syscode-labs/syscode-homelab-gitops-apps"`, replacement, 1)
			case "idempotency":
				payload = strings.Replace(payload, `"idempotency_key":"talos-v1.14.0"`, replacement, 1)
			case "digest":
				payload = strings.Replace(payload, `"digest":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"`, replacement, 1)
			case "tag":
				payload = strings.Replace(payload, `"ref":"ghcr.io/syscode-labs/talos-images/installer:v1.14.0-libvirt"`, replacement, 1)
			}
			if _, err := Parse([]byte(payload)); err == nil {
				t.Fatal("Parse accepted unsafe release input")
			}
		})
	}
}

func TestParseRejectsUnknownRequestFields(t *testing.T) {
	payload := strings.Replace(validPayload, "\n}", `,"unexpected":true
}`, 1)
	if _, err := Parse([]byte(payload)); err == nil {
		t.Fatal("Parse accepted an unknown request field")
	}
}

func TestResultPropagatesFailureWithAcceptedBuildCorrelation(t *testing.T) {
	request, err := Parse([]byte(validPayload))
	if err != nil {
		t.Fatalf("Parse returned error: %v", err)
	}
	result, err := Result(request, "failure", 456, "https://github.com/syscode-labs/omni-on-unraid/actions/runs/456", "failed_pre_mutation")
	if err != nil {
		t.Fatalf("Result returned error: %v", err)
	}
	if result.Outcome != "failure" || result.AttemptState != "failed_pre_mutation" || result.BuildRunID != request.BuildRunID || result.Artifacts != request.Artifacts {
		t.Fatalf("failure callback lost controller correlation or recovery classification: %#v", result)
	}
}

func TestResultRejectsRetryClassificationAfterClaimOrOnSuccess(t *testing.T) {
	request, err := Parse([]byte(validPayload))
	if err != nil {
		t.Fatalf("Parse returned error: %v", err)
	}
	if _, err := Result(request, "success", 456, "https://example.test/run/456", "failed_pre_mutation"); err == nil {
		t.Fatal("success callback accepted a retry classification")
	}
	if _, err := Result(request, "failure", 456, "https://example.test/run/456", "unknown"); err == nil {
		t.Fatal("callback accepted an unknown recovery classification")
	}
}
