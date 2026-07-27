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
						ID:      "git",
						Name:    "Git",
						Default: true,
						Steps:   []manifest.Step{{Type: "run", Command: "git --version"}},
						Children: []manifest.Node{
							{ID: "git-identity", Name: "Identity", Setup: []string{"git-identity"}},
							{ID: "signed-commits", Name: "Signed Commits", Setup: []string{"signed-commits"}},
						},
					},
					{
						ID:   "vscode",
						Name: "VS Code",
						Children: []manifest.Node{
							{ID: "vscode-settings", Name: "Settings", Steps: []manifest.Step{{Type: "symlink", From: "vscode/settings.json", To: "~/Library/Application Support/Code/User/settings.json"}}},
							{ID: "vscode-extensions", Name: "Extensions", Children: []manifest.Node{
								{ID: "vscode-catppuccin", Name: "Catppuccin", Default: true, Steps: []manifest.Step{{Type: "vscode", Extension: "catppuccin.catppuccin-vsc"}}},
							}},
						},
					},
					{
						ID:      "hunk",
						Name:    "Hunk",
						Default: true,
						Setup:   []string{"hunk-git-pager"},
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
	expected := []string{"category:base", "git", "git-identity", "signed-commits", "vscode", "vscode-settings", "vscode-extensions", "vscode-catppuccin", "hunk", "hunk-pager"}
	if len(order) != len(expected) {
		t.Fatalf("got %d prompts, want %d", len(order), len(expected))
	}
	for i, id := range expected {
		if order[i] != id {
			t.Fatalf("prompt[%d]: got %s, want %s", i, order[i], id)
		}
	}
}

