package executor

import (
	"os"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

type Result struct {
	Status string
	Msg    string
}

func Run(step manifest.Step, dotfilesDir string, vars map[string]string, dryRun bool) Result {
	expand := func(s string) string {
		s = os.ExpandEnv(s)
		for k, v := range vars {
			s = strings.ReplaceAll(s, "${"+k+"}", v)
		}
		return s
	}

	if dryRun {
		return dryRunStep(step, dotfilesDir, expand)
	}

	switch step.Type {
	case "brew":
		return execBrew(step, expand)
	case "cask":
		return execCask(step, expand)
	case "tap":
		return execTap(step, expand)
	case "vscode":
		return execVSCode(step, expand)
	case "omz-plugin":
		return execOMZPlugin(step, expand)
	case "symlink":
		return execSymlink(step, dotfilesDir, expand)
	case "template-symlink":
		return execTemplateSymlink(step, dotfilesDir, vars, expand)
	case "git-clone":
		return execGitClone(step, expand)
	case "run":
		return execRun(step, expand)
	default:
		return Result{Status: "error", Msg: "unknown step type: " + step.Type}
	}
}

func dryRunStep(step manifest.Step, dotfilesDir string, expand func(string) string) Result {
	if checkSkip(step.Skip, expand) {
		return Result{Status: "would-skip", Msg: step.Package + " already installed"}
	}
	switch step.Type {
	case "symlink", "template-symlink":
		return Result{Status: "would-install", Msg: expand(step.To)}
	default:
		return Result{Status: "would-install", Msg: step.Package + step.Repo + step.Extension + step.Command}
	}
}
