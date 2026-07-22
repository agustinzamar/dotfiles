package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/symlink"
	"github.com/spf13/cobra"
)

var reconcileDryRun bool

func runReconcile() error {
	dotfilesDir := manifest.DotfilesDir()

	m, err := manifest.Load(dotfilesDir + "/config/tools.yaml")
	if err != nil {
		return err
	}
	vars := config.GetVars()

	revOut, _ := exec.Command("git", "-C", dotfilesDir, "rev-parse", "--short", "HEAD").Output()
	rev := strings.TrimSpace(string(revOut))
	fmt.Printf("Dotfiles repo: %s (%s)\n", dotfilesDir, rev)

	expand := func(s string) string {
		s = os.ExpandEnv(s)
		for k, v := range vars {
			s = strings.ReplaceAll(s, "${"+k+"}", v)
		}
		return s
	}

	fixed := 0
	skipped := 0

	for _, cat := range m.Categories {
		fmt.Printf("\n%s:\n", cat.Name)
		for _, t := range cat.Tools {
			toolFixed := 0
			hasSymlink := false
			for _, step := range t.Steps {
				if step.Type != "symlink" && step.Type != "template-symlink" {
					continue
				}
				hasSymlink = true
				if step.Type == "template-symlink" {
					config.PromptMissing(step.Vars)
				}
				vars = config.GetVars()

				r := symlink.Reconcile(step, dotfilesDir, vars, expand)
				if !r.Repaired {
					continue
				}
				if reconcileDryRun {
					fmt.Printf("  [dry-run] %s (%s)\n", t.Name, r.Msg)
				} else {
					fmt.Printf("  %s (%s)\n", t.Name, r.Msg)
				}
				toolFixed++
				fixed++
			}
			if hasSymlink && toolFixed == 0 {
				fmt.Printf("  %s (ok)\n", t.Name)
			}
			skipped++
		}
	}

	fmt.Printf("\nSummary: %d fixed, %d tools checked", fixed, skipped)
	fmt.Println()

	if reconcileDryRun {
		fmt.Println("\nDry-run: no changes made (pass without --dry-run to apply)")
	}

	return nil
}

var reconcileCmd = &cobra.Command{
	Use:   "reconcile",
	Short: "Repair broken or stale symlinks against current manifest",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runReconcile()
	},
}

var doctorReconcileCmd = &cobra.Command{
	Use:   "reconcile",
	Short: "Repair broken or stale symlinks against current manifest",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runReconcile()
	},
}

func init() {
	rootCmd.AddCommand(reconcileCmd)
	reconcileCmd.Flags().BoolVar(&reconcileDryRun, "dry-run", false, "Show what would be reconciled without making changes")

	doctorCmd.AddCommand(doctorReconcileCmd)
	doctorReconcileCmd.Flags().BoolVar(&reconcileDryRun, "dry-run", false, "Show what would be reconciled without making changes")
}
