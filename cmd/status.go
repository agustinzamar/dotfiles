package cmd

import (
	"fmt"
	"os"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/snapshot"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show snapshot state and what changed since install",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		list, err := snapshot.ListSnapshots(dotfilesDir)
		if err != nil {
			return fmt.Errorf("list snapshots: %w", err)
		}
		if len(list) == 0 {
			fmt.Println("No snapshots — install has not been run with safety mode")
			return nil
		}

		m, err := snapshot.LoadManifest(list[0], dotfilesDir)
		if err != nil {
			return fmt.Errorf("load latest snapshot: %w", err)
		}

		fmt.Printf("Latest snapshot: %s (%d files)\n", m.Timestamp, len(m.Entries))

		changed := 0
		for _, entry := range m.Entries {
			if entry.Action == "skipped" {
				continue
			}
			curHash, err := snapshot.FileHash(entry.OriginalPath)
			if err != nil {
				// File may have been removed
				fmt.Fprintf(os.Stdout, "  ! %s: %v\n", entry.OriginalPath, err)
				changed++
				continue
			}
			if curHash != entry.Hash {
				fmt.Fprintf(os.Stdout, "  ~ %s (changed since install)\n", entry.OriginalPath)
				changed++
			}
		}

		if changed == 0 {
			fmt.Println("No files changed since install")
		} else {
			fmt.Printf("\n%d file(s) changed since install — run 'dotfiles rollback' to restore\n", changed)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(statusCmd)
}
