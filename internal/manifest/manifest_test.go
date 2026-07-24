package manifest

import (
	"os"
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
