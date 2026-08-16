package installer

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestPlanIncludesHunkInGit(t *testing.T) {
	profile := DefaultProfile()
	tasks, _, err := Plan(profile, Environment{Commands: map[string]bool{"brew": true}})
	if err != nil {
		t.Fatal(err)
	}
	for _, task := range tasks {
		if task.ComponentID == "hunk" {
			t.Fatal("Hunk must not be a separate task")
		}
		if task.ComponentID == "git" && strings.Contains(task.Operation, "hunk") {
			return
		}
	}
	t.Fatal("Git task does not include Hunk")
}

func TestPlanSkipsXcodeInstallWhenToolsExist(t *testing.T) {
	profile := DefaultProfile()
	tasks, _, err := Plan(profile, Environment{Commands: map[string]bool{
		"brew":         true,
		"xcode-select": true,
	}})
	if err != nil {
		t.Fatal(err)
	}
	for _, task := range tasks {
		if task.Operation == "xcode-select --install" {
			t.Fatal("planned a non-idempotent Xcode install")
		}
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

func TestExecuteWithProgressReportsBeforeRunning(t *testing.T) {
	tasks := []Task{{ComponentID: "base", Label: "Base", Operation: "install"}}
	var progress []string
	results := ExecuteWithProgress(context.Background(), tasks, func(_ context.Context, command string) (string, error) {
		return command, nil
	}, func(task Task) {
		progress = append(progress, task.Label)
	})
	if len(progress) != 1 || progress[0] != "Base" {
		t.Fatalf("unexpected progress: %#v", progress)
	}
	if results[0].Status != "installed" {
		t.Fatalf("unexpected results: %#v", results)
	}
}
