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
		for _, result := range installer.Execute(context.Background(), tasks, installer.ShellRunner) {
			fmt.Printf("%s %s: %s\n", result.Status, result.Task.Label, result.Output)
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
	for _, result := range installer.Execute(context.Background(), tasks, installer.ShellRunner) {
		fmt.Printf("%s %s: %s\n", result.Status, result.Task.Label, result.Output)
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
