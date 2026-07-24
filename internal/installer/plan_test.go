package installer

import (
	"testing"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

func testManifest() *manifest.Manifest {
	return &manifest.Manifest{
		Categories: []manifest.Category{
			{
				ID:   "base",
				Name: "Base",
				Nodes: []manifest.Node{
					{
						ID:       "git",
						Name:     "Git",
						Default:  true,
						Steps:    []manifest.Step{{Type: "run", Command: "git --version"}},
						Children: []manifest.Node{
							{ID: "git-identity", Name: "Identity", Setup: []string{"git-identity"}},
							{ID: "signed-commits", Name: "Signed Commits", Setup: []string{"signed-commits"}},
						},
					},
					{
						ID:       "vscode",
						Name:     "VS Code",
						Children: []manifest.Node{
							{ID: "vscode-settings", Name: "Settings", Steps: []manifest.Step{{Type: "symlink", From: "vscode/settings.json", To: "~/Library/Application Support/Code/User/settings.json"}}},
							{ID: "vscode-extensions", Name: "Extensions", Children: []manifest.Node{
								{ID: "vscode-catppuccin", Name: "Catppuccin", Default: true, Steps: []manifest.Step{{Type: "vscode", Extension: "catppuccin.catppuccin-vsc"}}},
							}},
						},
					},
					{
						ID:       "hunk",
						Name:     "Hunk",
						Default:  true,
						Setup:    []string{"hunk-git-pager"},
						Children: []manifest.Node{
							{ID: "hunk-pager", Name: "Git Pager", Steps: []manifest.Step{{Type: "run", Command: "git config --global core.pager hunk"}}},
						},
					},
				},
			},
		},
	}
}

func TestPlannerAsksCategoryThenEveryLeaf(t *testing.T) {
	m := testManifest()
	p := NewPlanner(m, "")

	var order []string
	for {
		item := p.Next()
		if item == nil {
			break
		}
		order = append(order, item.ID)
		p.Answer(item.ID, DecisionYes)
	}
	expected := []string{"git", "git-identity", "signed-commits", "vscode", "vscode-settings", "vscode-extensions", "vscode-catppuccin", "hunk", "hunk-pager"}
	if len(order) != len(expected) {
		t.Fatalf("got %d prompts, want %d", len(order), len(expected))
	}
	for i, id := range expected {
		if order[i] != id {
			t.Fatalf("prompt[%d]: got %s, want %s", i, order[i], id)
		}
	}
}

func TestPlannerDeclinedRequirementSkipsDependent(t *testing.T) {
	m := &manifest.Manifest{
		Categories: []manifest.Category{
			{
				ID:   "base",
				Name: "Base",
				Nodes: []manifest.Node{
					{
						ID:       "git",
						Name:     "Git",
						Children: []manifest.Node{
							{ID: "git-identity", Name: "Identity", Setup: []string{"git-identity"}, Requires: []string{"git"}},
						},
					},
				},
			},
		},
	}
	p := NewPlanner(m, "")

	var order []string
	for {
		item := p.Next()
		if item == nil {
			break
		}
		order = append(order, item.ID)
		if item.ID == "git" {
			p.Answer(item.ID, DecisionNo)
		} else {
			p.Answer(item.ID, DecisionYes)
		}
	}
	if len(order) != 1 || order[0] != "git" {
		t.Fatalf("expected only git prompt, got %v", order)
	}
	identity, ok := p.byID["git-identity"]
	if !ok {
		t.Fatal("expected git-identity item")
	}
	if identity.Status != StatusSkippedDependency {
		t.Fatalf("expected skipped-dependency, got %s", identity.Status)
	}
}

func TestPlannerGroupShortcutStillVisitsEachChild(t *testing.T) {
	m := &manifest.Manifest{
		Categories: []manifest.Category{
			{
				ID:   "editors",
				Name: "Editors",
				Nodes: []manifest.Node{
					{
						ID:       "vscode",
						Name:     "VS Code",
						Children: []manifest.Node{
							{ID: "vscode-settings", Name: "Settings", Steps: []manifest.Step{{Type: "symlink", From: "vscode/settings.json", To: "settings.json"}}},
							{ID: "vscode-extensions", Name: "Extensions", Children: []manifest.Node{
								{ID: "vscode-catppuccin", Name: "Catppuccin", Default: true, Steps: []manifest.Step{{Type: "vscode", Extension: "catppuccin.catppuccin-vsc"}}},
							}},
						},
					},
				},
			},
		},
	}
	p := NewPlanner(m, "")

	item := p.Next()
	if item == nil || item.ID != "vscode" {
		t.Fatalf("expected vscode first, got %v", item)
	}
	p.Answer(item.ID, DecisionYes)

	item = p.Next()
	if item == nil || item.ID != "vscode-settings" {
		t.Fatalf("expected vscode-settings next, got %v", item)
	}
	p.Answer(item.ID, DecisionYes)

	item = p.Next()
	if item == nil || item.ID != "vscode-extensions" {
		t.Fatalf("expected vscode-extensions next, got %v", item)
	}
	p.Answer(item.ID, DecisionYes)

	item = p.Next()
	if item == nil || item.ID != "vscode-catppuccin" {
		t.Fatalf("expected vscode-catppuccin next, got %v", item)
	}
}

func TestPlannerBackCannotUndoExecutedItem(t *testing.T) {
	m := testManifest()
	p := NewPlanner(m, "")

	item := p.Next()
	if item == nil {
		t.Fatal("expected item")
	}
	p.Answer(item.ID, DecisionYes)
	item.Status = StatusInstalled

	back := p.Back()
	if back != nil {
		t.Fatalf("expected nil back for executed item, got %v", back)
	}
}

func TestPlannerFiltersProfileBeforePrompting(t *testing.T) {
	m := &manifest.Manifest{
		Categories: []manifest.Category{
			{
				ID:   "base",
				Name: "Base",
				Nodes: []manifest.Node{
					{ID: "always", Name: "Always", Profiles: []string{}, Steps: []manifest.Step{{Type: "run", Command: "echo always"}}},
				},
			},
			{
				ID:   "work",
				Name: "Work",
				Nodes: []manifest.Node{
					{ID: "work-tool", Name: "Work Tool", Profiles: []string{"work"}, Steps: []manifest.Step{{Type: "run", Command: "echo work"}}},
				},
			},
		},
	}
	p := NewPlanner(m, "personal")

	count := 0
	for {
		item := p.Next()
		if item == nil {
			break
		}
		count++
		p.Answer(item.ID, DecisionYes)
	}
	if count != 1 {
		t.Fatalf("expected 1 prompt for personal profile, got %d", count)
	}
}
