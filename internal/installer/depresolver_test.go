package installer

import (
	"testing"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

func TestDepResolver_ProvidesIndex(t *testing.T) {
	items := []*Item{
		{ID: "brew", Node: nodeRefForStep("brew", "curl")},
		{ID: "cask", Node: nodeRefForStep("cask", "app")},
		{ID: "other", Node: nodeRefForStep("symlink", "")},
	}
	dr := NewDepResolver(items, nil)
	homebrewProviders := dr.providersFor("homebrew")
	if len(homebrewProviders) != 2 {
		t.Fatalf("expected 2 homebrew providers, got %d", len(homebrewProviders))
	}
	if homebrewProviders[0].ID != "brew" {
		t.Fatalf("expected first provider to be brew, got %s", homebrewProviders[0].ID)
	}
}

func TestDepResolver_NeedsOf_Implicit(t *testing.T) {
	items := []*Item{
		{ID: "cask1", Node: nodeRefForStep("cask", "app")},
		{ID: "tap1", Node: nodeRefForStep("tap", "repo")},
		{ID: "sym1", Node: nodeRefForStep("symlink", "")},
	}
	dr := NewDepResolver(items, nil)
	caskNeeds := dr.needsOf(items[0])
	if len(caskNeeds) != 1 || caskNeeds[0] != "homebrew" {
		t.Fatalf("cask should need homebrew, got %v", caskNeeds)
	}
	tapNeeds := dr.needsOf(items[1])
	if len(tapNeeds) != 1 || tapNeeds[0] != "homebrew" {
		t.Fatalf("tap should need homebrew, got %v", tapNeeds)
	}
	symNeeds := dr.needsOf(items[2])
	if len(symNeeds) != 0 {
		t.Fatalf("symlink should have no implicit needs, got %v", symNeeds)
	}
}

func TestDepResolver_NeedsOf_ExplicitPlusImplicit(t *testing.T) {
	items := []*Item{
		{ID: "a", Node: nodeRefForStep("cask", "app")},
	}
	items[0].Node.Node.Steps[0].Needs = []string{"vscode"}
	dr := NewDepResolver(items, nil)
	needs := dr.needsOf(items[0])
	if len(needs) != 2 {
		t.Fatalf("expected 2 needs (vscode + homebrew), got %v", needs)
	}
}

func TestDepResolver_NeededBy(t *testing.T) {
	items := []*Item{
		{ID: "a", Node: nodeRefForStep("cask", "app")},
		{ID: "b", Node: nodeRefForStep("symlink", "")},
	}
	items[1].Node.Node.Steps[0].Needs = []string{"homebrew"}
	dr := NewDepResolver(items, nil)
	// a provides homebrew (implicit cask), b needs it
	neededByA := dr.neededBy[items[0]]
	if len(neededByA) != 1 || neededByA[0].ID != "b" {
		t.Fatalf("a (homebrew provider) should be needed by b, got %v", neededByA)
	}
}

func TestDepResolver_Satisfied(t *testing.T) {
	satisfied := false
	dr := NewDepResolver([]*Item{
		{ID: "brew", Node: nodeRefForStep("brew", "curl")},
	}, func(tag string, item *Item) bool {
		return tag == "homebrew"
	})
	if !dr.satisfied(dr.providersFor("homebrew")[0]) {
		t.Fatal("expected satisfied to return true")
	}
	_ = satisfied
}

func TestDepResolver_SatisfiedFalse(t *testing.T) {
	dr := NewDepResolver([]*Item{
		{ID: "brew", Node: nodeRefForStep("brew", "curl")},
	}, func(tag string, item *Item) bool {
		return false
	})
	if dr.satisfied(dr.providersFor("homebrew")[0]) {
		t.Fatal("expected satisfied to return false")
	}
}

// Test helpers
func nodeRefForStep(stepType, pkg string) manifest.NodeRef {
	return manifest.NodeRef{
		Node: &manifest.Node{
			ID:   stepType + "_node",
			Name: stepType + " Node",
			Steps: []manifest.Step{
				{Type: stepType, Package: pkg},
			},
		},
		CategoryID: "test",
		Category:   "Test",
	}
}
