package installer

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func TestModelEnterShowsReviewThenSubmits(t *testing.T) {
	model := NewModel()
	model.selected["php"] = false

	updated, cmd := model.Update(tea.KeyPressMsg(tea.Key{Code: tea.KeyEnter}))
	model = updated.(Model)
	if !model.review {
		t.Fatal("enter did not open the review screen")
	}
	if cmd != nil {
		t.Fatal("review screen returned a command")
	}
	view := model.View().Content
	if !strings.Contains(view, "Review plan") {
		t.Fatalf("review view = %q", view)
	}
	updated, cmd = model.Update(tea.KeyPressMsg(tea.Key{Code: tea.KeyEnter}))
	model = updated.(Model)
	if !model.Submitted() {
		t.Fatal("enter on review did not submit the model")
	}
	if cmd == nil {
		t.Fatal("submit did not return a quit command")
	}
	if model.Profile().Components["php"] {
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
	updated, _ := model.Update(tea.WindowSizeMsg{Height: 12, Width: 80})
	model = updated.(Model)
	model.pane = paneCategories
	for index, category := range model.categories {
		if category == "Communication" {
			model.catCursor = index
			break
		}
	}
	updated, _ = model.Update(tea.KeyPressMsg(tea.Key{Text: "a"}))
	model = updated.(Model)
	if !model.selected["communication-discord"] || !model.selected["communication-slack"] {
		t.Fatal("category action did not select communication apps")
	}
	model.pane = paneComponents
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
	view := model.View().Content
	if !strings.Contains(view, "✓") {
		t.Fatal("applied component is not shown with an applied mark")
	}
}

func TestModelSidebarNavigatesCategories(t *testing.T) {
	model := NewModel()
	model.pane = paneCategories
	model.catCursor = 0
	for range model.categories {
		updated, _ := model.Update(tea.KeyPressMsg(tea.Key{Code: tea.KeyDown}))
		model = updated.(Model)
	}
	if model.catCursor != len(model.categories)-1 {
		t.Fatalf("down arrows did not reach the last category: %d of %d", model.catCursor, len(model.categories))
	}
	indices := model.visibleIndices()
	if len(indices) == 0 {
		t.Fatal("last category has no components")
	}
	last := model.components[indices[len(indices)-1]]
	if last.Category != model.activeCategory() {
		t.Fatalf("component %s is outside the active category %s", last.ID, model.activeCategory())
	}
}