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

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update dotfiles repo, brew packages, and sync symlinks",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		fmt.Println("Pulling latest dotfiles...")
		c1 := exec.Command("git", "-C", dotfilesDir, "pull")
		c1.Stdout = os.Stdout
		c1.Stderr = os.Stderr
		c1.Run()

		fmt.Println("\nUpdating Homebrew...")
		exec.Command("brew", "update").Run()
		exec.Command("brew", "upgrade").Run()

		fmt.Println("\nRe-syncing config symlinks...")
		m, err := manifest.Load(dotfilesDir + "/config/tools.yaml")
		if err != nil {
			return err
		}
		vars := config.GetVars()
		for _, cat := range m.Categories {
			for _, t := range cat.Tools {
				for _, step := range t.Steps {
					executor.Run(step, dotfilesDir, vars, false)
				}
			}
		}
		fmt.Println("Dotfiles updated.")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(updateCmd)
}
