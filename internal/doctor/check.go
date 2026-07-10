package doctor

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

type Result struct {
	Status string
	Msg    string
}

func Check(step manifest.Step, dotfilesDir string, vars map[string]string) Result {
	expand := func(s string) string {
		s = os.ExpandEnv(s)
		for k, v := range vars {
			s = strings.ReplaceAll(s, "${"+k+"}", v)
		}
		return s
	}

	switch step.Type {
	case "brew", "cask":
		return checkSkip(step, expand, "missing")
	case "tap":
		return checkTap(step, expand)
	case "vscode":
		return checkVSCode(step, expand)
	case "omz-plugin":
		return checkOMZPlugin(step, expand)
	case "symlink":
		return checkSymlink(step, dotfilesDir, expand)
	case "template-symlink":
		return checkTemplateSymlink(step, dotfilesDir, vars, expand)
	case "git-clone":
		return checkGitClone(step, expand)
	case "run":
		return checkSkip(step, expand, "missing")
	case "defaults":
		return checkDefaults(step, expand)
	default:
		return Result{Status: "unknown", Msg: "unknown step type: " + step.Type}
	}
}

func checkSkip(step manifest.Step, expand func(string) string, missingStatus string) Result {
	if step.Skip == "" {
		return Result{Status: "unknown", Msg: "no skip check defined"}
	}
	if exec.Command("sh", "-c", expand(step.Skip)).Run() == nil {
		return Result{Status: "ok", Msg: step.Package}
	}
	return Result{Status: missingStatus, Msg: step.Package + " not found"}
}

func checkTap(step manifest.Step, expand func(string) string) Result {
	out, _ := exec.Command("brew", "tap").Output()
	if strings.Contains(string(out), step.Repo) {
		return Result{Status: "ok", Msg: step.Repo}
	}
	return Result{Status: "missing", Msg: step.Repo + " not tapped"}
}

func checkVSCode(step manifest.Step, expand func(string) string) Result {
	out, _ := exec.Command("code", "--list-extensions").Output()
	if strings.Contains(string(out), step.Extension) {
		return Result{Status: "ok", Msg: step.Extension}
	}
	return Result{Status: "missing", Msg: step.Extension + " not installed"}
}

func checkOMZPlugin(step manifest.Step, expand func(string) string) Result {
	name := step.Package
	if name == "" {
		parts := strings.Split(step.Repo, "/")
		name = strings.TrimSuffix(parts[len(parts)-1], ".git")
	}
	dest := expand("${HOME}/.oh-my-zsh/custom/plugins/" + name)
	if _, err := os.Stat(dest); err == nil {
		return Result{Status: "ok", Msg: name}
	}
	return Result{Status: "missing", Msg: name + " plugin not found"}
}

func checkSymlink(step manifest.Step, dotfilesDir string, expand func(string) string) Result {
	expectedSrc := filepath.Join(dotfilesDir, step.From)
	dst := expand(step.To)
	linkTarget, err := os.Readlink(dst)
	if err != nil {
		if _, lstatErr := os.Lstat(dst); lstatErr == nil {
			return Result{Status: "broken", Msg: dst + " exists but is not a symlink"}
		}
		return Result{Status: "missing", Msg: dst + " not symlinked"}
	}
	if linkTarget == expectedSrc {
		return Result{Status: "ok", Msg: dst}
	}
	return Result{Status: "broken", Msg: dst + " -> " + linkTarget + " (expected " + expectedSrc + ")"}
}

func checkTemplateSymlink(step manifest.Step, dotfilesDir string, vars map[string]string, expand func(string) string) Result {
	for _, key := range step.Vars {
		if vars[key] == "" {
			return Result{Status: "missing", Msg: "template var " + key + " not set"}
		}
	}
	return checkSymlink(step, dotfilesDir, expand)
}

func checkGitClone(step manifest.Step, expand func(string) string) Result {
	dest := expand(step.Dest)
	if _, err := os.Stat(dest); err == nil {
		return Result{Status: "ok", Msg: dest}
	}
	return Result{Status: "missing", Msg: dest + " not cloned"}
}

func checkDefaults(step manifest.Step, expand func(string) string) Result {
	if step.Domain == "" || step.Key == "" {
		return Result{Status: "unknown", Msg: "defaults step missing domain/key"}
	}
	out, err := exec.Command("defaults", "read", step.Domain, step.Key).Output()
	if err != nil {
		return Result{Status: "missing", Msg: step.Domain + " " + step.Key + " not set"}
	}
	current := strings.TrimSpace(string(out))
	expected := expand(step.Value)
	if current == expected {
		return Result{Status: "ok", Msg: step.Domain + " " + step.Key}
	}
	return Result{Status: "broken", Msg: step.Domain + " " + step.Key + " = " + current + " (expected " + expected + ")"}
}
