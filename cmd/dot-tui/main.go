package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	tea "charm.land/bubbletea/v2"
	"dotfiles/internal/installer"
)

func main() {
	profilePath := flag.String("profile", "", "profile path")
	apply := flag.Bool("apply", false, "apply profile")
	dryRun := flag.Bool("dry-run", false, "plan only")
	flag.Parse()
	if *profilePath != "" {
		profile, err := installer.LoadProfile(*profilePath)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		tasks, skips, err := installer.Plan(profile, installer.DetectEnvironment())
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		for _, skip := range skips {
			fmt.Printf("skip %s: %s\n", skip.ComponentID, skip.Reason)
		}
		for _, task := range tasks {
			fmt.Printf("%s: %s\n", task.Label, task.Operation)
		}
		if *dryRun || !*apply {
			return
		}
		failed := false
		for _, result := range installer.Execute(context.Background(), tasks, installer.ShellRunner) {
			fmt.Printf("%s %s: %s\n", result.Status, result.Task.Label, result.Output)
			failed = failed || result.Status == "failed"
		}
		if err := installer.SaveProfile(*profilePath, profile); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if failed {
			os.Exit(1)
		}
		return
	}
	if _, err := tea.NewProgram(installer.NewModel()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
