package tui

import (
	"fmt"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/logger"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type state int

const (
	stateSelecting state = iota
	statePrompting
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
	categories     []manifest.Category
	toolsByTab     [][]toolItem
	tabIndex       int
	cursor         int
	state          state
	messages       []string
	vars           map[string]string
	spinner        spinner.Model
	currentTool    string
	installing     int
	totalToInstall int
	textInput      textinput.Model
	promptKeys     []string
	promptIndex    int
}

func NewModel(m *manifest.Manifest) tea.Model {
	vars := config.GetVars()
	toolsByTab := make([][]toolItem, len(m.Categories))
	for i, cat := range m.Categories {
		for _, t := range cat.Tools {
			toolsByTab[i] = append(toolsByTab[i], toolItem{tool: t, checked: t.Checked})
		}
	}
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = SpinnerStyle
	ti := textinput.New()
	ti.Placeholder = ""
	ti.CharLimit = 256
	return &model{
		categories: m.Categories,
		toolsByTab: toolsByTab,
		state:      stateSelecting,
		vars:       vars,
		spinner:    s,
		textInput:  ti,
	}
}

func (m *model) Init() tea.Cmd { return m.spinner.Tick }

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

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
				m.startPrompting()
				if m.state == stateInstalling {
					return m, installNextFlatCmd(0, m)
				}
				m.textInput.Focus()
				return m, textinput.Blink
			}
		}

		if m.state == statePrompting {
			switch msg.String() {
			case "enter":
				val := m.textInput.Value()
				m.vars[m.promptKeys[m.promptIndex]] = val
				config.SaveVars(m.vars)
				m.promptIndex++
				if m.promptIndex >= len(m.promptKeys) {
					m.state = stateInstalling
					return m, installNextFlatCmd(0, m)
				}
				m.textInput.SetValue("")
				m.textInput.Focus()
				return m, textinput.Blink
			case "ctrl+c":
				return m, tea.Quit
			default:
				var cmd tea.Cmd
				m.textInput, cmd = m.textInput.Update(msg)
				return m, cmd
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
			logger.Log(r.Status, msg.toolName, r.Msg)
		}
		flat := m.flatItems()
		for i := range flat {
			if flat[i].tool.Name == msg.toolName {
				return m, installNextFlatCmd(i+1, m)
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
	case statePrompting:
		return m.promptingView()
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

	if m.state == stateInstalling {
		b.WriteString(fmt.Sprintf("%s Installing %d/%d: %s\n",
			m.spinner.View(), m.installing, m.totalToInstall, m.currentTool))
	}

	for _, msg := range m.messages {
		b.WriteString(msg)
		b.WriteString("\n")
	}
	if m.state == stateDone {
		b.WriteString("\n" + SuccessStyle.Render("Done. Restart your terminal."))
	}
	return b.String()
}

func (m *model) startPrompting() {
	seen := map[string]bool{}
	var keys []string
	flat := m.flatItems()
	for _, item := range flat {
		if !item.checked {
			continue
		}
		m.totalToInstall++
		for _, step := range item.tool.Steps {
			if step.Type != "template-symlink" {
				continue
			}
			for _, k := range step.Vars {
				if !seen[k] && m.vars[k] == "" {
					keys = append(keys, k)
				}
				seen[k] = true
			}
		}
	}
	if len(keys) == 0 {
		m.vars = config.GetVars()
		m.state = stateInstalling
		return
	}
	m.promptKeys = keys
	m.promptIndex = 0
	m.textInput.SetValue("")
	m.state = statePrompting
}

func (m *model) promptingView() string {
	var b strings.Builder
	b.WriteString(TitleStyle.Render("Setup"))
	b.WriteString("\n\n")
	b.WriteString(fmt.Sprintf("Enter value for %s:\n\n", PromptLabelStyle.Render(m.promptKeys[m.promptIndex])))
	b.WriteString(m.textInput.View())
	b.WriteString("\n\n")
	b.WriteString(HelpStyle.Render(fmt.Sprintf("%d/%d values needed. Enter to confirm, Ctrl+C to quit.", m.promptIndex+1, len(m.promptKeys))))
	return b.String()
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
	m.currentTool = item.tool.Name
	m.installing++
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
