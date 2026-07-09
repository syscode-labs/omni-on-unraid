package omnitui

import (
	"path/filepath"
	"testing"
)

func TestDefaultActionsExposeMemorableMakeTargets(t *testing.T) {
	actions := DefaultActions()
	targets := make([]string, 0, len(actions))
	for _, action := range actions {
		targets = append(targets, action.Target)
	}

	want := []string{
		"provider",
		"provider-status",
		"mc",
		"cluster",
		"status",
		"lab",
		"provider-logs",
		"provider-down",
		"deploy-remote",
	}
	if len(targets) != len(want) {
		t.Fatalf("targets length = %d, want %d: %v", len(targets), len(want), targets)
	}
	for i := range want {
		if targets[i] != want[i] {
			t.Fatalf("targets[%d] = %q, want %q; all targets: %v", i, targets[i], want[i], targets)
		}
	}
}

func TestModelSelectionWrapsAround(t *testing.T) {
	model := NewModel([]Action{
		{Target: "one"},
		{Target: "two"},
		{Target: "three"},
	})

	model.MoveUp()
	if got := model.CurrentAction().Target; got != "three" {
		t.Fatalf("after moving up from first, target = %q, want three", got)
	}

	model.MoveDown()
	if got := model.CurrentAction().Target; got != "one" {
		t.Fatalf("after moving down from last, target = %q, want one", got)
	}
}

func TestModelBuildsMakeCommandForCurrentAction(t *testing.T) {
	model := NewModel([]Action{{Target: "mc"}})

	cmd := model.CommandForCurrentAction()

	if filepath.Base(cmd.Path) != "make" {
		t.Fatalf("command path = %q, want make", cmd.Path)
	}
	if len(cmd.Args) != 2 || cmd.Args[1] != "mc" {
		t.Fatalf("command args = %v, want [make mc]", cmd.Args)
	}
}
