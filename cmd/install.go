package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/lock"
	"github.com/agustinzamar/dotfiles/internal/logger"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/snapshot"
	"github.com/agustinzamar/dotfiles/internal/tui"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var allFlag bool
var allDryRun bool
var profileFlag string
var installApplyFlag bool
var installDiffFlag bool
var installForceFlag bool

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install and configure development tools",
	RunE: func(cmd *cobra.Command, args []string) error {
		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}
		if allFlag || allDryRun {
			return installAll(m)
		}
		p := tea.NewProgram(tui.NewModel(m, profileFlag))
		_, err = p.Run()
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
}

func installAll(m *manifest.Manifest) error {
	vars := config.GetVars()
	dotfilesDir := manifest.DotfilesDir()

	isDryRun := allDryRun
	if !allDryRun && !installApplyFlag {
		isDryRun = true
		fmt.Fprintln(os.Stderr, "Dry-run mode (pass --apply to actually install)")
	}

	if !isDryRun {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("home dir: %w", err)
		}
		lk := lock.New(filepath.Join(homeDir, ".dotfiles", ".lock"))
		if err := lk.Acquire(); err != nil {
			return err
		}
		defer lk.Release()
		executor.ResetSnapshots()
	}

	expand := func(s string) string {
		s = os.ExpandEnv(s)
		for k, v := range vars {
			s = strings.ReplaceAll(s, "${"+k+"}", v)
		}
		return s
	}

	if installDiffFlag && !installForceFlag {
		fmt.Fprintln(os.Stderr, "Planned changes:")
		for _, cat := range m.Categories {
			for _, t := range cat.Tools {
				if profileFlag != "" && !t.MatchesProfile(profileFlag) {
					continue
				}
				for _, step := range t.Steps {
					switch step.Type {
					case "symlink":
						src := filepath.Join(dotfilesDir, step.From)
						dst := expand(step.To)
						currentTarget, _ := os.Readlink(dst)
						if currentTarget != src {
							fmt.Fprintf(os.Stderr, "  symlink %s\n", dst)
							fmt.Fprintf(os.Stderr, "    from: %s\n", currentTarget)
							fmt.Fprintf(os.Stderr, "    to:   %s\n", src)
						}
					case "template-symlink":
						src := filepath.Join(dotfilesDir, step.From)
						dst := expand(step.To)
						currentTarget, _ := os.Readlink(dst)
						if currentTarget != src {
							fmt.Fprintf(os.Stderr, "  template %s\n", dst)
						}
						tmplData, _ := os.ReadFile(src)
						rendered, _ := config.Render(string(tmplData), vars)
						existing, _ := os.ReadFile(dst)
						if string(existing) != rendered {
							fmt.Fprintf(os.Stderr, "    content differs\n")
						}
					default:
						fmt.Fprintf(os.Stderr, "  %s %s\n", step.Type, step.Package+step.Repo+step.Command)
					}
				}
			}
		}
	}

	hadError := false
	for _, cat := range m.Categories {
		fmt.Fprintf(os.Stderr, "\n%s\n", cat.Name)
		for _, t := range cat.Tools {
			if profileFlag != "" && !t.MatchesProfile(profileFlag) {
				continue
			}
			for _, step := range t.Steps {
				if step.Type == "template-symlink" {
					config.PromptMissing(step.Vars)
				}
			}
			vars = config.GetVars()

			fmt.Fprintf(os.Stderr, "  %s...", t.Name)
			allSkipped := true
			for _, step := range t.Steps {
				r := executor.Run(step, dotfilesDir, vars, isDryRun)
				switch r.Status {
				case "installed":
					fmt.Fprint(os.Stderr, " \u2713")
					allSkipped = false
				case "skipped":
					fmt.Fprint(os.Stderr, " \u2022")
				case "would-install":
					fmt.Fprint(os.Stderr, " +")
					allSkipped = false
				case "would-skip":
					fmt.Fprint(os.Stderr, " \u2022")
				case "error":
					fmt.Fprintf(os.Stderr, " \u2717(%s)", r.Msg)
					allSkipped = false
					hadError = true
				}
				logger.Log(r.Status, t.Name, r.Msg)
			}
			if allSkipped {
				fmt.Fprint(os.Stderr, " (already done)")
			}
			fmt.Fprintln(os.Stderr)
		}
	}

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
		return fmt.Errorf("install completed with errors and was rolled back")
	}

	if !isDryRun {
		entries := executor.SnapshotEntries()
		if len(entries) > 0 {
			ts := time.Now().Format("20060102T150405")
			sm := &snapshot.Manifest{Timestamp: ts, Entries: entries}
			if err := snapshot.SaveManifest(sm, dotfilesDir); err != nil {
				logger.Log("error", "snapshot", fmt.Sprintf("save manifest: %v", err))
			}
			if err := snapshot.PruneSnapshots(dotfilesDir, 5); err != nil {
				logger.Log("error", "snapshot", fmt.Sprintf("prune: %v", err))
			}
			fmt.Fprintf(os.Stderr, "\nSnapshot saved: %s (%d files)\n", ts, len(entries))
		}
	}

	fmt.Println("\nDone.")
	return nil
}
