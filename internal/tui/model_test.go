package tui

import (
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/installer"
	"github.com/agustinzamar/dotfiles/internal/manifest"
)

func TestNewModelBuilds(t *testing.T) {
	m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
	if err != nil {
		t.Fatalf("Load manifest: %v", err)
	}
	model := NewSelectModel(m, "", true)
	if model == nil {
		t.Fatal("NewSelectModel returned nil")
	}
	_ = model.(tea.Model)
}

func TestSelectModelPreservesDryRun(t *testing.T) {
	m := &manifest.Manifest{}
	model := NewSelectModel(m, "", true).(*model)
	if !model.dryRun {
		t.Fatal("expected select model dry-run mode")
	}
}

// --- test helpers ---

func guidedTestSession(t *testing.T, nodes []manifest.Node, results []executor.Result) *installer.Session {
	t.Helper()
	m := &manifest.Manifest{
		Categories: []manifest.Category{
			{ID: "test", Name: "Test", Nodes: nodes},
		},
	}
	p := installer.NewPlanner(m, "")
	runner := &guidedFakeRunner{results: results}
	return installer.NewSession(p, runner, "/tmp", nil, true, "")
}

type guidedFakeRunner struct {
	results []executor.Result
	idx     int
}

func (f *guidedFakeRunner) Run(step manifest.Step, dotfilesDir string, vars map[string]string, dryRun bool) executor.Result {
	if f.idx >= len(f.results) {
		return executor.Result{Status: "installed"}
	}
	r := f.results[f.idx]
	f.idx++
	return r
}

// TestGuidedModelShowsCategoryBeforeTool
func TestGuidedModelShowsCategoryBeforeTool(t *testing.T) {
	nodes := []manifest.Node{
		{ID: "homebrew", Name: "Homebrew", Steps: []manifest.Step{{Type: "run", Command: "echo hi"}}},
	}
	s := guidedTestSession(t, nodes, nil)
	m := NewGuidedModel(s, "").(*guidedModel)
	m.Init()

	if m.state != stateGuidePrompt {
		t.Fatalf("expected stateGuidePrompt, got %v", m.state)
	}
	if m.item == nil {
		t.Fatal("expected current item, got nil")
	}
	if m.item.ID != "homebrew" {
		t.Fatalf("expected homebrew item, got %s", m.item.ID)
	}
}

// TestGuidedModelPromptsEveryExtensionAfterGroupAccept
func TestGuidedModelPromptsEveryExtensionAfterGroupAccept(t *testing.T) {
	nodes := []manifest.Node{
		{
			ID:   "vscode",
			Name: "VSCode",
			Children: []manifest.Node{
				{ID: "vscode-ext1", Name: "Extension 1", Steps: []manifest.Step{{Type: "run"}}},
				{ID: "vscode-ext2", Name: "Extension 2", Steps: []manifest.Step{{Type: "run"}}},
			},
		},
	}
	s := guidedTestSession(t, nodes, nil)
	m := NewGuidedModel(s, "").(*guidedModel)
	m.Init()

	// First prompt should be for the group
	if m.state != stateGuidePrompt {
		t.Fatalf("expected stateGuidePrompt, got %v", m.state)
	}
	if m.item == nil || m.item.ID != "vscode" {
		t.Fatalf("expected vscode group, got %s", m.item.ID)
	}
	if !m.hasGroup() {
		t.Fatal("expected vscode to be a group with children")
	}

	// Accept group (set children defaults to Yes)
	m.answer = true
	m.onPromptDone()

	if m.state != stateGuidePrompt {
		t.Fatalf("expected still in prompt state after group accept, got %v", m.state)
	}
	if m.item == nil || m.item.ID != "vscode-ext1" {
		t.Fatalf("expected first extension prompted, got %v", m.item)
	}

	// Accept first extension
	m.answer = true
	m.onPromptDone()

	// Should now be executing (not prompting next yet)
	if m.state != stateGuideExecuting {
		t.Fatalf("expected executing state, got %v", m.state)
	}
}

