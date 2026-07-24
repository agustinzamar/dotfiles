package tui

import (
	"fmt"
	"os/exec"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/huh/v2"
	"github.com/agustinzamar/dotfiles/internal/installer"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/workflow"
)

type guidedState int

const (
	stateGuidePrompt guidedState = iota
	stateGuideExecuting
	stateGuideInteractiveCommand
	stateGuideWorkflowPrompt
	stateGuideFailure
	stateGuideSummary
)

// msg types for guiding state machine
type stepDoneMsg struct {
	itemID string
	result installer.Result
}

type interactiveNeededMsg struct {
	itemID string
	reason string
}

type interactiveFinishedMsg struct{ err error }

type workflowAnswer struct {
	value string
	ok    bool
}

type workflowRequest struct {
	kind    string
	title   string
	value   string
	options []string
	answer  chan workflowAnswer
}

type workflowEventMsg struct {
	request *workflowRequest
	result  *workflow.Result
	err     error
}

type failActionMsg struct {
	action string
}

type guidedModel struct {
	session *installer.Session
	profile string
	state   guidedState

	// current decision
	item   *installer.Item
	answer bool
	sel    string

	// form
	form *huh.Form

	// results accum
	results []installer.Result

	// failure state
	failID  string
	failMsg string

	// interactive state
	interactiveItem string
	setup           []string
	setupIndex      int
	interactiveCmd  *exec.Cmd
	workflowEvents  <-chan workflowEventMsg
	workflowRequest *workflowRequest
	workflowValue   string
	workflowConfirm bool
	workflowRunner  *workflow.Runner

	// sizing
	width  int
	height int
}

func NewGuidedModel(session *installer.Session, profile string) tea.Model {
	return &guidedModel{
		session:        session,
		profile:        profile,
		state:          stateGuidePrompt,
		workflowRunner: newGuidedWorkflowRunner(),
	}
}

// --- lifecycle ---

func (m *guidedModel) Init() tea.Cmd {
	m.nextItem()
	if m.item == nil {
		m.state = stateGuideSummary
		return nil
	}
	return m.rebuildForm()
}

func (m *guidedModel) nextItem() {
	planner := m.session.Planner()
	m.item = planner.Next()
}

func (m *guidedModel) hasGroup() bool {
	return m.item != nil && len(m.item.Node.Node.Children) > 0
}

func (m *guidedModel) rebuildForm() tea.Cmd {
	item := m.item
	if item == nil {
		m.state = stateGuideSummary
		return tea.Quit
	}

	m.answer = item.Decision == installer.DecisionYes

	title := fmt.Sprintf("Install %s?", item.Name)
	if m.hasGroup() {
		title = fmt.Sprintf("Include %s components?", item.Name)
	}
	desc := item.Node.Node.Description
	if desc == "" {
		desc = item.Node.Node.ID
	}
	if m.hasGroup() {
		desc += " (each component confirmed individually)"
	}

	confirm := huh.NewConfirm().
		Title(title).
		Description(desc).
		Value(&m.answer)

	m.form = huh.NewForm(huh.NewGroup(confirm).WithWidth(80))
	if m.width > 0 {
		m.form = m.form.WithWidth(m.width)
	}
	return m.form.Init()
}

// --- update ---

func (m *guidedModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if wm, ok := msg.(tea.WindowSizeMsg); ok {
		m.width = wm.Width
		m.height = wm.Height
	}

	// handle forms in prompt and failure states
	if m.form != nil && (m.state == stateGuidePrompt || m.state == stateGuideFailure || m.state == stateGuideWorkflowPrompt) {
		fm, cmd := m.form.Update(msg)
		m.form = fm.(*huh.Form)
		if m.form.State == huh.StateCompleted {
			return m, m.onFormDone()
		}
		return m, cmd
	}

	switch msg := msg.(type) {
	case stepDoneMsg:
		return m.onStepDone(msg)
	case interactiveNeededMsg:
		m.state = stateGuideInteractiveCommand
		m.interactiveItem = msg.itemID
		return m, nil
	case interactiveFinishedMsg:
		if msg.err != nil {
			return m, func() tea.Msg {
				return stepDoneMsg{itemID: m.item.ID, result: installer.Result{ItemID: m.item.ID, Status: installer.StatusFailed, Reason: msg.err.Error()}}
			}
		}
		m.state = stateGuideExecuting
		m.interactiveCmd = nil
		m.setupIndex++
		return m, m.startWorkflow()
	case workflowEventMsg:
		return m.onWorkflowEvent(msg)
	case failActionMsg:
		return m.onFailAction(msg)
	case tea.KeyMsg:
		switch m.state {
		case stateGuideSummary:
			return m, tea.Quit
		case stateGuideInteractiveCommand:
			switch msg.String() {
			case "enter":
				return m, m.runInteractiveCmd()
			case "esc":
				if m.item != nil {
					m.item.Status = installer.StatusPendingSetup
					m.item.Reason = "interactive setup skipped"
				}
				m.nextItem()
				m.state = stateGuidePrompt
				return m, m.rebuildForm()
			}
		}
	}
	return m, nil
}

