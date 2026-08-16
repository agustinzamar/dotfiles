package installer

import (
	"strings"

	tea "charm.land/bubbletea/v2"
)

type Model struct {
	components []Component
	cursor     int
	selected   map[string]bool
	submitted  bool
	query      string
	searching  bool
	applied    map[string]bool
	height     int
}

func NewModel() Model {
	selected := make(map[string]bool)
	for _, component := range Components() {
		selected[component.ID] = component.Default || component.Required
	}
	return Model{components: Components(), selected: selected, applied: make(map[string]bool)}
}

func (m Model) Init() tea.Cmd { return nil }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if size, ok := msg.(tea.WindowSizeMsg); ok {
		m.height = size.Height
		return m, nil
	}
	if key, ok := msg.(tea.KeyPressMsg); ok {
		if m.searching {
			switch key.String() {
			case "esc", "enter":
				m.searching = false
			case "backspace":
				if m.query != "" {
					m.query = m.query[:len(m.query)-1]
					m.cursor = 0
				}
			default:
				if key.Text != "" {
					m.query += key.Text
					m.cursor = 0
				}
			}
			return m, nil
		}

		switch key.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "enter":
			m.submitted = true
			return m, tea.Quit
		case "/":
			m.searching = true
		case "up", "down":
			indices := m.visibleIndices()
			if key.String() == "up" && m.cursor > 0 {
				m.cursor--
			}
			if key.String() == "down" && m.cursor < len(indices)-1 {
				m.cursor++
			}
		case "a", "n":
			indices := m.visibleIndices()
			if len(indices) == 0 {
				break
			}
			category := m.components[indices[m.cursor]].Category
			for _, index := range indices {
				component := m.components[index]
				if component.Category == category && !component.Required {
					m.selected[component.ID] = key.String() == "a"
				}
			}
		case "space":
			indices := m.visibleIndices()
			if len(indices) == 0 {
				break
			}
			component := m.components[indices[m.cursor]]
			if !component.Required && !m.applied[component.ID] {
				m.selected[component.ID] = !m.selected[component.ID]
			}
		}
	}
	return m, nil
}

func (m Model) Profile() Profile {
	selected := make(map[string]bool, len(m.selected))
	for id, enabled := range m.selected {
		selected[id] = enabled
	}
	return Profile{Components: selected}
}

func (m Model) Submitted() bool { return m.submitted }

func (m Model) Applied() map[string]bool {
	applied := make(map[string]bool, len(m.applied))
	for id, value := range m.applied {
		applied[id] = value
	}
	return applied
}

func (m *Model) ResetSubmission() { m.submitted = false }

func (m *Model) MarkApplied(componentIDs []string) {
	if m.applied == nil {
		m.applied = make(map[string]bool)
	}
	for _, id := range componentIDs {
		m.applied[id] = true
	}
}

func (m Model) visibleIndices() []int {
	query := strings.ToLower(m.query)
	indices := make([]int, 0, len(m.components))
	for index, component := range m.components {
		if query == "" || strings.Contains(strings.ToLower(component.Label), query) || strings.Contains(strings.ToLower(component.Category), query) {
			indices = append(indices, index)
		}
	}
	return indices
}

func (m Model) View() tea.View {
	indices := m.visibleIndices()
	rows := make([]string, 0, len(indices)*2)
	cursorRow := 0
	lastCategory := ""
	for i, index := range indices {
		component := m.components[index]
		if component.Category != lastCategory {
			rows = append(rows, "["+component.Category+"]")
			lastCategory = component.Category
		}
		cursor := " "
		if i == m.cursor {
			cursor = ">"
			cursorRow = len(rows)
		}
		mark := " "
		if m.selected[component.ID] {
			mark = "x"
		}
		status := ""
		if m.applied[component.ID] {
			status = " (installed)"
		}
		rows = append(rows, cursor+" ["+mark+"] "+component.Label+status)
	}
	if len(indices) == 0 {
		rows = append(rows, "No matching components.")
	}

	available := len(rows)
	if m.height > 0 {
		available = m.height - 4
		if available < 1 {
			available = 1
		}
	}
	start := 0
	if cursorRow >= available {
		start = cursorRow - available + 1
	}
	if start+available > len(rows) {
		start = len(rows) - available
		if start < 0 {
			start = 0
		}
	}
	end := start + available
	if end > len(rows) {
		end = len(rows)
	}
	text := "dot installer"
	if start > 0 {
		text += "  ↑ more"
	}
	text += "\n\n" + strings.Join(rows[start:end], "\n")
	if end < len(rows) {
		text += "\n↓ more"
	}
	if m.searching {
		text += "\n\nsearch: " + m.query + "_"
	} else {
		text += "\n\nspace toggle  a all  n none  / search  enter apply  q quit"
	}
	return tea.NewView(text)
}
