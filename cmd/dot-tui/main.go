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

type componentResult struct {
	Label  string
	Status string
	Output string
}

func execute(tasks []installer.Task) []componentResult {
	started := map[string]bool{}
	results := installer.ExecuteWithProgress(context.Background(), tasks, installer.ShellRunner, func(task installer.Task) {
		if started[task.ComponentID] {
			return
		}
		started[task.ComponentID] = true
		fmt.Printf("🔧 %s...\n", task.Label)
	})
	return summarize(results)
}

func summarize(results []installer.Result) []componentResult {
	components := make([]componentResult, 0)
	indexes := map[string]int{}
	for _, result := range results {
		id := result.Task.ComponentID
		index, ok := indexes[id]
		if !ok {
			indexes[id] = len(components)
			components = append(components, componentResult{Label: result.Task.Label, Status: result.Status})
			index = len(components) - 1
		}
		component := &components[index]
		switch {
		case result.Status == "failed":
			if component.Status != "failed" {
				component.Output = ""
			}
			component.Status = "failed"
			if result.Output != "" {
				if component.Output != "" {
					component.Output += "\n"
				}
				component.Output += result.Output
			}
		case result.Status == "skipped" && component.Status != "failed":
			component.Status = "skipped"
			component.Output = result.Output
		}
	}
	return components
}

func printResult(result componentResult) {
	switch result.Status {
	case "installed":
		fmt.Printf("✅ %s installed\n", result.Label)
	case "skipped":
		fmt.Printf("⚠️ %s skipped: %s\n", result.Label, result.Output)
	case "failed":
		fmt.Fprintf(os.Stderr, "❌ %s install failed\n", result.Label)
		if result.Output != "" {
			fmt.Fprintln(os.Stderr, result.Output)
		}
	}
}
