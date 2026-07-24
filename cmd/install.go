package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/installer"
	"github.com/agustinzamar/dotfiles/internal/logger"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/snapshot"
	"github.com/agustinzamar/dotfiles/internal/tui"
	"github.com/spf13/cobra"
)

var allFlag bool
var allDryRun bool
var profileFlag string
var installApplyFlag bool
var installDiffFlag bool
var installForceFlag bool
var selectFlag bool

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install and configure development tools",
	RunE: func(cmd *cobra.Command, args []string) error {
		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}

		// Build shared session
		planner := installer.NewPlanner(m, profileFlag)
		dotfilesDir := manifest.DotfilesDir()
		vars := config.GetVars()

		isDryRun := allDryRun
		if !allDryRun && !installApplyFlag {
			isDryRun = true
		}

		homeDir, err := os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("home dir: %w", err)
		}
		lockPath := filepath.Join(homeDir, ".dotfiles", ".lock")

		runner := executor.Runner{}
		session := installer.NewSession(planner, runner, dotfilesDir, vars, isDryRun, lockPath)

		if allFlag || allDryRun {
			return installAll(m, session)
		}

		if selectFlag {
			p := tea.NewProgram(tui.NewSelectModel(m, profileFlag, isDryRun))
			_, err = p.Run()
			return err
		}

		// Guided mode (default)
		p := tea.NewProgram(tui.NewGuidedModel(session, profileFlag))
		_, err = p.Run()
		if closeErr := session.Close(); err == nil {
			err = closeErr
		} else {
			err = errors.Join(err, closeErr)
		}
		return err
	},
}

func init() {
	rootCmd.AddCommand(installCmd)
	installCmd.Flags().BoolVar(&allFlag, "all", false, "Install all tools without TUI prompt")
	installCmd.Flags().BoolVar(&allDryRun, "dry-run", false, "Preview what would be installed without making changes")
	installCmd.Flags().StringVar(&profileFlag, "profile", "", "Profile to filter tools (e.g. personal, work)")
	installCmd.Flags().BoolVar(&installApplyFlag, "apply", false, "Actually perform installation (default is dry-run)")
	installCmd.Flags().BoolVar(&installDiffFlag, "diff", false, "Show file diffs of changes")
	installCmd.Flags().BoolVar(&installForceFlag, "force", false, "Skip confirmation and diff (headless/CI)")
	installCmd.Flags().BoolVar(&selectFlag, "select", false, "Use advanced selection TUI instead of guided mode")
}

func installAll(m *manifest.Manifest, session *installer.Session) error {
	vars := config.GetVars()
	dotfilesDir := manifest.DotfilesDir()
	isDryRun := session.DryRun()

	expand := func(s string) string {
		s = os.ExpandEnv(s)
		for k, v := range vars {
			s = strings.ReplaceAll(s, "${"+k+"}", v)
		}
		return s
	}

	// Diff output (preflight — read from manifest directly)
	if installDiffFlag && !installForceFlag {
		fmt.Fprintln(os.Stderr, "Planned changes:")
		for _, cat := range m.Categories {
			for _, t := range cat.Tools {
				if profileFlag != "" && !t.MatchesProfile(profileFlag) {
					continue
				}
				for _, step := range t.Steps {
					diffStep(step, t.Name, dotfilesDir, expand, vars)
				}
				for _, f := range t.Features {
					if !f.Checked {
						continue
					}
					for _, step := range f.Steps {
						diffStep(step, t.Name+" > "+f.Name, dotfilesDir, expand, vars)
					}
				}
			}
		}
	}

	// Execute planned items via session
	session.Planner().SetAll(installer.DecisionYes)
	hadError := false
	for {
		item := session.Planner().Next()
		if item == nil {
			break
		}
		if item.Decision != installer.DecisionYes {
			// Mark unset items as pending if they have no default
			if item.Decision == installer.DecisionUnset && item.Status == installer.StatusPlanned {
				item.Status = installer.StatusPendingSetup
			}
			continue
		}

		fmt.Fprintf(os.Stderr, "  %s...", item.Name)
		result := session.Execute(item.ID)
		switch result.Status {
		case installer.StatusInstalled:
			fmt.Fprint(os.Stderr, " \u2713")
		case installer.StatusAlreadyPresent:
			fmt.Fprint(os.Stderr, " \u2022")
		case installer.StatusWouldInstall:
			fmt.Fprint(os.Stderr, " +")
		case installer.StatusPendingSetup:
			fmt.Fprint(os.Stderr, " \u25d8(pending setup)")
		case installer.StatusFailed:
			fmt.Fprintf(os.Stderr, " \u2717(%s)", result.Reason)
			hadError = true
		default:
			fmt.Fprint(os.Stderr, " \u2022")
		}
		logger.Log(string(result.Status), item.Name, result.Reason)
		fmt.Fprintln(os.Stderr)
	}

	closeErr := session.Close()

	if hadError && !isDryRun {
		entries := executor.SnapshotEntries()
		if len(entries) > 0 {
			fmt.Fprintf(os.Stderr, "\nErrors occurred. Rolling back %d changes...\n", len(entries))
			for _, entry := range entries {
				if err := snapshot.Restore(entry); err != nil {
					fmt.Fprintf(os.Stderr, "  \u2717 %s: %v\n", entry.OriginalPath, err)
				} else if entry.Action != "skipped" {
					fmt.Fprintf(os.Stderr, "  \u2713 restored %s\n", entry.OriginalPath)
				}
			}
		}
		return errors.Join(fmt.Errorf("install completed with errors and was rolled back"), closeErr)
	}
	if closeErr != nil {
		return closeErr
	}

	// Snapshot handling is done inside session.Close()
	fmt.Println("\nDone.")
	return nil
}

func diffStep(step manifest.Step, label string, dotfilesDir string, expand func(string) string, vars map[string]string) {
	switch step.Type {
	case "symlink":
		src := filepath.Join(dotfilesDir, step.From)
		dst := expand(step.To)
		currentTarget, _ := os.Readlink(dst)
		if currentTarget != src {
			fmt.Fprintf(os.Stderr, "  %s: symlink %s\n", label, dst)
			fmt.Fprintf(os.Stderr, "    from: %s\n", currentTarget)
			fmt.Fprintf(os.Stderr, "    to:   %s\n", src)
		}
	case "template-symlink":
		src := filepath.Join(dotfilesDir, step.From)
		dst := expand(step.To)
		currentTarget, _ := os.Readlink(dst)
		if currentTarget != src {
			fmt.Fprintf(os.Stderr, "  %s: template %s\n", label, dst)
		}
		tmplData, _ := os.ReadFile(src)
		rendered, _ := config.Render(string(tmplData), vars)
		existing, _ := os.ReadFile(dst)
		if string(existing) != rendered {
			fmt.Fprintf(os.Stderr, "    content differs\n")
		}
	default:
		fmt.Fprintf(os.Stderr, "  %s: %s %s\n", label, step.Type, step.Package+step.Repo+step.Command)
	}
}