// --- form completion ---

func (m *guidedModel) onFormDone() tea.Cmd {
	switch m.state {
	case stateGuidePrompt:
		return m.onPromptDone()
	case stateGuideFailure:
		return m.onFailFormDone()
	case stateGuideWorkflowPrompt:
		return m.onWorkflowFormDone()
	}
	return nil
}

func (m *guidedModel) onPromptDone() tea.Cmd {
	item := m.item
	if item == nil {
		m.state = stateGuideSummary
		return tea.Quit
	}

	planner := m.session.Planner()

	if m.hasGroup() {
		if m.answer {
			planner.SetGroupDefault(item.ID, installer.DecisionYes)
		} else {
			planner.Answer(item.ID, installer.DecisionNo)
		}
		m.nextItem()
		if m.item == nil {
			m.state = stateGuideSummary
			return tea.Quit
		}
		return m.rebuildForm()
	}

	if !m.answer {
		planner.Answer(item.ID, installer.DecisionNo)
		m.nextItem()
		if m.item == nil {
			m.state = stateGuideSummary
			return tea.Quit
		}
		return m.rebuildForm()
	}

	// accepted
	planner.Answer(item.ID, installer.DecisionYes)
	m.state = stateGuideExecuting
	return m.execCurrent()
}

func (m *guidedModel) execCurrent() tea.Cmd {
	item := m.item
	if item == nil {
		m.state = stateGuideSummary
		return tea.Quit
	}

	m.setup = nil
	for _, name := range item.Node.Node.Setup {
		if manifest.KnownWorkflows[name] {
			m.setup = append(m.setup, name)
		}
	}
	m.setupIndex = 0
	if len(m.setup) > 0 {
		return m.startWorkflow()
	}

	// regular execution
	return func() tea.Msg {
		r := m.session.Execute(item.ID)
		return stepDoneMsg{itemID: item.ID, result: r}
	}
}

func (m *guidedModel) onStepDone(msg stepDoneMsg) (tea.Model, tea.Cmd) {
	m.results = append(m.results, msg.result)

	if msg.result.Status == installer.StatusFailed {
		m.state = stateGuideFailure
		m.failID = msg.itemID
		m.failMsg = msg.result.Reason
		return m, m.buildFailureForm()
	}

	m.nextItem()
	if m.item == nil {
		m.state = stateGuideSummary
		return m, tea.Quit
	}
	m.state = stateGuidePrompt
	return m, m.rebuildForm()
}

// --- failure handling ---

func (m *guidedModel) buildFailureForm() tea.Cmd {
	m.sel = "retry"
	sel := huh.NewSelect[string]().
		Title(fmt.Sprintf("Failed: %s", m.failMsg)).
		Options(
			huh.NewOption("Retry", "retry"),
			huh.NewOption("Skip", "skip"),
			huh.NewOption("Quit", "quit"),
		).
		Value(&m.sel)
	m.form = huh.NewForm(huh.NewGroup(sel))
	if m.width > 0 {
		m.form = m.form.WithWidth(m.width)
	}
	return m.form.Init()
}

func (m *guidedModel) onFailFormDone() tea.Cmd {
	// Extract value from Select form
	action := m.sel
	return func() tea.Msg {
		return failActionMsg{action: action}
	}
}

func (m *guidedModel) onWorkflowEvent(msg workflowEventMsg) (tea.Model, tea.Cmd) {
	if msg.request != nil {
		m.workflowRequest = msg.request
		m.workflowValue = msg.request.value
		m.workflowConfirm = msg.request.value == "true"
		m.state = stateGuideWorkflowPrompt
		return m, m.buildWorkflowForm(msg.request)
	}
	if msg.err != nil || msg.result == nil || msg.result.Outcome == workflow.OutcomeFailed {
		reason := "workflow failed"
		if msg.err != nil {
			reason = msg.err.Error()
		} else if msg.result != nil {
			reason = msg.result.Reason
		}
		return m, func() tea.Msg {
			return stepDoneMsg{itemID: m.item.ID, result: installer.Result{ItemID: m.item.ID, Status: installer.StatusFailed, Reason: reason}}
		}
	}
	if msg.result.Interactive != nil {
		m.interactiveCmd = msg.result.Interactive
		m.interactiveItem = m.item.ID
		m.state = stateGuideInteractiveCommand
		return m, nil
	}
	if msg.result.Outcome != workflow.OutcomeComplete {
		m.item.Status = installer.StatusPendingSetup
		m.item.Reason = msg.result.Reason
		return m, func() tea.Msg {
			return stepDoneMsg{itemID: m.item.ID, result: installer.Result{ItemID: m.item.ID, Status: installer.StatusPendingSetup, Reason: msg.result.Reason}}
		}
	}
	m.setupIndex++
	return m, m.startWorkflow()
}

