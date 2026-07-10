package cmd

import (
	"fmt"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var listCategoryFlag string

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all available tools in the manifest",
	RunE: func(cmd *cobra.Command, args []string) error {
		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}

		fmt.Println("Dotfiles Tools")
		fmt.Println("==============")

		total := 0
		for _, cat := range m.Categories {
			if listCategoryFlag != "" && cat.Name != listCategoryFlag {
				continue
			}
			fmt.Printf("\n%s (%d tools)\n", cat.Name, len(cat.Tools))
			for _, t := range cat.Tools {
				mark := "[ ]"
				if t.Checked {
					mark = "[\u2713]"
				}
				fmt.Printf("  %s %-20s %s\n", mark, t.Name, t.Description)
			}
			total += len(cat.Tools)
		}

		fmt.Printf("\n%d tools across %d categories\n", total, len(m.Categories))
		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
	listCmd.Flags().StringVar(&listCategoryFlag, "category", "", "Filter to a single category")
}