// TestGuidedModelExecutesAcceptedNodeBeforeNextPrompt
func TestGuidedModelExecutesAcceptedNodeBeforeNextPrompt(t *testing.T) {
	nodes := []manifest.Node{
		{ID: "node1", Name: "Node 1", Steps: []manifest.Step{{Type: "run", Command: "echo one"}}},
		{ID: "node2", Name: "Node 2", Steps: []manifest.Step{{Type: "run", Command: "echo two"}}},
	}
	results := []executor.Result{{Status: "installed"}}
	s := guidedTestSession(t, nodes, results)
	m := NewGuidedModel(s, "").(*guidedModel)
	m.Init()

	// Accept first node
	m.answer = true
	m.onPromptDone()

	// Should be executing
	if m.state != stateGuideExecuting {
		t.Fatalf("expected executing, got %v", m.state)
	}

	// Simulate step done
	m.onStepDone(stepDoneMsg{
		itemID: "node1",
		result: installer.Result{ItemID: "node1", Status: installer.StatusInstalled},
	})

	// Should advance to next item in prompt state
	if m.state != stateGuidePrompt {
		t.Fatalf("expected prompt after done, got %v", m.state)
	}
	if m.item == nil || m.item.ID != "node2" {
		t.Fatalf("expected node2, got %v", m.item)
	}
}

// TestGuidedModelOffersRetrySkipQuitOnFailure
func TestGuidedModelOffersRetrySkipQuitOnFailure(t *testing.T) {
	nodes := []manifest.Node{
		{
			ID:    "failing",
			Name:  "Failing Tool",
			Steps: []manifest.Step{{Type: "run", Command: "boom"}},
		},
		{
			ID:    "next",
			Name:  "Next Tool",
			Steps: []manifest.Step{{Type: "run", Command: "ok"}},
		},
	}
	s := guidedTestSession(t, nodes, nil)
	m := NewGuidedModel(s, "").(*guidedModel)
	m.Init()

	// Accept
	m.answer = true
	m.onPromptDone()

	// Fail it
	m.onStepDone(stepDoneMsg{
		itemID: "failing",
		result: installer.Result{ItemID: "failing", Status: installer.StatusFailed, Reason: "boom"},
	})

	// Should be in failure state
	if m.state != stateGuideFailure {
		t.Fatalf("expected failure state, got %v", m.state)
	}
	if m.failID != "failing" {
		t.Fatalf("expected failing item, got %s", m.failID)
	}

	// Skip the failure
	m.onFailAction(failActionMsg{action: "skip"})

	// Should advance to next item
	if m.item == nil || m.item.ID != "next" {
		t.Fatalf("expected next item after skip, got %v", m.item)
	}

	// Accept and complete next
	m.answer = true
	m.onPromptDone()
	m.onStepDone(stepDoneMsg{
		itemID: "next",
		result: installer.Result{ItemID: "next", Status: installer.StatusInstalled},
	})

	// Should go to summary (no more items)
	if m.state != stateGuideSummary {
		t.Fatalf("expected summary state, got %v", m.state)
	}
}

// TestGuidedModelResumesAndRechecksAfterInteractiveCommand
func TestGuidedModelResumesAndRechecksAfterInteractiveCommand(t *testing.T) {
	nodes := []manifest.Node{
		{
			ID:    "interactive-node",
			Name:  "Needs Setup",
			Setup: []string{"git-identity"},
		},
	}
	s := guidedTestSession(t, nodes, nil)
	m := NewGuidedModel(s, "").(*guidedModel)
	m.Init()

	// Accept
	m.answer = true
	m.onPromptDone()

	// Should be executing
	if m.state != stateGuideExecuting {
		t.Fatalf("expected executing after accept, got %v", m.state)
	}

	// Simulate interactive needed message
	m.Update(interactiveNeededMsg{
		itemID: "interactive-node",
		reason: "needs interactive setup",
	})

	if m.state != stateGuideInteractiveCommand {
		t.Fatalf("expected interactive command state, got %v", m.state)
	}

	// Simulate interactive finished
	m.Update(interactiveFinishedMsg{})

	// Should go back to executing
	if m.state != stateGuideExecuting {
		t.Fatalf("expected executing after interactive, got %v", m.state)
	}
}