func (m *guidedModel) startWorkflow() tea.Cmd {
	if m.setupIndex >= len(m.setup) {
		return func() tea.Msg {
			r := m.session.Execute(m.item.ID)
			return stepDoneMsg{itemID: m.item.ID, result: r}
		}
	}
	events := make(chan workflowEventMsg)
	m.workflowEvents = events
	name := m.setup[m.setupIndex]
	go func() {
		p := &guidedPrompt{requests: events}
		result, err := m.workflowRunner.Run(name, p, guidedCommandRunner{})
		if err != nil {
			events <- workflowEventMsg{err: err}
			return
		}
		events <- workflowEventMsg{result: &result}
	}()
	return m.waitWorkflowEvent()
}

func (m *guidedModel) waitWorkflowEvent() tea.Cmd {
	return func() tea.Msg { return <-m.workflowEvents }
}

func (m *guidedModel) buildWorkflowForm(req *workflowRequest) tea.Cmd {
	var field huh.Field
	switch req.kind {
	case "confirm":
		field = huh.NewConfirm().Title(req.title).Value(&m.workflowConfirm)
	case "input":
		field = huh.NewInput().Title(req.title).Value(&m.workflowValue)
	case "choose":
		options := make([]huh.Option[string], 0, len(req.options))
		for _, option := range req.options {
			options = append(options, huh.NewOption(option, option))
		}
		field = huh.NewSelect[string]().Title(req.title).Options(options...).Value(&m.workflowValue)
	}
	m.form = huh.NewForm(huh.NewGroup(field))
	if m.width > 0 {
		m.form = m.form.WithWidth(m.width)
	}
	return m.form.Init()
}

func (m *guidedModel) onWorkflowFormDone() tea.Cmd {
	answer := workflowAnswer{value: m.workflowValue, ok: m.workflowConfirm}
	if m.workflowRequest.kind != "confirm" {
		answer.ok = true
	}
	m.workflowRequest.answer <- answer
	m.workflowRequest = nil
	m.form = nil
	m.state = stateGuideExecuting
	return m.waitWorkflowEvent()
}

func (m *guidedModel) onFailAction(msg failActionMsg) (tea.Model, tea.Cmd) {
	switch msg.action {
	case "retry":
		m.state = stateGuideExecuting
		return m, m.execCurrent()
	case "skip":
		if m.item != nil {
			m.session.Planner().Answer(m.item.ID, installer.DecisionNo)
		}
		m.nextItem()
		if m.item == nil {
			m.state = stateGuideSummary
			return m, tea.Quit
		}
		m.state = stateGuidePrompt
		return m, m.rebuildForm()
	case "quit":
		m.state = stateGuideSummary
		return m, tea.Quit
	}
	return m, nil
}

// --- interactive command ---

func (m *guidedModel) runInteractiveCmd() tea.Cmd {
	if m.interactiveCmd == nil {
		return func() tea.Msg { return interactiveFinishedMsg{} }
	}
	return tea.ExecProcess(m.interactiveCmd, func(err error) tea.Msg {
		return interactiveFinishedMsg{err: err}
	})
}

type guidedPrompt struct{ requests chan<- workflowEventMsg }

func (p *guidedPrompt) Confirm(title string, defaultYes bool) (bool, error) {
	answer := make(chan workflowAnswer)
	p.requests <- workflowEventMsg{request: &workflowRequest{kind: "confirm", title: title, value: fmt.Sprint(defaultYes), answer: answer}}
	return (<-answer).ok, nil
}
func (p *guidedPrompt) Input(title, value string) (string, error) {
	answer := make(chan workflowAnswer)
	p.requests <- workflowEventMsg{request: &workflowRequest{kind: "input", title: title, value: value, answer: answer}}
	return (<-answer).value, nil
}
func (p *guidedPrompt) Choose(title string, options []string) (string, error) {
	answer := make(chan workflowAnswer)
	p.requests <- workflowEventMsg{request: &workflowRequest{kind: "choose", title: title, options: options, answer: answer}}
	return (<-answer).value, nil
}

type guidedCommandRunner struct{}

func (guidedCommandRunner) Run(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).CombinedOutput()
	return string(out), err
}
func (guidedCommandRunner) LookPath(name string) (string, error) { return exec.LookPath(name) }

