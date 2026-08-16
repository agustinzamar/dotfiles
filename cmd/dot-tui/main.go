package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	tea "charm.land/bubbletea/v2"
	"dotfiles/internal/installer"
)

func main() {
	flagProfilePath := flag.String("profile", "", "profile path")
	apply := flag.Bool("apply", false, "apply profile")
	dryRun := flag.Bool("dry-run", false, "plan only")
	flag.Parse()
	if *flagProfilePath != "" {
		profile, err := installer.LoadProfile(*flagProfilePath)
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
		for _, result := range execute(tasks) {
			printResult(result)
			failed = failed || result.Status == "failed"
		}
		if err := installer.SaveProfile(*flagProfilePath, profile); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if failed {
			os.Exit(1)
		}
		return
	}
	finalModel, err := tea.NewProgram(installer.NewModel()).Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	model, ok := finalModel.(installer.Model)
	if !ok || !model.Submitted() {
		return
	}

	configPath := os.Getenv("XDG_CONFIG_HOME")
	if configPath == "" {
		configPath = filepath.Join(os.Getenv("HOME"), ".config")
	}
	profilePath := filepath.Join(configPath, "dot", "profile.json")
	profile := model.Profile()
	tasks, skips, err := installer.Plan(profile, installer.DetectEnvironment())
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	for _, skip := range skips {
		fmt.Printf("skip %s: %s\n", skip.ComponentID, skip.Reason)
	}
	failed := false
	for _, result := range execute(tasks) {
		printResult(result)
		failed = failed || result.Status == "failed"
	}
	if err := installer.SaveProfile(profilePath, profile); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if failed {
		os.Exit(1)
	}
}

func execute(tasks []installer.Task) []installer.Result {
	return installer.ExecuteWithProgress(context.Background(), tasks, installer.ShellRunner, func(task installer.Task) {
		fmt.Printf("🔧 %s...\n", task.Label)
	})
}

func printResult(result installer.Result) {
	switch result.Status {
	case "installed":
		fmt.Printf("✅ %s installed\n", result.Task.Label)
	case "skipped":
		fmt.Printf("⚠️ %s skipped: %s\n", result.Task.Label, result.Output)
	case "failed":
		fmt.Fprintf(os.Stderr, "❌ %s install failed\n", result.Task.Label)
		if result.Output != "" {
			fmt.Fprintln(os.Stderr, result.Output)
		}
	}
}
