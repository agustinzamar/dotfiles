package cmd

import (
	"fmt"
	"os"

	"github.com/agustinzamar/dotfiles/internal/lock"
	"github.com/agustinzamar/dotfiles/internal/logger"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/snapshot"
	"github.com/spf13/cobra"
)

var rollbackCmd = &cobra.Command{
	Use:   "rollback [timestamp]",
	Short: "Restore files from a snapshot",
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		homeDir, err := os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("home dir: %w", err)
		}
		lockObj := lock.New(homeDir + "/.dotfiles/.lock")
		if err := lockObj.Acquire(); err != nil {
			return err
		}
		defer lockObj.Release()

		var m *snapshot.Manifest
		if len(args) == 1 {
			m, err = snapshot.LoadManifest(args[0], dotfilesDir)
			if err != nil {
				return fmt.Errorf("load snapshot %s: %w", args[0], err)
			}
		} else {
			m, err = snapshot.LatestManifest(dotfilesDir)
			if err != nil {
				return fmt.Errorf("no snapshots found: %w", err)
			}
			fmt.Printf("Restoring from snapshot %s\n", m.Timestamp)
		}

		restored := 0
		skipped := 0
		for _, entry := range m.Entries {
			if err := snapshot.Restore(entry); err != nil {
				logger.Log("error", "rollback", fmt.Sprintf("%s: %v", entry.OriginalPath, err))
				fmt.Fprintf(os.Stderr, "  ✗ %s: %v\n", entry.OriginalPath, err)
				continue
			}
			if entry.Action == "skipped" {
				skipped++
			} else {
				restored++
				fmt.Printf("  ✓ %s\n", entry.OriginalPath)
			}
		}
		fmt.Printf("Rollback complete: %d restored, %d skipped\n", restored, skipped)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(rollbackCmd)
}
