package tui

import (
	"fmt"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	tea "github.com/charmbracelet/bubbletea"
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
	categories []manifest.Category
	items      []toolItem
	cursor     int
	state      state
	messages   []string
	vars       map[string]string
}

func NewModel(m *manifest.Manifest) tea.Model {
	vars := config.GetVars()
	var items []toolItem
	for _, cat := range m.Categories {
		for _, t := range cat.Tools {
			items = append(items, toolItem{tool: t, checked: t.Checked})
		}
	}
	return &model{
		categories: m.Categories,
		items:      items,
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
			case "up", "k":
				if m.cursor > 0 {
					m.cursor--
				}
			case "down", "j":
				if m.cursor < len(m.items)-1 {
					m.cursor++
				}
			case " ":
				m.items[m.cursor].checked = !m.items[m.cursor].checked
			case "enter":
				m.collectVars()
				m.state = stateInstalling
				return m, installNextCmd(0, m)
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
		for i := range m.items {
			if m.items[i].tool.Name == msg.toolName {
				for j := i + 1; j < len(m.items); j++ {
					if m.items[j].checked {
						return m, installNextCmd(j, m)
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
	b.WriteString("\n")
	b.WriteString(HelpStyle.Render("j/k or \u2191/\u2193 navigate  Space toggle  Enter install  q quit"))
	b.WriteString("\n\n")

	currentCat := ""
	for i, item := range m.items {
		if item.tool.Category != currentCat {
			currentCat = item.tool.Category
			b.WriteString(CategoryStyle.Render(currentCat))
			b.WriteString("\n")
		}
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
	return b.String()
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
	for _, item := range m.items {
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

func installNextCmd(idx int, m *model) tea.Cmd {
	item := m.items[idx]
	if !item.checked {
		return nil
	}
	return func() tea.Msg {
		var results []executor.Result
		dotfilesDir := manifest.DotfilesDir()
		for _, step := range item.tool.Steps {
			r := executor.Run(step, dotfilesDir, m.vars)
			results = append(results, r)
		}
		return installMsg{toolName: item.tool.Name, results: results}
	}
}
