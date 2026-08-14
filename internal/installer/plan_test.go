package installer

import (
	"context"
	"errors"
	"testing"
)

func TestPlanOrdersDependencies(t *testing.T) {
	profile := DefaultProfile()
	profile.Components["hunk"] = true
	tasks, _, err := Plan(profile, Environment{Commands: map[string]bool{"brew": true}})
	if err != nil {
		t.Fatal(err)
	}
	git, hunk := -1, -1
	for i, task := range tasks {
		if task.ComponentID == "git" && git == -1 {
			git = i
		}
		if task.ComponentID == "hunk" && hunk == -1 {
			hunk = i
		}
	}
	if git == -1 || hunk == -1 || git > hunk {
		t.Fatalf("dependency order is wrong: git=%d hunk=%d", git, hunk)
	}
}

func TestExecuteContinuesAndSkipsDependents(t *testing.T) {
	tasks := []Task{{ComponentID: "git", Operation: "fail"}, {ComponentID: "hunk", Operation: "later", Dependencies: []string{"git"}}, {ComponentID: "media", Operation: "independent"}}
	results := Execute(context.Background(), tasks, func(_ context.Context, command string) (string, error) {
		if command == "fail" {
			return "bad", errors.New("failed")
		}
		return command, nil
	})
	if results[1].Status != "skipped" || results[2].Status != "installed" {
		t.Fatalf("unexpected results: %#v", results)
	}
}
