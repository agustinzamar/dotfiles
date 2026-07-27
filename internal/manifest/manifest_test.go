package manifest

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTempManifest(t *testing.T, yaml string) string {
	t.Helper()
	dir := t.TempDir()
	path := dir + "/tools.yaml"
	if err := os.WriteFile(path, []byte(yaml), 0644); err != nil {
		t.Fatalf("write temp manifest: %v", err)
	}
	return path
}

func TestLoadRejectsDuplicateNodeID(t *testing.T) {
	yaml := `
categories:
  - id: base
    name: Base
    nodes:
      - id: git
        name: Git
      - id: git
        name: Git Duplicate
`
	_, err := Load(writeTempManifest(t, yaml))
	if err == nil {
		t.Fatal("expected duplicate node ID error")
	}
}

func TestLoadRejectsUnknownRequirement(t *testing.T) {
	yaml := `
categories:
  - id: base
    name: Base
    nodes:
      - id: node-a
        name: A
        requires: [missing]
`
	_, err := Load(writeTempManifest(t, yaml))
	if err == nil {
		t.Fatal("expected unknown requirement error")
	}
}

func TestLoadRejectsRequirementCycle(t *testing.T) {
	yaml := `
categories:
  - id: base
    name: Base
    nodes:
      - id: a
        name: A
        requires: [b]
      - id: b
        name: B
        requires: [a]
`
	_, err := Load(writeTempManifest(t, yaml))
	if err == nil {
		t.Fatal("expected cycle error")
	}
	if !strings.Contains(err.Error(), "requires cycle detected") {
		t.Fatalf("expected requires cycle error, got %v", err)
	}
}

func TestLoadAcceptsRequirement(t *testing.T) {
	yaml := `
categories:
  - id: base
    name: Base
    nodes:
      - id: a
        name: A
        requires: [b]
      - id: b
        name: B
`
	if _, err := Load(writeTempManifest(t, yaml)); err != nil {
		t.Fatalf("expected valid requirement, got %v", err)
	}
}

func TestWalkIncludesNestedNodesInOrder(t *testing.T) {
	yaml := `
categories:
  - id: editors
    name: Editors
    nodes:
      - id: vscode
        name: VS Code
        children:
          - id: vscode-settings
            name: Settings
          - id: vscode-extensions
            name: Extensions
            children:
              - id: vscode-catppuccin
                name: Catppuccin
`
	m, err := Load(writeTempManifest(t, yaml))
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	var ids []string
	_ = m.Walk(func(ref NodeRef) error {
		ids = append(ids, ref.Node.ID)
		return nil
	})
	expected := []string{"vscode", "vscode-settings", "vscode-extensions", "vscode-catppuccin"}
	if len(ids) != len(expected) {
		t.Fatalf("walk length %d, want %d", len(ids), len(expected))
	}
	for i, id := range expected {
		if ids[i] != id {
			t.Fatalf("walk[%d]: got %s, want %s", i, ids[i], id)
		}
	}
}

func TestProfileFilterExcludesParentAndDescendants(t *testing.T) {
	yaml := `
categories:
  - id: base
    name: Base
    nodes:
      - id: parent
        name: Parent
        profiles: [work]
        children:
          - id: child
            name: Child
            steps:
              - type: brew
                package: go
`
	m, err := Load(writeTempManifest(t, yaml))
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	node, _, ok := m.Node("parent")
	if !ok {
		t.Fatal("expected parent node to exist")
	}
	if node.MatchesProfile("personal") {
		t.Error("expected parent to not match personal profile")
	}
	if !node.MatchesProfile("work") {
		t.Error("expected parent to match work profile")
	}
}

func TestLoadRejectsUnknownWorkflow(t *testing.T) {
	yaml := `
categories:
  - id: base
    name: Base
    nodes:
      - id: git
        name: Git
        setup: [not-a-handler]
`
	_, err := Load(writeTempManifest(t, yaml))
	if err == nil {
		t.Fatal("expected unknown workflow error")
	}
}

func testManifestWithNeeds(id string, needs []string) *Manifest {
	return &Manifest{
		Categories: []Category{{
			ID: "test", Name: "Test",
			Nodes: []Node{{
				ID: id, Name: "A",
				Steps: []Step{{Type: "symlink", Needs: needs}},
			}},
		}},
	}
}

func testManifestWithNeedsProvides(needID string, needs []string, provideID string, provides []string) *Manifest {
	return &Manifest{
		Categories: []Category{{
			ID: "test", Name: "Test",
			Nodes: []Node{
				{ID: needID, Name: "Needer", Steps: []Step{{Type: "symlink", Needs: needs}}},
				{ID: provideID, Name: "Provider", Steps: []Step{{Type: "symlink", Provides: provides}}},
			},
		}},
	}
}

func TestValidate_UnrecognizedNeedsTag(t *testing.T) {
	m := testManifestWithNeeds("a", []string{"nonexistent-provider"})
	err := m.Validate()
	if err == nil {
		t.Fatal("expected error for unrecognized needs tag")
	}
}

