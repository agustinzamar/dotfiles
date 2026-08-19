package installer

import (
	"strings"

	tea "charm.land/bubbletea/v2"
)

const (
	ansiReset  = "\x1b[0m"
	ansiBold   = "\x1b[1m"
	ansiDim    = "\x1b[2m"
	ansiGreen  = "\x1b[32m"
	ansiCyan   = "\x1b[36m"
	ansiYellow = "\x1b[33m"
	ansiReverse = "\x1b[7m"
)

type pane int

const (
	paneCategories pane = iota
	paneComponents
)

type Model struct {
	components []Component
	categories []string

	pane      pane
	catCursor int
	cursor    int

	selected  map[string]bool
	applied   map[string]bool
	query     string
	searching bool

	review    bool
	reviewTop int

	submitted bool
	width     int
	height    int
}

func NewModel() Model {
	selected := make(map[string]bool)
	for _, component := range Components() {
		selected[component.ID] = component.Default || component.Required
	}
	components := Components()
	return Model{
		components: components,
		categories: categoryOrder(components),
		selected:   selected,
		applied:    make(map[string]bool),
	}
}

func categoryOrder(components []Component) []string {
	seen := make(map[string]bool)
	order := make([]string, 0)
	for _, component := range components {
		if !seen[component.Category] {
			seen[component.Category] = true
			order = append(order, component.Category)
		}
	}
	return order
}

func (m Model) Init() tea.Cmd { return nil }

func (m Model) activeCategory() string {
	if len(m.categories) == 0 {
		return ""
	}
	if m.catCursor < 0 {
		m.catCursor = 0
	}
	if m.catCursor >= len(m.categories) {
		m.catCursor = len(m.categories) - 1
	}
	return m.categories[m.catCursor]
}

// visibleIndices returns component indices visible in the right pane: every
// match when a search is active, otherwise the full grouped list.
func (m Model) visibleIndices() []int {
	query := strings.ToLower(m.query)
	indices := make([]int, 0, len(m.components))
	for index, component := range m.components {
		if m.searching {
			if query == "" || strings.Contains(strings.ToLower(component.Label), query) || strings.Contains(strings.ToLower(component.Category), query) {
				indices = append(indices, index)
			}
			continue
		}
		indices = append(indices, index)
	}
	return indices
}

// firstIndexInCategory returns the index into the component list of the first
// component in the given category, or the first matching index if the category
// is not present.
func (m Model) firstIndexInCategory(category string) int {
	for i := range m.components {
		if m.components[i].Category == category {
			return i
		}
	}
	return 0
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if size, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = size.Width
		m.height = size.Height
		return m, nil
	}
	key, ok := msg.(tea.KeyPressMsg)
	if !ok {
		return m, nil
	}

	if m.review {
		return m, m.updateReview(key)
	}
	if m.searching {
		switch {
		case key.String() == "esc" || key.String() == "enter":
			m.searching = false
		case key.String() == "backspace":
			if m.query != "" {
				m.query = m.query[:len(m.query)-1]
				m.cursor = 0
			}
		case key.Text != "":
			m.query += key.Text
			m.cursor = 0
		}
		return m, nil
	}

	switch key.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "/":
		m.searching = true
	case "tab", "left", "right":
		if m.pane == paneCategories {
			m.pane = paneComponents
		} else {
			m.pane = paneCategories
		}
	case "enter":
		if len(m.visibleIndices()) == 0 {
			break
		}
		m.review = true
		m.reviewTop = 0
	case "up", "down":
		if m.pane == paneCategories {
			if key.String() == "up" && m.catCursor > 0 {
				m.catCursor--
			}
			if key.String() == "down" && m.catCursor < len(m.categories)-1 {
				m.catCursor++
			}
			m.cursor = m.firstIndexInCategory(m.activeCategory())
		} else {
			indices := m.visibleIndices()
			if len(indices) > 0 {
				if key.String() == "up" && m.cursor > 0 {
					m.cursor--
				}
				if key.String() == "down" && m.cursor < len(indices)-1 {
					m.cursor++
				}
			}
		}
	case "a", "n":
		indices := m.visibleIndices()
		if len(indices) == 0 {
			break
		}
		if m.pane == paneCategories {
			m.selectCategory(m.activeCategory(), key.String() == "a")
		} else {
			component := m.components[indices[m.cursor]]
			m.selectCategory(component.Category, key.String() == "a")
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
	return m, nil
}

func (m *Model) selectCategory(category string, enabled bool) {
	for _, component := range m.components {
		if component.Category == category && !component.Required {
			m.selected[component.ID] = enabled
		}
	}
}

func (m *Model) updateReview(key tea.KeyPressMsg) tea.Cmd {
	switch key.String() {
	case "enter", "y":
		m.submitted = true
		m.review = false
		return tea.Quit
	case "esc":
		m.review = false
	case "q":
		return tea.Quit
	case "up":
		if m.reviewTop > 0 {
			m.reviewTop--
		}
	case "down":
		m.reviewTop++
	}
	return nil
}