func TestPlannerCategoriesDefaultToYes(t *testing.T) {
	p := NewPlanner(testManifest(), "")
	item := p.Next()
	if item == nil || item.Decision != DecisionYes {
		t.Fatalf("expected category to default to yes, got %#v", item)
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
						ID:   "git",
						Name: "Git",
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
	if len(order) != 2 || order[0] != "category:base" || order[1] != "git" {
		t.Fatalf("expected category and git prompts, got %v", order)
	}
	identity, ok := p.byID["git-identity"]
	if !ok {
		t.Fatal("expected git-identity item")
	}
	if identity.Status != StatusSkippedDependency {
		t.Fatalf("expected skipped-dependency, got %s", identity.Status)
	}
}

func TestPlannerDefersDependentUntilProviderCompletes(t *testing.T) {
	m := &manifest.Manifest{Categories: []manifest.Category{{
		ID: "tools", Name: "Tools", Nodes: []manifest.Node{
			{ID: "editor-alias", Name: "Editor alias", Requires: []string{"phpstorm"}, Steps: []manifest.Step{{Type: "symlink"}}},
			{ID: "shell-tool", Name: "Shell tool", Steps: []manifest.Step{{Type: "run"}}},
			{ID: "phpstorm", Name: "PhpStorm", Steps: []manifest.Step{{Type: "cask"}}},
			{ID: "other", Name: "Other", Steps: []manifest.Step{{Type: "run"}}},
		},
	}}}
	p := NewPlanner(m, "")

	category := p.Next()
	p.Answer(category.ID, DecisionYes)
	if item := p.Next(); item == nil || item.ID != "shell-tool" {
		t.Fatalf("expected unrelated shell tool while alias is blocked, got %#v", item)
	}
	p.Answer("shell-tool", DecisionYes)
	p.byID["shell-tool"].Status = StatusInstalled

	editor := p.Next()
	if editor == nil || editor.ID != "phpstorm" {
		t.Fatalf("expected PhpStorm before its alias, got %#v", editor)
	}
	p.Answer(editor.ID, DecisionYes)
	editor.Status = StatusInstalled
	p.ItemCompleted(editor.ID)

	if item := p.Next(); item == nil || item.ID != "editor-alias" {
		t.Fatalf("expected editor alias immediately after PhpStorm, got %#v", item)
	}
}

func TestPlannerDoesNotPromoteDependentBeforeItsCategory(t *testing.T) {
	m := &manifest.Manifest{Categories: []manifest.Category{
		{ID: "base", Name: "Base", Nodes: []manifest.Node{
			{ID: "git", Name: "Git", Steps: []manifest.Step{{Type: "run"}}},
			{ID: "homebrew", Name: "Homebrew", Steps: []manifest.Step{{Type: "run"}}},
		}},
		{ID: "dev", Name: "Dev", Nodes: []manifest.Node{
			{ID: "git-config", Name: "Git Config", Requires: []string{"git"}, Steps: []manifest.Step{{Type: "run"}}},
		}},
	}}
	p := NewPlanner(m, "")
	base := p.Next()
	p.Answer(base.ID, DecisionYes)
	git := p.Next()
	p.Answer(git.ID, DecisionYes)
	git.Status = StatusInstalled
	p.ItemCompleted(git.ID)

	if item := p.Next(); item == nil || item.ID != "homebrew" {
		t.Fatalf("expected remaining Base tool before unopened Dev category, got %#v", item)
	}
}

func TestPlannerCanRetryOrSkipFailedItem(t *testing.T) {
	p := NewPlanner(testManifest(), "")
	_ = p.Next()
	p.Answer("category:base", DecisionYes)
	item := p.Next()
	p.Answer(item.ID, DecisionYes)
	item.Status = StatusFailed

	if !p.Retry(item.ID) || item.Status != StatusPlanned {
		t.Fatalf("retry did not reset failed item: %#v", item)
	}
	item.Status = StatusFailed
	if !p.SkipFailed(item.ID) || item.Status != StatusDeclined {
		t.Fatalf("skip did not decline failed item: %#v", item)
	}
}

func TestPlannerDeclinedCategorySkipsItsTools(t *testing.T) {
	m := &manifest.Manifest{Categories: []manifest.Category{
		{ID: "ides", Name: "IDEs", Nodes: []manifest.Node{
			{ID: "vscode", Name: "VS Code"},
			{ID: "phpstorm", Name: "PhpStorm"},
		}},
		{ID: "apps", Name: "Apps", Nodes: []manifest.Node{
			{ID: "chatgpt", Name: "ChatGPT"},
		}},
	}}
	p := NewPlanner(m, "")

	item := p.Next()
	if item == nil || item.ID != "category:ides" {
		t.Fatalf("expected IDE category, got %#v", item)
	}
	p.Answer(item.ID, DecisionNo)
	item = p.Next()
	if item == nil || item.ID != "category:apps" {
		t.Fatalf("expected Apps category after declining IDEs, got %#v", item)
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
						ID:   "vscode",
						Name: "VS Code",
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
	if item == nil || item.ID != "category:editors" {
		t.Fatalf("expected editors category first, got %v", item)
	}
	p.Answer(item.ID, DecisionYes)

	item = p.Next()
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
	p.Answer(item.ID, DecisionYes)
	item = p.Next()
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
	if count != 2 {
		t.Fatalf("expected base category and its tool for personal profile, got %d prompts", count)
	}
}

func TestBasicPlannerIncludesMarkedSubtreesOnly(t *testing.T) {
	m := &manifest.Manifest{Categories: []manifest.Category{{
		ID: "tools", Name: "Tools", Nodes: []manifest.Node{
			{ID: "basic", Name: "Basic", Basic: true, Steps: []manifest.Step{{Type: "run"}}, Children: []manifest.Node{
				{ID: "basic-config", Name: "Config", Steps: []manifest.Step{{Type: "symlink"}}},
			}},
			{ID: "group", Name: "Group", Children: []manifest.Node{
				{ID: "selected", Name: "Selected", Basic: true, Steps: []manifest.Step{{Type: "run"}}},
				{ID: "omitted-child", Name: "Omitted Child", Steps: []manifest.Step{{Type: "run"}}},
			}},
			{ID: "omitted", Name: "Omitted", Steps: []manifest.Step{{Type: "run"}}},
		},
	}}}
	p := NewBasicPlanner(m, "")

	var got []string
	for item := p.Next(); item != nil; item = p.Next() {
		got = append(got, item.ID)
		p.Answer(item.ID, DecisionYes)
	}
	want := []string{"category:tools", "basic", "basic-config", "group", "selected"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("prompt[%d]: got %s, want %s", i, got[i], want[i])
		}
	}
}

func TestMacOSPlannerIncludesMacOSNodesOnly(t *testing.T) {
	m := &manifest.Manifest{Categories: []manifest.Category{
		{ID: "system", Name: "System", Nodes: []manifest.Node{
			{ID: "finder", Name: "Finder", MacOS: true, Steps: []manifest.Step{{Type: "defaults"}}},
			{ID: "other", Name: "Other", Steps: []manifest.Step{{Type: "run"}}},
		}},
		{ID: "apps", Name: "Apps", Nodes: []manifest.Node{
			{ID: "app", Name: "App", Steps: []manifest.Step{{Type: "cask"}}},
		}},
	}}
	p := NewMacOSPlanner(m, "")

	var got []string
	for item := p.Next(); item != nil; item = p.Next() {
		got = append(got, item.ID)
		p.Answer(item.ID, DecisionYes)
	}
	want := []string{"category:system", "finder"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("prompt[%d]: got %s, want %s", i, got[i], want[i])
		}
	}
}
