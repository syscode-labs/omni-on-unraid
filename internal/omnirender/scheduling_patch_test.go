package omnirender

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Run against real Talos patch semantics, not a YAML merge approximation:
// mise exec talosctl@1.14.0 -- env TALOSCTL=talosctl go test ./internal/omnirender -run TestControlPlaneSchedulingPatch -v
// Talos v1.14.0's configpatcher/testdata/patchmixed/patch.yaml exercises
// repeated document identities with ordinary merges and delete selectors.
func TestControlPlaneSchedulingPatch(t *testing.T) {
	ctl := os.Getenv("TALOSCTL")
	if ctl == "" {
		t.Skip("set TALOSCTL to a Talos 1.14 binary for real patch integration coverage")
	}
	version, err := exec.Command(ctl, "version", "--client").CombinedOutput()
	if err != nil || !strings.Contains(string(version), "v1.14.") {
		t.Fatalf("requires Talos 1.14: %s (%v)", version, err)
	}
	patch, err := filepath.Abs("../../omni/patches/1.14/libvirt/cp-schedulable.yaml")
	if err != nil {
		t.Fatal(err)
	}
	base := "apiVersion: v1alpha1\nkind: KubeNodeConfig\nlabels:\n  node-role.kubernetes.io/control-plane: \"\"\nannotations:\n  example.com/rack: rack1\nnodeIP:\n  validSubnets: [10.0.0.0/8]\n"
	for _, tc := range []struct{ name, taints string }{
		{"default-present", "taints:\n  node-role.kubernetes.io/control-plane: NoSchedule\n"},
		{"already-absent", ""},
		{"empty-map", "taints: {}\n"},
		{"preserve-other-with-default", "taints:\n  node-role.kubernetes.io/control-plane: NoSchedule\n  example.com/dedicated: infra:NoSchedule\n"},
		{"preserve-other-without-default", "taints:\n  example.com/dedicated: infra:NoSchedule\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			file := filepath.Join(t.TempDir(), "base.yaml")
			input := []byte(base + tc.taints)
			var first []byte
			for pass := 0; pass < 2; pass++ {
				if err := os.WriteFile(file, input, 0600); err != nil {
					t.Fatal(err)
				}
				out, err := exec.Command(ctl, "machineconfig", "patch", file, "--patch", "@"+patch).CombinedOutput()
				if err != nil {
					t.Fatalf("pass %d: %s (%v)", pass, out, err)
				}
				text := string(out)
				if strings.Count(text, "node-role.kubernetes.io/control-plane:") != 1 || strings.Contains(text, "$patch") {
					t.Fatalf("control-plane taint remains or label lost: %s", out)
				}
				for _, preserved := range []string{"example.com/rack: rack1", "10.0.0.0/8"} {
					if !strings.Contains(text, preserved) {
						t.Fatalf("lost %s: %s", preserved, out)
					}
				}
				if strings.Contains(tc.taints, "example.com/dedicated") != strings.Contains(text, "example.com/dedicated: infra:NoSchedule") {
					t.Fatalf("changed unrelated taint: %s", out)
				}
				if pass == 1 && !bytes.Equal(first, out) {
					t.Fatalf("patch is not idempotent:\n%s\n%s", first, out)
				}
				first, input = out, out
			}
		})
	}
}
