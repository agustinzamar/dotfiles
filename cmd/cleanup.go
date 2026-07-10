package cmd

import (
	"fmt"
	"os"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var cleanupDryRun bool

var cleanupCmd = &cobra.Command{
	Use:   "cleanup",
	Short: "Remove .backup files created by symlink operations",
	RunE: func(cmd *cobra.Command, args []string) error {
		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}

		removed := 0
		for _, cat := range m.Categories {
			for _, t := range cat.Tools {
				for _, step := range t.Steps {
					if step.Type != "symlink" && step.Type != "template-symlink" {
						continue
					}
					target := os.ExpandEnv(step.To)
					backup := target + ".backup"
					if _, err := os.Stat(backup); err == nil {
						if cleanupDryRun {
							fmt.Printf("  would remove: %s\n", backup)
						} else {
							if err := os.Remove(backup); err != nil {
								fmt.Fprintf(os.Stderr, "  failed to remove %s: %v\n", backup, err)
								continue
							}
							fmt.Printf("  removed: %s\n", backup)
						}
						removed++
					}
				}
			}
		}

		if removed == 0 {
			fmt.Println("No backup files found.")
		} else {
			action := "removed"
			if cleanupDryRun {
				action = "would be removed"
			}
			fmt.Printf("\n%d backup file(s) %s.\n", removed, action)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(cleanupCmd)
	cleanupCmd.Flags().BoolVar(&cleanupDryRun, "dry-run", false, "Preview without removing")
}
