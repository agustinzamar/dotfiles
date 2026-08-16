package installer

import (
	"strings"
	"testing"
)

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
	for _, id := range []string{"communication", "media", "desktop"} {
		if seen[id] {
			t.Fatalf("aggregate component %q still exists", id)
		}
	}
	for _, id := range []string{"communication-discord", "communication-slack", "media-spotify", "media-vlc", "desktop-chrome"} {
		if !seen[id] {
			t.Fatalf("missing individual component %q", id)
		}
	}
	for _, component := range Components() {
		if component.ID == "base" && !component.Required {
			t.Fatal("base must be required")
		}
		if component.ID == "git" {
			if !contains(component.Links, "hunk") || !strings.Contains(component.Commands[0], "hunk") {
				t.Fatal("Git must include Hunk")
			}
		}
	}
	if seen["hunk"] || seen["laravel"] || seen["phpstorm"] {
		t.Fatal("Git and PHP tooling must use combined components")
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

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
