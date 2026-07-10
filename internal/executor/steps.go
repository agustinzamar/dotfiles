package executor

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/symlink"
)

func checkSkip(skipCmd string, expand func(string) string) bool {
	if skipCmd == "" {
		return false
	}
	return exec.Command("sh", "-c", expand(skipCmd)).Run() == nil
}

func execBrew(step manifest.Step, expand func(string) string) Result {
	if checkSkip(step.Skip, expand) {
		return Result{Status: "skipped", Msg: step.Package + " already installed"}
	}
	cmd := exec.Command("brew", "install", step.Package)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("brew install %s: %v", step.Package, err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: step.Package}
}

func execCask(step manifest.Step, expand func(string) string) Result {
	if checkSkip(step.Skip, expand) {
		return Result{Status: "skipped", Msg: step.Package + " already installed"}
	}
	cmd := exec.Command("brew", "install", "--cask", step.Package)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("brew cask install %s: %v", step.Package, err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: step.Package}
}

func execTap(step manifest.Step, expand func(string) string) Result {
	out, _ := exec.Command("brew", "tap").Output()
	if strings.Contains(string(out), step.Repo) {
		return Result{Status: "skipped", Msg: "tap " + step.Repo + " already exists"}
	}
	cmd := exec.Command("brew", "tap", step.Repo)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("tap %s: %v", step.Repo, err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: "tapped " + step.Repo}
}

func execVSCode(step manifest.Step, expand func(string) string) Result {
	out, _ := exec.Command("code", "--list-extensions").Output()
	if strings.Contains(string(out), step.Extension) {
		return Result{Status: "skipped", Msg: step.Extension + " already installed"}
	}
	cmd := exec.Command("code", "--install-extension", step.Extension)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("vscode %s: %v", step.Extension, err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: step.Extension}
}

func execOMZPlugin(step manifest.Step, expand func(string) string) Result {
	name := step.Package
	if name == "" {
		parts := strings.Split(step.Repo, "/")
		name = strings.TrimSuffix(parts[len(parts)-1], ".git")
	}
	dest := expand("${HOME}/.oh-my-zsh/custom/plugins/" + name)
	if _, err := os.Stat(dest); err == nil {
		return Result{Status: "skipped", Msg: name + " plugin already installed"}
	}
	cmd := exec.Command("git", "clone", "--depth=1", step.Repo, dest)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("clone %s: %v", step.Repo, err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: name}
}

func execSymlink(step manifest.Step, dotfilesDir string, expand func(string) string) Result {
	src := filepath.Join(dotfilesDir, step.From)
	dst := expand(step.To)
	if err := symlink.Link(src, dst); err != nil {
		return Result{Status: "error", Msg: fmt.Sprintf("symlink %s: %v", step.To, err)}
	}
	return Result{Status: "installed", Msg: dst}
}

func execTemplateSymlink(step manifest.Step, dotfilesDir string, vars map[string]string, expand func(string) string) Result {
	src := filepath.Join(dotfilesDir, step.From)
	dst := expand(step.To)

	tmplData, err := os.ReadFile(src)
	if err != nil {
		return Result{Status: "error", Msg: fmt.Sprintf("read template %s: %v", src, err)}
	}

	rendered, err := config.Render(string(tmplData), vars)
	if err != nil {
		return Result{Status: "error", Msg: fmt.Sprintf("render template %s: %v", src, err)}
	}

	renderedPath := strings.Replace(src, filepath.Ext(src), ".rendered"+filepath.Ext(src), 1)
	if err := os.WriteFile(renderedPath, []byte(rendered), 0644); err != nil {
		return Result{Status: "error", Msg: fmt.Sprintf("write rendered %s: %v", renderedPath, err)}
	}

	if err := symlink.Link(renderedPath, dst); err != nil {
		return Result{Status: "error", Msg: fmt.Sprintf("symlink %s: %v", dst, err)}
	}
	return Result{Status: "installed", Msg: dst}
}

func execGitClone(step manifest.Step, expand func(string) string) Result {
	dest := expand(step.Dest)
	if _, err := os.Stat(dest); err == nil {
		return Result{Status: "skipped", Msg: dest + " already exists"}
	}
	args := []string{"clone"}
	if step.Depth > 0 {
		args = append(args, fmt.Sprintf("--depth=%d", step.Depth))
	}
	args = append(args, step.Repo, dest)
	cmd := exec.Command("git", args...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("git clone %s: %v", step.Repo, err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: dest}
}

func execRun(step manifest.Step, expand func(string) string) Result {
	if checkSkip(step.Skip, expand) {
		return Result{Status: "skipped", Msg: "already done"}
	}
	cmd := exec.Command("sh", "-c", expand(step.Command))
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if step.Env != nil {
		cmd.Env = os.Environ()
		for k, v := range step.Env {
			cmd.Env = append(cmd.Env, k+"="+v)
		}
	}
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("run: %v", err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: "ok"}
}

func execDefaults(step manifest.Step, expand func(string) string) Result {
	domain := expand(step.Domain)
	key := expand(step.Key)
	value := expand(step.Value)

	out, err := exec.Command("defaults", "read", domain, key).Output()
	if err == nil {
		current := strings.TrimSpace(string(out))
		if current == value {
			return Result{Status: "skipped", Msg: domain + " " + key + " already set"}
		}
	}

	var flag string
	switch step.ValueType {
	case "bool":
		flag = "-bool"
	case "int":
		flag = "-int"
	default:
		flag = "-string"
	}

	cmd := exec.Command("defaults", "write", domain, key, flag, value)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := fmt.Sprintf("defaults write %s %s: %v", domain, key, err)
		if s := stderr.String(); s != "" {
			msg = s
		}
		return Result{Status: "error", Msg: msg}
	}
	return Result{Status: "installed", Msg: domain + " " + key}
}