func (m Model) reviewRows() []string {
	rows := make([]string, 0)
	lastCategory := ""
	for _, component := range m.components {
		if !m.selected[component.ID] || m.applied[component.ID] {
			continue
		}
		if component.Category != lastCategory {
			rows = append(rows, "["+component.Category+"]")
			lastCategory = component.Category
		}
		rows = append(rows, "   "+component.Label)
	}
	return rows
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

func (m Model) counts() (selected, installed, pending int) {
	for _, component := range m.components {
		if m.applied[component.ID] {
			installed++
			continue
		}
		if m.selected[component.ID] {
			selected++
			if !component.Required {
				pending++
			}
		}
	}
	return selected, installed, pending
}

func (m Model) View() tea.View {
	if m.review {
		return tea.NewView(m.reviewView())
	}
	return tea.NewView(m.selectionView())
}

func (m Model) reviewView() string {
	rows := m.reviewRows()
	available := m.height - 5
	if available < 1 {
		available = 1
	}
	start := m.reviewTop
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
	_, installed, pending := m.counts()
	lines := []string{ansiBold + " Review plan " + ansiReset + " (" + ansiGreen + "✓ installed " + itoa(installed) + ansiReset + ", " + ansiYellow + "to install " + itoa(pending) + ansiReset + ")"}
	lines = append(lines, "")
	if len(rows) == 0 {
		lines = append(lines, ansiDim+"Nothing to install — everything is already applied."+ansiReset)
	} else {
		if start > 0 {
			lines = append(lines, ansiDim+"↑ more"+ansiReset)
		}
		lines = append(lines, rows[start:end]...)
		if end < len(rows) {
			lines = append(lines, ansiDim+"↓ more"+ansiReset)
		}
	}
	lines = append(lines, "")
	lines = append(lines, ansiDim+"enter apply  esc back  q quit"+ansiReset)
	return strings.Join(lines, "\n")
}

func itoa(value int) string {
	if value == 0 {
		return "0"
	}
	digits := ""
	for value > 0 {
		digits = string(rune('0'+value%10)) + digits
		value /= 10
	}
	return digits
}

func (m Model) selectionView() string {
	_, installed, pending := m.counts()

	categoryRows := m.categoryRows()
	sidebarWidth := 0
	for _, row := range categoryRows {
		if len(row) > sidebarWidth {
			sidebarWidth = len(row)
		}
	}

	componentRows, cursorRow := m.componentRows()
	bodyHeight := m.height - 4
	if bodyHeight < 1 {
		bodyHeight = 1
	}

	header := ansiBold + " dot installer " + ansiReset
	if m.searching {
		header += ansiDim + " search: " + m.query + "_" + ansiReset
	} else {
		header += ansiDim + "(tab pane  / search)" + ansiReset
	}

	status := " " + ansiGreen + "✓ installed " + itoa(installed) + ansiReset +
		"  " + ansiYellow + "selected " + itoa(pending) + ansiReset

	lines := []string{header, ""}

	compStart := m.clampViewport(cursorRow, bodyHeight, len(componentRows))
	compEnd := compStart + bodyHeight
	if compEnd > len(componentRows) {
		compEnd = len(componentRows)
	}

	moreTop := compStart > 0
	moreBottom := compEnd < len(componentRows)
	lastRow := bodyHeight - 1
	for row := 0; row < bodyHeight; row++ {
		left := ""
		if !m.searching {
			if row < len(categoryRows) {
				left = categoryRows[row]
			}
			left = padRight(left, sidebarWidth)
			if m.pane == paneCategories && row == m.catCursor {
				left = ansiReverse + left + ansiReset
			}
		}
		right := ""
		if compStart+row < compEnd {
			right = componentRows[compStart+row]
		}
		if row == 0 && moreTop {
			right = ansiDim + "↑ more" + ansiReset
		}
		if row == lastRow && moreBottom {
			right = ansiDim + "↓ more" + ansiReset
		}
		lines = append(lines, left+"  "+right)
	}

	help := ansiDim + "space toggle  a all  n none  enter review  q quit" + ansiReset
	lines = append(lines, status, help)
	return strings.Join(lines, "\n")
}

func padRight(text string, width int) string {
	for len(text) < width {
		text += " "
	}
	return text
}

func (m Model) clampViewport(cursor, viewport, total int) int {
	if total <= viewport {
		return 0
	}
	start := cursor - viewport/2
	if start < 0 {
		start = 0
	}
	if start+viewport > total {
		start = total - viewport
	}
	return start
}

func (m Model) categoryRows() []string {
	rows := make([]string, 0, len(m.categories))
	for _, category := range m.categories {
		mark := " "
		if category == m.activeCategory() {
			mark = ">"
		}
		rows = append(rows, mark+" "+category)
	}
	return rows
}

func (m Model) componentRows() ([]string, int) {
	indices := m.visibleIndices()
	rows := make([]string, 0, len(indices))
	if len(indices) == 0 {
		return []string{ansiDim + "No matches for " + m.query + ansiReset}, 0
	}
	lastCategory := ""
	cursorRow := 0
	for i, index := range indices {
		component := m.components[index]
		if component.Category != lastCategory {
			rows = append(rows, ansiDim+"["+component.Category+"]"+ansiReset)
			lastCategory = component.Category
		}
		if i == m.cursor {
			cursorRow = len(rows)
		}
		cursor := " "
		if i == m.cursor {
			cursor = ">"
		}
		rows = append(rows, cursor+" "+m.stateMark(component)+" "+component.Label)
	}
	return rows, cursorRow
}

func (m Model) stateMark(component Component) string {
	switch {
	case m.applied[component.ID]:
		return ansiGreen + "✓" + ansiReset
	case m.selected[component.ID]:
		return ansiYellow + "x" + ansiReset
	default:
		return " "
	}
}