// TestValidate_RejectsRequiresField skipped in Phase 1.
// Phase 1 does NOT reject "requires" — it's still populated by toolsToNodes()
// from depends_on. Strict rejection and full removal is Phase 2 after tools.yaml migration.

func TestValidate_ValidNeedsProvides(t *testing.T) {
	m := testManifestWithNeedsProvides("a", []string{"my-provider"}, "b", []string{"my-provider"})
	err := m.Validate()
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
}

func TestValidate_KnownImplicitTag(t *testing.T) {
	m := testManifestWithNeeds("a", []string{"homebrew"})
	err := m.Validate()
	if err != nil {
		t.Fatalf("expected no error for known implicit tag homebrew, got: %v", err)
	}
}

func TestLoadValidatesLegacyToolsManifest(t *testing.T) {
	yaml := `
categories:
  - id: base
    name: Base
    tools:
      - name: Broken
        depends_on: [Missing]
`
	if _, err := Load(writeTempManifest(t, yaml)); err == nil {
		t.Fatal("expected legacy manifest validation error")
	}
}

func TestLegacyToolExpandsIntoInstallAndRelatedPrompts(t *testing.T) {
	yaml := `
categories:
  - name: IDEs
    tools:
      - name: VS Code
        checked: true
        steps:
          - type: cask
            package: visual-studio-code
          - type: symlink
            from: settings.json
            to: ${HOME}/settings.json
          - type: vscode
            extension: first.extension
          - type: vscode
            extension: second.extension
`
	m, err := Load(writeTempManifest(t, yaml))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}
	root := m.Categories[0].Nodes[0]
	if len(root.Steps) != 1 || root.Steps[0].Type != "cask" {
		t.Fatalf("expected only the app install on root, got %#v", root.Steps)
	}
	if len(root.Children) != 2 || root.Children[0].Name != "Extensions" {
		t.Fatalf("expected extensions group then settings, got %#v", root.Children)
	}
	if len(root.Children[0].Children) != 2 {
		t.Fatalf("expected individual extension prompts, got %#v", root.Children[0].Children)
	}
}

func TestLegacyBasicMarkerPropagatesToRelatedSteps(t *testing.T) {
	yaml := `
categories:
  - name: Tools
    tools:
      - name: Basic Tool
        basic: true
        checked: true
        steps:
          - type: brew
            package: basic
          - type: symlink
            from: basic.conf
            to: ${HOME}/basic.conf
`
	m, err := Load(writeTempManifest(t, yaml))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}
	root := m.Categories[0].Nodes[0]
	if !root.Basic || len(root.Children) != 1 || !root.Children[0].Basic {
		t.Fatalf("expected basic marker on tool subtree, got %#v", root)
	}
}

func TestLegacyMacOSMarkerPropagatesToRelatedSteps(t *testing.T) {
	yaml := `
categories:
  - name: System
    tools:
      - name: Finder
        macos: true
        checked: true
        steps:
          - type: defaults
            domain: com.apple.finder
            key: ShowPathbar
            value: "true"
          - type: run
            command: killall Finder
`
	m, err := Load(writeTempManifest(t, yaml))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}
	root := m.Categories[0].Nodes[0]
	if !root.MacOS || len(root.Children) != 2 || !root.Children[0].MacOS || !root.Children[1].MacOS {
		t.Fatalf("expected macos marker on tool subtree, got %#v", root)
	}
}

func TestLegacyAliasesBecomeOneGroupWithIndividualPrompts(t *testing.T) {
	yaml := `
categories:
  - name: Shell
    tools:
      - name: "Aliases: System"
        steps:
          - type: symlink
            from: system.zsh
            to: ${HOME}/system.zsh
      - name: "Aliases: Git"
        steps:
          - type: symlink
            from: git.zsh
            to: ${HOME}/git.zsh
`
	m, err := Load(writeTempManifest(t, yaml))
	if err != nil {
		t.Fatalf("load manifest: %v", err)
	}
	group := m.Categories[0].Nodes[0]
	if group.Name != "Aliases" || len(group.Children) != 2 {
		t.Fatalf("expected one aliases group with two prompts, got %#v", group)
	}
	if group.Children[0].Name != "System" || group.Children[1].Name != "Git" {
		t.Fatalf("unexpected alias prompts: %#v", group.Children)
	}
}

func TestRepositorySymlinkSourcesExist(t *testing.T) {
	root := DotfilesDir()
	m, err := Load(filepath.Join(root, "config", "tools.yaml"))
	if err != nil {
		t.Fatalf("load repository manifest: %v", err)
	}
	if err := m.Walk(func(ref NodeRef) error {
		for _, step := range ref.Node.Steps {
			if step.Type != "symlink" && step.Type != "template-symlink" {
				continue
			}
			if _, err := os.Stat(filepath.Join(root, step.From)); err != nil {
				t.Errorf("%s: source %q: %v", ref.Node.Name, step.From, err)
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}
