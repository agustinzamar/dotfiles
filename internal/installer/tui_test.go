package installer

import (
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
