package installer

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func TestModelEnterSubmitsSelection(t *testing.T) {
	model := NewModel()
	model.selected["php"] = false

	updated, cmd := model.Update(tea.KeyPressMsg(tea.Key{Code: tea.KeyEnter}))
	if cmd == nil || !updated.(Model).Submitted() {
		t.Fatal("enter did not submit the model")
	}
	if updated.(Model).Profile().Components["php"] {
		t.Fatal("profile did not preserve selection")
	}
}

func TestModelViewportKeepsFooterVisible(t *testing.T) {
	model := NewModel()
	updated, _ := model.Update(tea.WindowSizeMsg{Height: 8, Width: 80})
	model = updated.(Model)
	content := model.View().Content
	if !strings.Contains(content, "space toggle") {
		t.Fatal("viewport removed the footer")
	}
	if !strings.Contains(content, "more") {
		t.Fatal("viewport did not indicate clipped rows")
	}
}

func TestModelSelectsCategoryAndSearches(t *testing.T) {
	model := NewModel()
	for index, component := range model.components {
		if component.ID == "communication-discord" {
			model.cursor = index
			break
		}
	}
	updated, _ := model.Update(tea.KeyPressMsg(tea.Key{Text: "a"}))
	model = updated.(Model)
	if !model.selected["communication-discord"] || !model.selected["communication-slack"] {
		t.Fatal("category action did not select communication apps")
	}
	updated, _ = model.Update(tea.KeyPressMsg(tea.Key{Text: "/"}))
	model = updated.(Model)
	for _, character := range "discord" {
		updated, _ = model.Update(tea.KeyPressMsg(tea.Key{Text: string(character)}))
		model = updated.(Model)
	}
	view := model.View().Content
	if !strings.Contains(view, "Discord") || strings.Contains(view, "Slack") {
		t.Fatalf("search view = %q", view)
	}
}

func TestModelMarksAppliedComponents(t *testing.T) {
	model := NewModel()
	model.MarkApplied([]string{"communication-discord"})
	if !strings.Contains(model.View().Content, "Discord (installed)") {
		t.Fatal("applied component is not shown as installed")
	}
}
