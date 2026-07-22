package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/snapshot"
	"github.com/spf13/cobra"
)

var snapshotsCmd = &cobra.Command{
	Use:   "snapshots",
	Short: "List available snapshots",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()
		list, err := snapshot.ListSnapshots(dotfilesDir)
		if err != nil {
			return fmt.Errorf("list snapshots: %w", err)
		}
		if len(list) == 0 {
			fmt.Println("No snapshots found")
			return nil
		}
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
		fmt.Fprintln(w, "TIMESTAMP\tFILES\tACTION")
		for _, ts := range list {
			m, err := snapshot.LoadManifest(ts, dotfilesDir)
			if err != nil {
				fmt.Fprintf(w, "%s\t-\tload error\n", ts)
				continue
			}
			count := len(m.Entries)
			fmt.Fprintf(w, "%s\t%d\trollback %s\n", ts, count, ts)
		}
		w.Flush()
		return nil
	},
}

func init() {
	rootCmd.AddCommand(snapshotsCmd)
}
