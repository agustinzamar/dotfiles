package installer

import "testing"

func TestManifestHasStableBaselineAndIndependentOptions(t *testing.T) {
	seen := map[string]bool{}
	for _, component := range Components() {
		if seen[component.ID] {
			t.Fatalf("duplicate component %q", component.ID)
		}
		seen[component.ID] = true
	}
	for _, id := range []string{"base", "shell", "git", "terminal"} {
		if !seen[id] {
			t.Fatalf("missing baseline %q", id)
		}
	}
	for _, component := range Components() {
		if component.ID == "base" && !component.Required {
			t.Fatal("base must be required")
		}
		if component.ID == "hunk" && (component.Category != "Git" || len(component.Links) == 0) {
			t.Fatal("hunk must be a Git component with a link")
		}
	}
	if seen["laravel"] || seen["phpstorm"] {
		t.Fatal("PHP tooling must be one component")
	}
	for _, component := range Components() {
		if component.ID != "php" {
			continue
		}
		for _, command := range component.Commands {
			if command == "brew install php" || command == "brew install php composer" {
				t.Fatal("PHP must be installed through Herd")
			}
		}
	}
}
