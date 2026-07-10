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

func Run(step manifest.Step, dotfilesDir string, vars map[string]string) Result {
	expand := func(s string) string {
		s = os.ExpandEnv(s)
		for k, v := range vars {
			s = strings.ReplaceAll(s, "${"+k+"}", v)
		}
		return s
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
