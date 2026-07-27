package tui

import "charm.land/lipgloss/v2"

var (
	HelpStyle             = lipgloss.NewStyle().Foreground(lipgloss.Color("#6e738d"))
	ErrorStyle            = lipgloss.NewStyle().Foreground(lipgloss.Color("#ed8796"))
	SpinnerStyle          = lipgloss.NewStyle().Foreground(lipgloss.Color("#7dc4e4"))
	GuidePromptStyle      = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#c6a0f6")).MarginBottom(1)
	GuideExecStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("#eed49f"))
	GuideInteractiveStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#7dc4e4"))
	GuideFailureStyle     = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#ed8796"))
	GuideSummaryStyle     = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#a6da95"))
)
