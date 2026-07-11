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

var manifestRef *manifest.Manifest

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

type stepResultMsg struct {
	toolName string
	stepType string
	result   executor.Result
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
	textInput      textinput.Model
	promptVars    []manifest.VarDef
	promptIndex    int
	stepQueue      []stepQueueItem
	currentTool    string
	currentStep    string
	stepsDone      int
	totalSteps     int
	installed      int
	skipped        int
	errors         int
}

type stepQueueItem struct {
	toolName string
	step     manifest.Step
}

func NewModel(m *manifest.Manifest) tea.Model {
	manifestRef = m
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
		if m.state == stateInstalling || m.state == stateDone {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}

	case tea.KeyMsg:
		if m.state == stateDone {
			return m, tea.Quit
		}

		if m.state == stateInstalling {
			if msg.String() == "ctrl+c" {
				return m, tea.Quit
			}
		}

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
					return m, tea.Batch(m.spinner.Tick, installNextStep(m))
				}
				m.textInput.Focus()
				return m, textinput.Blink
			}
		}

		if m.state == statePrompting {
			switch msg.String() {
			case "enter":
				val := m.textInput.Value()
				m.vars[m.promptVars[m.promptIndex].Name] = val
				config.SaveVars(m.vars)
				m.promptIndex++
				if m.promptIndex >= len(m.promptVars) {
					m.state = stateInstalling
					return m, tea.Batch(m.spinner.Tick, installNextStep(m))
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

	case stepResultMsg:
		icon := "\u2713"
		switch msg.result.Status {
		case "skipped":
			icon = "\u2022"
			m.skipped++
		case "error":
			icon = "\u2717"
			m.errors++
		default:
			m.installed++
		}
		m.stepsDone++
		m.messages = append(m.messages, fmt.Sprintf("  %s %s: %s", icon, msg.toolName, msg.result.Msg))
		logger.Log(msg.result.Status, msg.toolName, msg.result.Msg)

		if len(m.stepQueue) == 0 {
			m.state = stateDone
			return m, nil
		}
		return m, installNextStep(m)
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

	b.WriteString(HelpStyle.Render("\u2190/\u2192 switch tab  j/k navigate  Space toggle  Enter install  q quit"))
	b.WriteString("\n\n")

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
		desc := HelpStyle.Render(item.tool.Description)
		b.WriteString(CheckboxStyle.Render(fmt.Sprintf("%s %s %s %s", cursor, checkbox, name, desc)))
		b.WriteString("\n")
	}

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
	b.WriteString("\n\n")

	if m.state == stateInstalling && len(m.stepQueue) > 0 {
		b.WriteString(fmt.Sprintf("%s %s Installing step %d/%d: %s (%s)\n",
			m.spinner.View(), m.currentTool, m.stepsDone+1, m.totalSteps, m.currentTool, m.currentStep))
		b.WriteString("\n")
	}

	maxMsgs := 30
	start := 0
	if len(m.messages) > maxMsgs {
		start = len(m.messages) - maxMsgs
		b.WriteString(HelpStyle.Render(fmt.Sprintf("  ... %d earlier messages\n", start)))
	}
	for _, msg := range m.messages[start:] {
		b.WriteString(msg)
		b.WriteString("\n")
	}

	if m.state == stateDone {
		b.WriteString("\n" + SuccessStyle.Render("Installation Complete"))
		b.WriteString("\n\n")
		b.WriteString(fmt.Sprintf("  %s %d installed", SuccessStyle.Render("\u2713"), m.installed))
		b.WriteString("\n")
		b.WriteString(fmt.Sprintf("  %s %d skipped (already done)", HelpStyle.Render("\u2022"), m.skipped))
		b.WriteString("\n")
		if m.errors > 0 {
			b.WriteString(fmt.Sprintf("  %s %d errors", ErrorStyle.Render("\u2717"), m.errors))
		} else {
			b.WriteString(fmt.Sprintf("  %s 0 errors", SuccessStyle.Render("\u2713")))
		}
		b.WriteString("\n\n")
		b.WriteString(HelpStyle.Render("Press any key to exit."))
	}
	return b.String()
}

func (m *model) startPrompting() {
	seen := map[string]bool{}
	var vars []manifest.VarDef
	flat := m.flatItems()
	var queue []stepQueueItem
	for _, item := range flat {
		if !item.checked {
			continue
		}
		for _, step := range item.tool.Steps {
			queue = append(queue, stepQueueItem{toolName: item.tool.Name, step: step})
			if step.Type != "template-symlink" {
				continue
			}
			for _, k := range step.Vars {
				if !seen[k] && m.vars[k] == "" {
					if vd, ok := manifestRef.Vars[k]; ok {
						vars = append(vars, manifest.VarDef{Name: k, Description: vd.Description, Why: vd.Why, Hint: vd.Hint})
					} else {
						vars = append(vars, manifest.VarDef{Name: k, Description: k})
					}
				}
				seen[k] = true
			}
		}
	}
	m.stepQueue = queue
	m.totalSteps = len(queue)
	if len(vars) == 0 {
		m.vars = config.GetVars()
		m.state = stateInstalling
		return
	}
	m.promptVars = vars
	m.promptIndex = 0
	m.textInput.SetValue("")
	m.state = statePrompting
}

func (m *model) promptingView() string {
	var b strings.Builder
	vd := m.promptVars[m.promptIndex]
	b.WriteString(TitleStyle.Render("Setup"))
	b.WriteString("\n")
	b.WriteString(strings.Repeat("\u2500", 60))
	b.WriteString("\n\n")
	b.WriteString(fmt.Sprintf("Enter %s:\n\n", PromptLabelStyle.Render(vd.Description)))
	if vd.Why != "" {
		b.WriteString(HelpStyle.Render(fmt.Sprintf("  %s", vd.Why)))
		b.WriteString("\n")
	}
	if vd.Hint != "" {
		b.WriteString(HelpStyle.Render(fmt.Sprintf("  %s", vd.Hint)))
		b.WriteString("\n")
	}
	b.WriteString("\n")
	b.WriteString(m.textInput.View())
	b.WriteString("\n\n")
	b.WriteString(HelpStyle.Render(fmt.Sprintf("%d/%d values needed. Enter to confirm, Ctrl+C to quit.", m.promptIndex+1, len(m.promptVars))))
	return b.String()
}

func installNextStep(m *model) tea.Cmd {
	if len(m.stepQueue) == 0 {
		return nil
	}
	item := m.stepQueue[0]
	m.stepQueue = m.stepQueue[1:]
	m.currentTool = item.toolName
	m.currentStep = item.step.Type
	return func() tea.Msg {
		dotfilesDir := manifest.DotfilesDir()
		r := executor.Run(item.step, dotfilesDir, m.vars, false)
		return stepResultMsg{toolName: item.toolName, stepType: item.step.Type, result: r}
	}
}

var CategoryActiveStyle = lipgloss.NewStyle().
	Bold(true).
	Foreground(lipgloss.Color("#1e1e2e")).
	Background(lipgloss.Color("#c6a0f6")).
	Padding(0, 1)
