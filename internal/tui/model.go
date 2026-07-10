package tui

import (
	"fmt"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type state int

const (
	stateSelecting state = iota
	stateInstalling
	stateDone
)

type toolItem struct {
	tool    manifest.Tool
	checked bool
}

type installMsg struct {
	toolName string
	results  []executor.Result
}

type model struct {
	categories  []manifest.Category
	toolsByTab  [][]toolItem
	tabIndex    int
	cursor      int
	state       state
	messages    []string
	vars        map[string]string
}

func NewModel(m *manifest.Manifest) tea.Model {
	vars := config.GetVars()
	toolsByTab := make([][]toolItem, len(m.Categories))
	for i, cat := range m.Categories {
		for _, t := range cat.Tools {
			toolsByTab[i] = append(toolsByTab[i], toolItem{tool: t, checked: t.Checked})
		}
	}
	return &model{
		categories: m.Categories,
		toolsByTab: toolsByTab,
		state:      stateSelecting,
		vars:       vars,
	}
}

func (m *model) Init() tea.Cmd { return nil }

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if m.state == stateSelecting {
			switch msg.String() {
			case "ctrl+c", "q":
				return m, tea.Quit
			case "left", "shift+tab":
				if m.tabIndex > 0 {
					m.tabIndex--
					m.cursor = 0
				}
			case "right", "tab":
				if m.tabIndex < len(m.toolsByTab)-1 {
					m.tabIndex++
					m.cursor = 0
				}
			case "up", "k":
				if m.cursor > 0 {
					m.cursor--
				}
			case "down", "j":
				if m.cursor < len(m.toolsByTab[m.tabIndex])-1 {
					m.cursor++
				}
			case " ":
				if len(m.toolsByTab[m.tabIndex]) > 0 {
					m.toolsByTab[m.tabIndex][m.cursor].checked = !m.toolsByTab[m.tabIndex][m.cursor].checked
				}
			case "enter":
				m.collectVars()
				m.state = stateInstalling
				return m, installNextFlatCmd(0, m)
			}
		}

	case installMsg:
		for _, r := range msg.results {
			icon := "\u2713"
			switch r.Status {
			case "skipped":
				icon = "\u2022"
			case "error":
				icon = "\u2717"
			}
			m.messages = append(m.messages, fmt.Sprintf("  %s %s: %s", icon, msg.toolName, r.Msg))
		}
		flat := m.flatItems()
		for i := range flat {
			if flat[i].tool.Name == msg.toolName {
				for j := i + 1; j < len(flat); j++ {
					if flat[j].checked {
						return m, installNextFlatCmd(j, m)
					}
				}
				break
			}
		}
		m.state = stateDone
		return m, tea.Quit
	}

	return m, nil
}

func (m *model) flatItems() []toolItem {
	var items []toolItem
	for _, tab := range m.toolsByTab {
		items = append(items, tab...)
	}
	return items
}

func (m *model) View() string {
	switch m.state {
	case stateSelecting:
		return m.selectionView()
	case stateInstalling, stateDone:
		return m.installingView()
	}
	return ""
}

func (m *model) selectionView() string {
	var b strings.Builder

	b.WriteString(TitleStyle.Render("Dotfiles Installer"))
	b.WriteString("\n\n")

	// Tabs bar
	var tabStyles []string
	for i, cat := range m.categories {
		if i == m.tabIndex {
			tabStyles = append(tabStyles, CategoryActiveStyle.Render(cat.Name))
		} else {
			tabStyles = append(tabStyles, CategoryStyle.Render(cat.Name))
		}
	}
	b.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, tabStyles...))
	b.WriteString("\n")
	b.WriteString(strings.Repeat("\u2500", 60))
	b.WriteString("\n\n")

	// Help text
	b.WriteString(HelpStyle.Render("\u2190/\u2192 switch tab  j/k navigate  Space toggle  Enter install  q quit"))
	b.WriteString("\n\n")

	// Current tab's tools
	items := m.toolsByTab[m.tabIndex]
	if len(items) == 0 {
		b.WriteString(HelpStyle.Render("  No tools in this category"))
		b.WriteString("\n")
	}
	for i, item := range items {
		cursor := " "
		if m.cursor == i {
			cursor = CursorStyle.Render(">")
		}
		checkbox := "[ ]"
		if item.checked {
			checkbox = CheckedStyle.Render("[\u2713]")
		}
		name := UncheckedStyle.Render(item.tool.Name)
		if item.checked {
			name = CheckedStyle.Render(item.tool.Name)
		}
		if m.cursor == i {
			name = CursorStyle.Render(item.tool.Name)
		}
		b.WriteString(CheckboxStyle.Render(fmt.Sprintf("%s %s %s", cursor, checkbox, name)))
		b.WriteString("\n")
	}

	// Checked tool summary
	_, total := m.checkedCount()
	b.WriteString(fmt.Sprintf("\n%s", HelpStyle.Render(fmt.Sprintf("%d checked across all categories. Press Enter to install.", total))))

	return b.String()
}

func (m *model) checkedCount() (int, int) {
	checked := 0
	total := 0
	for _, tab := range m.toolsByTab {
		for _, item := range tab {
			total++
			if item.checked {
				checked++
			}
		}
	}
	return checked, total
}

func (m *model) installingView() string {
	var b strings.Builder
	b.WriteString(TitleStyle.Render("Installing..."))
	b.WriteString("\n")
	for _, msg := range m.messages {
		b.WriteString(msg)
		b.WriteString("\n")
	}
	if m.state == stateDone {
		b.WriteString("\n" + SuccessStyle.Render("Done. Restart your terminal."))
	}
	return b.String()
}

func (m *model) collectVars() {
	flat := m.flatItems()
	for _, item := range flat {
		if !item.checked {
			continue
		}
		for _, step := range item.tool.Steps {
			if step.Type == "template-symlink" {
				config.PromptMissing(step.Vars)
			}
		}
	}
	m.vars = config.GetVars()
}

func installNextFlatCmd(idx int, m *model) tea.Cmd {
	flat := m.flatItems()
	if idx >= len(flat) {
		return nil
	}
	item := flat[idx]
	if !item.checked {
		return nil
	}
	return func() tea.Msg {
		var results []executor.Result
		dotfilesDir := manifest.DotfilesDir()
		for _, step := range item.tool.Steps {
			r := executor.Run(step, dotfilesDir, m.vars, false)
			results = append(results, r)
		}
		return installMsg{toolName: item.tool.Name, results: results}
	}
}

var CategoryActiveStyle = lipgloss.NewStyle().
	Bold(true).
	Foreground(lipgloss.Color("#1e1e2e")).
	Background(lipgloss.Color("#c6a0f6")).
	Padding(0, 1)
