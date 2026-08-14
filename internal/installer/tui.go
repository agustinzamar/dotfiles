package installer

import tea "charm.land/bubbletea/v2"

type Model struct {
	components []Component
	cursor     int
	selected   map[string]bool
}

func NewModel() Model {
	selected := make(map[string]bool)
	for _, component := range Components() {
		selected[component.ID] = component.Default || component.Required
	}
	return Model{components: Components(), selected: selected}
}

func (m Model) Init() tea.Cmd { return nil }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyPressMsg); ok {
		switch key.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "up":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down":
			if m.cursor < len(m.components)-1 {
				m.cursor++
			}
		case "space":
			component := m.components[m.cursor]
			if !component.Required {
				m.selected[component.ID] = !m.selected[component.ID]
			}
		}
	}
	return m, nil
}

func (m Model) View() tea.View {
	text := "dot installer\n\n"
	for i, component := range m.components {
		cursor := " "
		if i == m.cursor {
			cursor = ">"
		}
		mark := " "
		if m.selected[component.ID] {
			mark = "x"
		}
		text += cursor + " [" + mark + "] " + component.Category + ": " + component.Label + "\n"
	}
	text += "\nspace toggle  arrows move  q quit"
	return tea.NewView(text)
}
