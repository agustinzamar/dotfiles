package installer

import (
	"context"
	"os/exec"
	"strings"
	"time"
)

type Task struct {
	ComponentID  string
	Label        string
	Operation    string
	Dependencies []string
}

type Skip struct {
	ComponentID string
	Reason      string
}

type Result struct {
	Task     Task
	Status   string
	Output   string
	Started  time.Time
	Finished time.Time
}

type Environment struct {
	Commands map[string]bool
}

func DetectEnvironment() Environment {
	commands := make(map[string]bool)
	for _, name := range []string{"brew", "xcode-select", "git", "gh", "code", "php", "composer", "opencode"} {
		_, err := exec.LookPath(name)
		commands[name] = err == nil
	}
	return Environment{Commands: commands}
}

type Runner func(context.Context, string) (string, error)

func ShellRunner(ctx context.Context, command string) (string, error) {
	output, err := exec.CommandContext(ctx, "sh", "-c", command).CombinedOutput()
	return string(output), err
}

func Plan(profile Profile, env Environment) ([]Task, []Skip, error) {
	ordered := make([]Component, 0, len(Components()))
	visiting, visited := map[string]bool{}, map[string]bool{}
	var add func(Component)
	add = func(component Component) {
		if visited[component.ID] || visiting[component.ID] {
			return
		}
		visiting[component.ID] = true
		for _, dependency := range component.Dependencies {
			for _, candidate := range Components() {
				if candidate.ID == dependency {
					add(candidate)
				}
			}
		}
		visiting[component.ID] = false
		visited[component.ID] = true
		ordered = append(ordered, component)
	}
	for _, component := range Components() {
		if profile.Components[component.ID] {
			add(component)
		}
	}

	var tasks []Task
	var skips []Skip
	for _, component := range ordered {
		for _, command := range component.Commands {
			if strings.HasPrefix(command, "brew ") && !env.Commands["brew"] {
				skips = append(skips, Skip{ComponentID: component.ID, Reason: "Homebrew is not installed"})
				break
			}
			tasks = append(tasks, Task{ComponentID: component.ID, Label: component.Label, Operation: command, Dependencies: component.Dependencies})
		}
	}
	return tasks, skips, nil
}

func Execute(ctx context.Context, tasks []Task, run Runner) []Result {
	results := make([]Result, 0, len(tasks))
	failed := map[string]bool{}
	for _, task := range tasks {
		started := time.Now()
		blocked := false
		for _, dependency := range task.Dependencies {
			if failed[dependency] {
				blocked = true
				break
			}
		}
		if blocked {
			results = append(results, Result{Task: task, Status: "skipped", Output: "dependency failed", Started: started, Finished: time.Now()})
			continue
		}
		if ctx.Err() != nil {
			results = append(results, Result{Task: task, Status: "skipped", Output: "cancelled", Started: started, Finished: time.Now()})
			continue
		}
		output, err := run(ctx, task.Operation)
		status := "installed"
		if err != nil {
			status = "failed"
			failed[task.ComponentID] = true
		}
		results = append(results, Result{Task: task, Status: status, Output: output, Started: started, Finished: time.Now()})
	}
	return results
}
