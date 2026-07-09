package omnitui

import "testing"

func TestVersionString(t *testing.T) {
	if got := VersionString("1.2.3"); got != "omni-on-unraid 1.2.3" {
		t.Fatalf("VersionString() = %q", got)
	}
}
