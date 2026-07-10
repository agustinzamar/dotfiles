package cmd

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var updateContinueFlag bool

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update dotfiles repo, brew packages, and sync symlinks",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		fmt.Println("Pulling latest dotfiles...")
		c1 := exec.Command("git", "-C", dotfilesDir, "pull")
		c1.Stdout = os.Stdout
		c1.Stderr = os.Stderr
		if err := c1.Run(); err != nil {
			msg := fmt.Sprintf("git pull failed: %v", err)
			if !updateContinueFlag {
				return fmt.Errorf("%s", msg)
			}
			fmt.Fprintf(os.Stderr, "  %s\n", msg)
		}

		fmt.Println("\nUpdating Homebrew...")
		if err := exec.Command("brew", "update").Run(); err != nil {
			msg := fmt.Sprintf("brew update failed: %v", err)
			if !updateContinueFlag {
				return fmt.Errorf("%s", msg)
			}
			fmt.Fprintf(os.Stderr, "  %s\n", msg)
		}
		if err := exec.Command("brew", "upgrade").Run(); err != nil {
			msg := fmt.Sprintf("brew upgrade failed: %v", err)
			if !updateContinueFlag {
				return fmt.Errorf("%s", msg)
			}
			fmt.Fprintf(os.Stderr, "  %s\n", msg)
		}

		fmt.Println("\nRe-syncing config symlinks...")
		m, err := manifest.Load(dotfilesDir + "/config/tools.yaml")
		if err != nil {
			if !updateContinueFlag {
				return fmt.Errorf("load manifest: %w", err)
			}
			fmt.Fprintf(os.Stderr, "  load manifest failed: %v\n", err)
		}

		if m != nil {
			vars := config.GetVars()
			for _, cat := range m.Categories {
				for _, t := range cat.Tools {
					for _, step := range t.Steps {
						executor.Run(step, dotfilesDir, vars, false)
					}
				}
			}
		}

		fmt.Println("Dotfiles updated.")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(updateCmd)
	updateCmd.Flags().BoolVar(&updateContinueFlag, "continue", false, "Continue past errors instead of stopping")
}