func newGuidedWorkflowRunner() *workflow.Runner {
	registry := workflow.NewRegistry()
	registry.Register("git-identity", workflow.GitIdentity)
	registry.Register("github-auth", workflow.GitHubAuth)
	registry.Register("signed-commits", workflow.SignedCommits)
	registry.Register("hunk-git-pager", workflow.HunkGitPager)
	return workflow.NewRunner(registry)
}

// --- views ---

func (m *guidedModel) View() tea.View {
	switch m.state {
	case stateGuidePrompt:
		if m.form != nil {
			return tea.NewView(m.form.View())
		}
		return tea.NewView("")
	case stateGuideExecuting:
		return tea.NewView(m.executingView())
	case stateGuideInteractiveCommand:
		return tea.NewView(m.interactiveView())
	case stateGuideFailure:
		if m.form != nil {
			return tea.NewView(m.form.View())
		}
		return tea.NewView(m.failureView())
	case stateGuideWorkflowPrompt:
		if m.form != nil {
			return tea.NewView(m.form.View())
		}
		return tea.NewView("")
	case stateGuideSummary:
		return m.summaryView()
	}
	return tea.NewView("")
}

func (m *guidedModel) executingView() string {
	var b strings.Builder
	b.WriteString(GuidePromptStyle.Render("Installing..."))
	b.WriteString("\n\n")
	if m.item != nil {
		b.WriteString(GuideExecStyle.Render(fmt.Sprintf("  %s", m.item.Name)))
		b.WriteString("\n")
	}
	b.WriteString(SpinnerStyle.Render("  processing..."))
	b.WriteString("\n")
	return b.String()
}

func (m *guidedModel) interactiveView() string {
	var b strings.Builder
	b.WriteString(GuideInteractiveStyle.Render("Interactive Setup"))
	b.WriteString("\n\n")
	b.WriteString(fmt.Sprintf("  %s\n\n", m.interactiveItem))
	b.WriteString(HelpStyle.Render("  Enter  start interactive process"))
	b.WriteString("\n")
	b.WriteString(HelpStyle.Render("  Esc    skip"))
	b.WriteString("\n")
	return b.String()
}

func (m *guidedModel) failureView() string {
	var b strings.Builder
	b.WriteString(GuideFailureStyle.Render("Installation Failed"))
	b.WriteString("\n\n")
	b.WriteString(ErrorStyle.Render(fmt.Sprintf("  %s: %s", m.failID, m.failMsg)))
	b.WriteString("\n\n")
	return b.String()
}

func (m *guidedModel) summaryView() tea.View {
	var b strings.Builder
	b.WriteString(GuideSummaryStyle.Render("Installation Summary"))
	b.WriteString("\n\n")

	items := m.session.Planner().Summary()

	groups := []struct {
		label string
		items []installer.Item
		st    installer.Status
	}{
		{"Installed", nil, installer.StatusInstalled},
		{"Already Present", nil, installer.StatusAlreadyPresent},
		{"Would Install", nil, installer.StatusWouldInstall},
		{"Declined", nil, installer.StatusDeclined},
		{"Skipped (dependency)", nil, installer.StatusSkippedDependency},
		{"Pending Setup", nil, installer.StatusPendingSetup},
		{"Failed", nil, installer.StatusFailed},
	}

	for i := range groups {
		for _, it := range items {
			if it.Status == groups[i].st {
				groups[i].items = append(groups[i].items, it)
			}
		}
	}

	any := false
	for _, g := range groups {
		if len(g.items) > 0 {
			any = true
			break
		}
	}
	if !any {
		b.WriteString(HelpStyle.Render("  No items processed."))
		b.WriteString("\n\n")
	}

	for _, g := range groups {
		if len(g.items) == 0 {
			continue
		}
		b.WriteString(g.label + ":\n")
		for _, it := range g.items {
			b.WriteString(fmt.Sprintf("  %s  %s\n", statusIcon(it.Status), it.Name))
			if it.Reason != "" {
				b.WriteString(fmt.Sprintf("       %s\n", HelpStyle.Render(it.Reason)))
			}
		}
		b.WriteString("\n")
	}

	b.WriteString(HelpStyle.Render("  Press any key to exit."))
	b.WriteString("\n")
	return tea.NewView(b.String())
}

func statusIcon(st installer.Status) string {
	switch st {
	case installer.StatusInstalled:
		return "\u2713"
	case installer.StatusAlreadyPresent:
		return "\u2022"
	case installer.StatusWouldInstall:
		return "+"
	case installer.StatusDeclined:
		return "\u2013"
	case installer.StatusSkippedDependency:
		return "\u21b7"
	case installer.StatusPendingSetup:
		return "\u25d8"
	case installer.StatusFailed:
		return "\u2717"
	default:
		return "?"
	}
}
