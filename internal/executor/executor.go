package executor

import (
	"os"
	"strings"
	"sync"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/snapshot"
)

var (
	mu             sync.Mutex
	snapshotEntries []snapshot.Entry
)

func ResetSnapshots() {
	mu.Lock()
	defer mu.Unlock()
	snapshotEntries = nil
}

func appendSnapshotEntry(entry snapshot.Entry) {
	mu.Lock()
	defer mu.Unlock()
	snapshotEntries = append(snapshotEntries, entry)
}

func SnapshotEntries() []snapshot.Entry {
	mu.Lock()
	defer mu.Unlock()
	if len(snapshotEntries) == 0 {
		return nil
	}
	out := make([]snapshot.Entry, len(snapshotEntries))
	copy(out, snapshotEntries)
	return out
}

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
	case "defaults":
		return execDefaults(step, expand)
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
