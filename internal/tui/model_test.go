package tui

import (
	"testing"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	tea "charm.land/bubbletea/v2"
)

func TestNewModelBuilds(t *testing.T) {
	m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
	if err != nil {
		t.Fatalf("Load manifest: %v", err)
	}
	model := NewModel(m, "")
	if model == nil {
		t.Fatal("NewModel returned nil")
	}
	_ = model.(tea.Model)
}
