package tui

import "charm.land/lipgloss/v2"

var (
	TitleStyle       = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7dc4e4")).MarginBottom(1)
	CategoryStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#f5a97f")).MarginTop(1)
	CheckboxStyle    = lipgloss.NewStyle().PaddingLeft(2)
	CursorStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("#a6da95"))
	CheckedStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("#a6da95"))
	UncheckedStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#6e738d"))
	HelpStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("#6e738d"))
	InstallingStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#eed49f"))
	SuccessStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("#a6da95"))
	ErrorStyle       = lipgloss.NewStyle().Foreground(lipgloss.Color("#ed8796"))
	SkipStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("#6e738d"))
	SpinnerStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("#7dc4e4"))
	PromptLabelStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#f5a97f"))

	FeatureStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("#b8c0e0"))
	FeatureCursorStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#c6a0f6"))
	FeatureCheckedStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#a6da95"))
	FeatureBulletStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#6e738d"))
	ExpandIndicatorStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#6e738d"))

	// Guided state machine styles
	GuidePromptStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#c6a0f6")).MarginBottom(1)
	GuideExecStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("#eed49f"))
	GuideInteractiveStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#7dc4e4"))
	GuideFailureStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#ed8796"))
	GuideSummaryStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#a6da95"))
	GuideItemInstalled  = lipgloss.NewStyle().Foreground(lipgloss.Color("#a6da95"))
	GuideItemSkipped    = lipgloss.NewStyle().Foreground(lipgloss.Color("#6e738d"))
	GuideItemDeclined   = lipgloss.NewStyle().Foreground(lipgloss.Color("#f5a97f"))
	GuideItemFailed     = lipgloss.NewStyle().Foreground(lipgloss.Color("#ed8796"))
	GuideItemPending    = lipgloss.NewStyle().Foreground(lipgloss.Color("#eed49f"))
	GuideItemWould      = lipgloss.NewStyle().Foreground(lipgloss.Color("#b8c0e0"))
)
