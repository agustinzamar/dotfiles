package cmd

import (
	"fmt"
	"os"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/tui"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var allFlag bool
var allDryRun bool

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install and configure development tools",
	RunE: func(cmd *cobra.Command, args []string) error {
		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}
		if allFlag {
			return installAll(m)
		}
		p := tea.NewProgram(tui.NewModel(m), tea.WithAltScreen())
		_, err = p.Run()
		return err
	},
}

func init() {
	rootCmd.AddCommand(installCmd)
	installCmd.Flags().BoolVar(&allFlag, "all", false, "Install all tools without TUI prompt")
	installCmd.Flags().BoolVar(&allDryRun, "dry-run", false, "Preview what would be installed without making changes")
}

func installAll(m *manifest.Manifest) error {
	vars := config.GetVars()
	dotfilesDir := manifest.DotfilesDir()
	for _, cat := range m.Categories {
		fmt.Fprintf(os.Stderr, "\n%s\n", cat.Name)
		for _, t := range cat.Tools {
			for _, step := range t.Steps {
				if step.Type == "template-symlink" {
					config.PromptMissing(step.Vars)
				}
			}
			vars = config.GetVars()

			fmt.Fprintf(os.Stderr, "  %s...", t.Name)
			allSkipped := true
			for _, step := range t.Steps {
				r := executor.Run(step, dotfilesDir, vars, allDryRun)
				switch r.Status {
				case "installed":
					fmt.Print(" \u2713")
					allSkipped = false
				case "skipped":
					fmt.Print(" \u2022")
				case "would-install":
					fmt.Print(" +")
					allSkipped = false
				case "would-skip":
					fmt.Print(" \u2022")
				case "error":
					fmt.Fprintf(os.Stderr, " \u2717(%s)", r.Msg)
					allSkipped = false
				}
			}
			if allSkipped {
				fmt.Print(" (already done)")
			}
			fmt.Println()
		}
	}
	fmt.Println("\nDone.")
	return nil
}
