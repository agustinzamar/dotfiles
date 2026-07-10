package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/doctor"
	"github.com/agustinzamar/dotfiles/internal/logger"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var doctorLogFlag bool

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Check health of installed tools and symlinks",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		fmt.Println("Dotfiles Health Check")
		fmt.Println("=====================")

		revOut, _ := exec.Command("git", "-C", dotfilesDir, "rev-parse", "--short", "HEAD").Output()
		rev := strings.TrimSpace(string(revOut))
		status, _ := exec.Command("git", "-C", dotfilesDir, "status", "--porcelain").Output()
		repoState := "up to date"
		if len(status) > 0 {
			repoState = "dirty (uncommitted changes)"
		}
		fmt.Printf("\nRepository: %s (%s)\n", repoState, rev)

		m, err := manifest.Load(dotfilesDir + "/config/tools.yaml")
		if err != nil {
			return err
		}
		vars := config.GetVars()

		okCount := 0
		missingCount := 0
		brokenCount := 0
		unknownCount := 0

		for _, cat := range m.Categories {
			fmt.Printf("\n%s:\n", cat.Name)
			for _, t := range cat.Tools {
				results := []doctor.Result{}
				allOk := true
				for _, step := range t.Steps {
					r := doctor.Check(step, dotfilesDir, vars)
					results = append(results, r)
					if r.Status != "ok" {
						allOk = false
					}
				}

				if allOk {
					fmt.Printf("  \u2713 %s\n", t.Name)
					okCount++
				} else {
					for _, r := range results {
						switch r.Status {
						case "ok":
						case "missing":
							fmt.Printf("  \u2717 %s (%s)\n", t.Name, r.Msg)
							missingCount++
						case "broken":
							fmt.Fprintf(os.Stderr, "  \u26a0 %s (%s)\n", t.Name, r.Msg)
							brokenCount++
						default:
							fmt.Fprintf(os.Stderr, "  ? %s (%s)\n", t.Name, r.Msg)
							unknownCount++
						}
					}
				}
			}
		}

		fmt.Printf("\nSummary: %d ok, %d missing, %d broken", okCount, missingCount, brokenCount)
		if unknownCount > 0 {
			fmt.Printf(", %d unknown", unknownCount)
		}
		fmt.Println()

		if doctorLogFlag {
			printRecentErrors()
		}

		return nil
	},
}

func printRecentErrors() {
	errors := logger.ReadErrors(10)
	if len(errors) == 0 {
		fmt.Println("\nNo recent errors logged.")
		return
	}
	fmt.Printf("\nRecent errors:\n")
	for _, e := range errors {
		fmt.Printf("  %s\n", e)
	}
}

func init() {
	rootCmd.AddCommand(doctorCmd)
	doctorCmd.Flags().BoolVar(&doctorLogFlag, "log", false, "Show recent errors from install log")
}
