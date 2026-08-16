package main

import (
	"testing"

	"dotfiles/internal/installer"
)

func TestSummarizeResultsByComponent(t *testing.T) {
	results := summarize([]installer.Result{
		{Task: installer.Task{ComponentID: "shell", Label: "Shell"}, Status: "installed"},
		{Task: installer.Task{ComponentID: "shell", Label: "Shell"}, Status: "installed"},
		{Task: installer.Task{ComponentID: "git", Label: "Git"}, Status: "installed"},
		{Task: installer.Task{ComponentID: "git", Label: "Git"}, Status: "failed", Output: "command failed"},
	})

	if len(results) != 2 {
		t.Fatalf("got %d component results, want 2", len(results))
	}
	if results[0].Status != "installed" {
		t.Fatalf("shell status = %q, want installed", results[0].Status)
	}
	if results[1].Status != "failed" || results[1].Output != "command failed" {
		t.Fatalf("git result = %#v", results[1])
	}
}
