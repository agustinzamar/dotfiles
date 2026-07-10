# Dotfiles Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `doctor`, `list`, `--dry-run` commands; fix error swallowing in `update`; fix `vars.json` permissions; add logging, backup cleanup, macOS defaults, TUI progress spinner; add LICENSE and CI.

**Architecture:** New Cobra subcommands (`list`, `doctor`, `cleanup`) wired into `cmd/`. New internal packages: `doctor` (health checks), `logger` (file logging). Executor gains a `dryRun` mode and a `defaults` step type. TUI gains spinner-based per-step progress. Manifest gains `defaults` step fields.

**Tech Stack:** Go 1.26, Cobra, Bubble Tea + Bubbles (spinner), Lipgloss, YAML v3.

## Global Constraints

- Go 1.26.5 (per `go.mod`)
- macOS-only (tests use `brew`, `code`, macOS paths, `defaults` command)
- Follow existing code conventions: no comments, terse style, `internal/` packages
- All new step types must be idempotent and have skip checks
- Tests must pass: `go test ./...`
- Build must pass: `go build -o dotfiles .`

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `LICENSE` | MIT license text | Create |
| `.github/workflows/test.yml` | CI workflow | Create |
| `internal/config/vars.go` | Template var storage — fix perms | Modify |
| `cmd/list.go` | `list` subcommand — print manifest | Create |
| `cmd/doctor.go` | `doctor` subcommand — health check | Create |
| `cmd/cleanup.go` | `cleanup` subcommand — remove `.backup` files | Create |
| `cmd/install.go` | Add `--dry-run` flag | Modify |
| `cmd/update.go` | Error propagation | Modify |
| `internal/logger/logger.go` | File logger | Create |
| `internal/logger/logger_test.go` | Logger tests | Create |
| `internal/doctor/check.go` | Health check logic per step type | Create |
| `internal/doctor/check_test.go` | Doctor tests | Create |
| `internal/executor/executor.go` | Add `dryRun` param | Modify |
| `internal/executor/steps.go` | Add `defaults` step, dry-run paths | Modify |
| `internal/executor/executor_test.go` | Add defaults + dry-run tests | Modify |
| `internal/manifest/manifest.go` | Add `defaults` fields to `Step` | Modify |
| `internal/symlink/symlink.go` | Return backup info | Modify |
| `internal/symlink/symlink_test.go` | Test backup return | Modify |
| `internal/tui/model.go` | Spinner, per-step progress | Modify |
| `internal/tui/styles.go` | Spinner/progress styles | Modify |
| `config/tools.yaml` | Add macOS Defaults category | Modify |
| `go.mod` / `go.sum` | Add `bubbles/spinner` dep | Modify |

---

## Task 1: Fix vars.json Permissions

**Files:**
- Modify: `internal/config/vars.go:48`

**Interfaces:**
- Produces: `SaveVars` now writes with `0600` and `chmod`s existing files

- [ ] **Step 1: Write the failing test**

Create `internal/config/vars_test.go`:

```go
package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSaveVars_FilePermissions(t *testing.T) {
	dir := t.TempDir()
	home := os.Getenv("HOME")
	os.Setenv("HOME", dir)
	defer os.Setenv("HOME", home)

	varsCachePath = filepath.Join(dir, ".dotfiles-custom", "vars.json")

	vars := map[string]string{"TestKey": "test-value"}
	if err := SaveVars(vars); err != nil {
		t.Fatalf("SaveVars failed: %v", err)
	}

	info, err := os.Stat(varsCachePath)
	if err != nil {
		t.Fatalf("Stat failed: %v", err)
	}
	perm := info.Mode().Perm()
	if perm != 0600 {
		t.Fatalf("expected 0600, got %o", perm)
	}
}

func TestSaveVars_OverwriteFixesExistingPerms(t *testing.T) {
	dir := t.TempDir()
	home := os.Getenv("HOME")
	os.Setenv("HOME", dir)
	defer os.Setenv("HOME", home)

	varsCachePath = filepath.Join(dir, ".dotfiles-custom", "vars.json")

	if err := SaveVars(map[string]string{"A": "b"}); err != nil {
		t.Fatalf("first SaveVars failed: %v", err)
	}
	if err := os.Chmod(varsCachePath, 0644); err != nil {
		t.Fatalf("chmod to 0644 failed: %v", err)
	}

	if err := SaveVars(map[string]string{"C": "d"}); err != nil {
		t.Fatalf("second SaveVars failed: %v", err)
	}

	info, err := os.Stat(varsCachePath)
	if err != nil {
		t.Fatalf("Stat failed: %v", err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("expected 0600 after overwrite, got %o", info.Mode().Perm())
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/config/ -run TestSaveVars -v`
Expected: FAIL — perms are `0644`, not `0600`

- [ ] **Step 3: Write minimal implementation**

In `internal/config/vars.go`, replace the `SaveVars` function:

```go
func SaveVars(vars map[string]string) error {
	os.MkdirAll(filepath.Dir(varsCachePath), 0755)
	data, _ := json.MarshalIndent(vars, "", "  ")
	if err := os.WriteFile(varsCachePath, data, 0600); err != nil {
		return err
	}
	return os.Chmod(varsCachePath, 0600)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/config/ -run TestSaveVars -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/config/vars.go internal/config/vars_test.go
git commit -m "fix: write vars.json with 0600 perms

GitHubPAT stored in vars.json was world-readable (0644).
Change to 0600 and chmod on every write to fix existing files."
```

---

## Task 2: List Command

**Files:**
- Create: `cmd/list.go`
- Modify: `cmd/root.go` (no change needed — `init()` auto-registers)

**Interfaces:**
- Consumes: `manifest.Load`, `manifest.Manifest`
- Produces: `listCmd` registered via `init()`

- [ ] **Step 1: Write the implementation**

Create `cmd/list.go`:

```go
package cmd

import (
	"fmt"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var listCategoryFlag string

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all available tools in the manifest",
	RunE: func(cmd *cobra.Command, args []string) error {
		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}

		fmt.Println("Dotfiles Tools")
		fmt.Println("==============")

		total := 0
		for _, cat := range m.Categories {
			if listCategoryFlag != "" && cat.Name != listCategoryFlag {
				continue
			}
			fmt.Printf("\n%s (%d tools)\n", cat.Name, len(cat.Tools))
			for _, t := range cat.Tools {
				mark := "[ ]"
				if t.Checked {
					mark = "[\u2713]"
				}
				fmt.Printf("  %s %-20s %s\n", mark, t.Name, t.Description)
			}
			total += len(cat.Tools)
		}

		fmt.Printf("\n%d tools across %d categories\n", total, len(m.Categories))
		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
	listCmd.Flags().StringVar(&listCategoryFlag, "category", "", "Filter to a single category")
}
```

- [ ] **Step 2: Build and verify**

Run: `go build -o dotfiles . && ./dotfiles list`
Expected: prints all tools grouped by category with checkmarks

- [ ] **Step 3: Test the category filter**

Run: `./dotfiles list --category "CLI Tools"`
Expected: prints only the CLI Tools category

- [ ] **Step 4: Run existing tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add cmd/list.go
git commit -m "feat: add list command

Prints all tools from manifest grouped by category with
checked/unchecked indicators. --category flag filters."
```

---

## Task 3: Dry-Run Flag

**Files:**
- Modify: `cmd/install.go`
- Modify: `internal/executor/executor.go`
- Modify: `internal/executor/steps.go`
- Modify: `internal/executor/executor_test.go`

**Interfaces:**
- Consumes: existing `Run` function
- Produces: `Run` gains `dryRun bool` parameter; returns `{Status: "would-install"}` or `{Status: "would-skip"}` when dry-running

- [ ] **Step 1: Write the failing tests**

Append to `internal/executor/executor_test.go`:

```go
func TestDryRunBrewWouldInstall(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "nonexistent-package-xyz",
		Skip:    "which nonexistent-package-xyz",
	}
	result := Run(step, "", nil, true)
	if result.Status != "would-install" {
		t.Fatalf("expected would-install, got %s: %s", result.Status, result.Msg)
	}
}

func TestDryRunBrewWouldSkip(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "go",
		Skip:    "which go",
	}
	result := Run(step, "", nil, true)
	if result.Status != "would-skip" {
		t.Fatalf("expected would-skip, got %s: %s", result.Status, result.Msg)
	}
}
```

Also update existing tests to pass `false` for the new `dryRun` parameter. Every call to `Run(step, dir, vars)` becomes `Run(step, dir, vars, false)`. Every call to `execBrew(step, expand)` etc. stays unchanged (internal fns don't get the param).

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/executor/ -run TestDryRun -v`
Expected: FAIL — `Run` signature mismatch

- [ ] **Step 3: Update executor to support dry-run**

In `internal/executor/executor.go`, replace the `Run` function:

```go
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
```

- [ ] **Step 4: Update all callers of `Run`**

In `cmd/install.go`, update all calls:
- `executor.Run(step, dotfilesDir, vars)` → `executor.Run(step, dotfilesDir, vars, allDryRun)`
- Add `allDryRun bool` flag alongside `allFlag`

In `cmd/install.go` add the flag:

```go
var allDryRun bool
```

In the `init()` function:

```go
installCmd.Flags().BoolVar(&allDryRun, "dry-run", false, "Preview what would be installed without making changes")
```

In `installAll`, pass `allDryRun` to `Run`. Update the status switch to handle `"would-install"` and `"would-skip"`:

```go
switch r.Status {
case "installed":
	fmt.Print(" \u2713")
	allSkipped = false
case "skipped":
	fmt.Print(" \u2022")
case "would-install":
	fmt.Print(" +")
	allSkipped = false
case "would-skip":
	fmt.Print(" \u2022")
case "error":
	fmt.Fprintf(os.Stderr, " \u2717(%s)", r.Msg)
	allSkipped = false
}
```

In `cmd/update.go`, update the `Run` call to pass `false`:
- `executor.Run(step, dotfilesDir, vars)` → `executor.Run(step, dotfilesDir, vars, false)`

In `internal/tui/model.go`, update the `Run` call in `installNextCmd`:
- `executor.Run(step, dotfilesDir, m.vars)` → `executor.Run(step, dotfilesDir, m.vars, false)`

- [ ] **Step 5: Run all tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 6: Build and verify dry-run**

Run: `go build -o dotfiles . && ./dotfiles install --all --dry-run`
Expected: prints `+` for would-install, `•` for would-skip, no actual installs

- [ ] **Step 7: Commit**

```bash
git add cmd/install.go cmd/update.go internal/executor/executor.go internal/executor/steps.go internal/executor/executor_test.go internal/tui/model.go
git commit -m "feat: add --dry-run flag to install

Preview install plan without making changes. Prints + for
would-install, • for would-skip. Works with --all."
```

---

## Task 4: Error Propagation in update.go

**Files:**
- Modify: `cmd/update.go`

**Interfaces:**
- Consumes: none new
- Produces: `update` returns errors instead of swallowing them

- [ ] **Step 1: Write the implementation**

Replace `cmd/update.go` entirely:

```go
package cmd

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var updateContinueFlag bool

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update dotfiles repo, brew packages, and sync symlinks",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		fmt.Println("Pulling latest dotfiles...")
		c1 := exec.Command("git", "-C", dotfilesDir, "pull")
		c1.Stdout = os.Stdout
		c1.Stderr = os.Stderr
		if err := c1.Run(); err != nil {
			msg := fmt.Sprintf("git pull failed: %v", err)
			if !updateContinueFlag {
				return fmt.Errorf(msg)
			}
			fmt.Fprintf(os.Stderr, "  %s\n", msg)
		}

		fmt.Println("\nUpdating Homebrew...")
		if err := exec.Command("brew", "update").Run(); err != nil {
			msg := fmt.Sprintf("brew update failed: %v", err)
			if !updateContinueFlag {
				return fmt.Errorf(msg)
			}
			fmt.Fprintf(os.Stderr, "  %s\n", msg)
		}
		if err := exec.Command("brew", "upgrade").Run(); err != nil {
			msg := fmt.Sprintf("brew upgrade failed: %v", err)
			if !updateContinueFlag {
				return fmt.Errorf(msg)
			}
			fmt.Fprintf(os.Stderr, "  %s\n", msg)
		}

		fmt.Println("\nRe-syncing config symlinks...")
		m, err := manifest.Load(dotfilesDir + "/config/tools.yaml")
		if err != nil {
			if !updateContinueFlag {
				return fmt.Errorf("load manifest: %w", err)
			}
			fmt.Fprintf(os.Stderr, "  load manifest failed: %v\n", err)
		}

		if m != nil {
			vars := config.GetVars()
			for _, cat := range m.Categories {
				for _, t := range cat.Tools {
					for _, step := range t.Steps {
						executor.Run(step, dotfilesDir, vars, false)
					}
				}
			}
		}

		fmt.Println("Dotfiles updated.")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(updateCmd)
	updateCmd.Flags().BoolVar(&updateContinueFlag, "continue", false, "Continue past errors instead of stopping")
}
```

- [ ] **Step 2: Build and verify**

Run: `go build -o dotfiles .`
Expected: compiles

- [ ] **Step 3: Run all tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add cmd/update.go
git commit -m "fix: propagate errors in update command

git pull, brew update, and brew upgrade errors were silently
swallowed. Now returned to caller. --continue flag keeps going
past errors for partial-update scenarios."
```

---

## Task 5: Logger

**Files:**
- Create: `internal/logger/logger.go`
- Create: `internal/logger/logger_test.go`
- Modify: `internal/executor/steps.go`

**Interfaces:**
- Produces: `logger.Log(result, toolName, stepType)` — appends to log file
- Consumes: called from `cmd/install.go` and `internal/tui/model.go` after each step

- [ ] **Step 1: Write the failing test**

Create `internal/logger/logger_test.go`:

```go
package logger

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLog_WritesEntry(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	Log("installed", "bat", "brew")

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("ReadFile failed: %v", err)
	}
	line := string(data)
	if !strings.Contains(line, "installed") {
		t.Fatalf("expected 'installed' in log, got %q", line)
	}
	if !strings.Contains(line, "bat") {
		t.Fatalf("expected 'bat' in log, got %q", line)
	}
	if !strings.Contains(line, "brew") {
		t.Fatalf("expected 'brew' in log, got %q", line)
	}
}

func TestLog_AppendsMultiple(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	Log("installed", "bat", "brew")
	Log("skipped", "fzf", "brew")
	Log("error", "herd", "cask: exit status 1")

	data, _ := os.ReadFile(logPath)
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 log lines, got %d", len(lines))
	}
}

func TestLog_CreatesParentDir(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "nested", "deep", "test.log")

	Log("installed", "bat", "brew")

	if _, err := os.Stat(logPath); err != nil {
		t.Fatalf("log file not created: %v", err)
	}
}

func TestLog_TimestampFormat(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	before := time.Now().UTC().Format(time.RFC3339)
	Log("installed", "bat", "brew")
	after := time.Now().UTC().Format(time.RFC3339)

	data, _ := os.ReadFile(logPath)
	line := string(data)

	parts := strings.Fields(line)
	if len(parts) < 1 {
		t.Fatalf("expected timestamp in log, got %q", line)
	}
	ts := parts[0]
	if ts < before || ts > after {
		t.Fatalf("timestamp %q not between %q and %q", ts, before, after)
	}
}

func TestReadLastErrors(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	Log("installed", "bat", "brew")
	Log("error", "herd", "cask: exit 1")
	Log("skipped", "fzf", "brew")
	Log("error", "phpstorm", "cask: exit 1")

	errors := ReadErrors(2)
	if len(errors) != 2 {
		t.Fatalf("expected 2 errors, got %d", len(errors))
	}
	if !strings.Contains(errors[0], "phpstorm") {
		t.Fatalf("expected phpstorm in first error, got %q", errors[0])
	}
	if !strings.Contains(errors[1], "herd") {
		t.Fatalf("expected herd in second error, got %q", errors[1])
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/logger/ -v`
Expected: FAIL — package doesn't exist

- [ ] **Step 3: Write the implementation**

Create `internal/logger/logger.go`:

```go
package logger

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var logPath string

func init() {
	home, _ := os.UserHomeDir()
	logPath = filepath.Join(home, ".dotfiles", ".log")
}

func SetPath(p string) {
	logPath = p
}

func Log(status, tool, detail string) {
	os.MkdirAll(filepath.Dir(logPath), 0755)
	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	ts := time.Now().UTC().Format(time.RFC3339)
	fmt.Fprintf(f, "%s [%s] %s: %s\n", ts, status, tool, detail)
}

func ReadErrors(limit int) []string {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil
	}
	var errors []string
	lines := strings.Split(string(data), "\n")
	for i := len(lines) - 1; i >= 0 && len(errors) < limit; i-- {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			continue
		}
		if strings.Contains(line, "[error]") {
			errors = append(errors, line)
		}
	}
	return errors
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/logger/ -v`
Expected: all pass

- [ ] **Step 5: Wire logger into install command**

In `cmd/install.go`, add import and logging calls. In `installAll`, after each step result switch block, add:

```go
logger.Log(r.Status, t.Name, r.Msg)
```

In `internal/tui/model.go`, in the `installMsg` handler, after building the message line, add:

```go
for _, r := range msg.results {
	logger.Log(r.Status, msg.toolName, r.Msg)
}
```

- [ ] **Step 6: Run all tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 7: Build and verify**

Run: `go build -o dotfiles . && ./dotfiles install --all --dry-run`
Expected: works (dry-run doesn't log, but install does)

- [ ] **Step 8: Commit**

```bash
git add internal/logger/logger.go internal/logger/logger_test.go cmd/install.go internal/tui/model.go
git commit -m "feat: add file logger for install operations

Logs each step result to ~/.dotfiles/.log with timestamp.
ReadErrors retrieves recent errors for doctor --log."
```

---

## Task 6: Backup Cleanup Command

**Files:**
- Modify: `internal/symlink/symlink.go`
- Modify: `internal/symlink/symlink_test.go`
- Create: `cmd/cleanup.go`

**Interfaces:**
- Consumes: `manifest.Load`, `symlink.Link`
- Produces: `LinkResult` struct with `BackupCreated bool` and `BackupPath string`; `cleanupCmd` scans manifest targets for `.backup` files

- [ ] **Step 1: Write the failing test**

Append to `internal/symlink/symlink_test.go`:

```go
func TestLinkResult_BackupCreated(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("new"), 0644)
	os.WriteFile(dst, []byte("old"), 0644)

	result, err := LinkWithResult(src, dst)
	if err != nil {
		t.Fatalf("LinkWithResult failed: %v", err)
	}
	if !result.BackupCreated {
		t.Fatal("expected BackupCreated=true")
	}
	if result.BackupPath != dst+".backup" {
		t.Fatalf("expected backup path %s, got %s", dst+".backup", result.BackupPath)
	}
}

func TestLinkResult_NoBackup(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("content"), 0644)

	result, err := LinkWithResult(src, dst)
	if err != nil {
		t.Fatalf("LinkWithResult failed: %v", err)
	}
	if result.BackupCreated {
		t.Fatal("expected BackupCreated=false for fresh symlink")
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/symlink/ -run TestLinkResult -v`
Expected: FAIL — `LinkWithResult` doesn't exist

- [ ] **Step 3: Implement LinkWithResult**

In `internal/symlink/symlink.go`, add:

```go
type LinkResult struct {
	BackupCreated bool
	BackupPath    string
}

func LinkWithResult(src, dst string) (LinkResult, error) {
	result := LinkResult{}
	if existing, err := os.Readlink(dst); err == nil {
		if existing == src {
			return result, nil
		}
		target, _ := os.Readlink(dst)
		return result, fmt.Errorf("%s is already symlinked to %s (not %s) — skipping", dst, target, src)
	}
	if _, err := os.Lstat(dst); err == nil {
		backup := dst + ".backup"
		if err := os.Rename(dst, backup); err != nil {
			return result, fmt.Errorf("backup %s: %w", dst, err)
		}
		result.BackupCreated = true
		result.BackupPath = backup
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return result, err
	}
	return result, os.Symlink(src, dst)
}
```

Keep the existing `Link` function as a wrapper:

```go
func Link(src, dst string) error {
	_, err := LinkWithResult(src, dst)
	return err
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/symlink/ -v`
Expected: all pass (existing + new)

- [ ] **Step 5: Write the cleanup command**

Create `cmd/cleanup.go`:

```go
package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var cleanupDryRun bool

var cleanupCmd = &cobra.Command{
	Use:   "cleanup",
	Short: "Remove .backup files created by symlink operations",
	RunE: func(cmd *cobra.Command, args []string) error {
		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}

		removed := 0
		for _, cat := range m.Categories {
			for _, t := range cat.Tools {
				for _, step := range t.Steps {
					if step.Type != "symlink" && step.Type != "template-symlink" {
						continue
					}
					target := os.ExpandEnv(step.To)
					backup := target + ".backup"
					if _, err := os.Stat(backup); err == nil {
						if cleanupDryRun {
							fmt.Printf("  would remove: %s\n", backup)
						} else {
							if err := os.Remove(backup); err != nil {
								fmt.Fprintf(os.Stderr, "  failed to remove %s: %v\n", backup, err)
								continue
							}
							fmt.Printf("  removed: %s\n", backup)
						}
						removed++
					}
				}
			}
		}

		if removed == 0 {
			fmt.Println("No backup files found.")
		} else {
			fmt.Printf("\n%d backup file(s) %s.\n", removed, cleanupDryRun ? "would be removed" : "removed")
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(cleanupCmd)
	cleanupCmd.Flags().BoolVar(&cleanupDryRun, "dry-run", false, "Preview without removing")
}
```

Note: the ternary `cleanupDryRun ? "would be removed" : "removed"` is not valid Go. Use:

```go
action := "removed"
if cleanupDryRun {
	action = "would be removed"
}
fmt.Printf("\n%d backup file(s) %s.\n", removed, action)
```

- [ ] **Step 6: Build and verify**

Run: `go build -o dotfiles . && ./dotfiles cleanup --dry-run`
Expected: lists any `.backup` files or prints "No backup files found."

- [ ] **Step 7: Run all tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 8: Commit**

```bash
git add internal/symlink/symlink.go internal/symlink/symlink_test.go cmd/cleanup.go
git commit -m "feat: add cleanup command and LinkWithResult

cleanup removes .backup files left by symlink operations.
LinkWithResult reports whether a backup was created. Both
support --dry-run."
```

---

## Task 7: Doctor Command

**Files:**
- Create: `internal/doctor/check.go`
- Create: `internal/doctor/check_test.go`
- Create: `cmd/doctor.go`

**Interfaces:**
- Consumes: `manifest.Manifest`, `manifest.Step`, `config.GetVars`
- Produces: `Check(step, dotfilesDir, vars) Result` where `Result` is `{Status string, Msg string}` with statuses: `"ok"`, `"missing"`, `"broken"`, `"unknown"`
- `doctorCmd` registered via `init()`

- [ ] **Step 1: Write the failing tests**

Create `internal/doctor/check_test.go`:

```go
package doctor

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

func TestCheckBrew_OK(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "go",
		Skip:    "which go",
	}
	result := Check(step, "", nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckBrew_Missing(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "nonexistent-package-xyz",
		Skip:    "which nonexistent-package-xyz",
	}
	result := Check(step, "", nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckSymlink_OK(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("content"), 0644)
	os.Symlink(src, dst)

	step := manifest.Step{
		Type: "symlink",
		From: "src",
		To:   dst,
	}
	result := Check(step, dir, nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckSymlink_Missing(t *testing.T) {
	dir := t.TempDir()
	step := manifest.Step{
		Type: "symlink",
		From: "nonexistent",
		To:   filepath.Join(dir, "missing-dst"),
	}
	result := Check(step, dir, nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckSymlink_BrokenTarget(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	other := filepath.Join(dir, "other")
	os.WriteFile(src, []byte("content"), 0644)
	os.WriteFile(other, []byte("other"), 0644)
	os.Symlink(other, dst)

	step := manifest.Step{
		Type: "symlink",
		From: "src",
		To:   dst,
	}
	result := Check(step, dir, nil)
	if result.Status != "broken" {
		t.Fatalf("expected broken, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckGitClone_OK(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "existing")
	os.MkdirAll(dest, 0755)

	step := manifest.Step{
		Type: "git-clone",
		Dest: dest,
	}
	result := Check(step, "", nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckGitClone_Missing(t *testing.T) {
	step := manifest.Step{
		Type: "git-clone",
		Dest: "/nonexistent/path/that/does/not/exist",
	}
	result := Check(step, "", nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckRun_OK(t *testing.T) {
	step := manifest.Step{
		Type: "run",
		Skip: "true",
	}
	result := Check(step, "", nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckRun_Missing(t *testing.T) {
	step := manifest.Step{
		Type: "run",
		Skip: "false",
	}
	result := Check(step, "", nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go test ./internal/doctor/ -v`
Expected: FAIL — package doesn't exist

- [ ] **Step 3: Write the implementation**

Create `internal/doctor/check.go`:

```go
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `go test ./internal/doctor/ -v`
Expected: all pass

- [ ] **Step 5: Write the doctor command**

Create `cmd/doctor.go`:

```go
package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/doctor"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var doctorLogFlag bool

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Check health of installed tools and symlinks",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		fmt.Println("Dotfiles Health Check")
		fmt.Println("=====================")

		rev := strings.TrimSpace(string(exec.Command("git", "-C", dotfilesDir, "rev-parse", "--short", "HEAD").Output()))
		status := exec.Command("git", "-C", dotfilesDir, "status", "--porcelain").Output()
		repoState := "up to date"
		if len(status) > 0 {
			repoState = "dirty (uncommitted changes)"
		}
		fmt.Printf("\nRepository: %s (%s)\n", repoState, rev)

		m, err := manifest.Load(dotfilesDir + "/config/tools.yaml")
		if err != nil {
			return err
		}
		vars := config.GetVars()

		okCount := 0
		missingCount := 0
		brokenCount := 0
		unknownCount := 0

		for _, cat := range m.Categories {
			fmt.Printf("\n%s:\n", cat.Name)
			for _, t := range cat.Tools {
				results := []doctor.Result{}
				allOk := true
				for _, step := range t.Steps {
					r := doctor.Check(step, dotfilesDir, vars)
					results = append(results, r)
					if r.Status != "ok" {
						allOk = false
					}
				}

				if allOk {
					fmt.Printf("  \u2713 %s\n", t.Name)
					okCount++
				} else {
					for _, r := range results {
						switch r.Status {
						case "ok":
						case "missing":
							fmt.Printf("  \u2717 %s (%s)\n", t.Name, r.Msg)
							missingCount++
						case "broken":
							fmt.Fprintf(os.Stderr, "  \u26a0 %s (%s)\n", t.Name, r.Msg)
							brokenCount++
						default:
							fmt.Fprintf(os.Stderr, "  ? %s (%s)\n", t.Name, r.Msg)
							unknownCount++
						}
					}
				}
			}
		}

		fmt.Printf("\nSummary: %d ok, %d missing, %d broken", okCount, missingCount, brokenCount)
		if unknownCount > 0 {
			fmt.Printf(", %d unknown", unknownCount)
		}
		fmt.Println()

		if doctorLogFlag {
			printRecentErrors()
		}

		return nil
	},
}

func printRecentErrors() {
	home, _ := os.UserHomeDir()
	errors := doctor.ReadErrors(home + "/.dotfiles/.log")
	if len(errors) == 0 {
		fmt.Println("\nNo recent errors logged.")
		return
	}
	fmt.Printf("\nRecent errors:\n")
	for _, e := range errors {
		fmt.Printf("  %s\n", e)
	}
}

func init() {
	rootCmd.AddCommand(doctorCmd)
	doctorCmd.Flags().BoolVar(&doctorLogFlag, "log", false, "Show recent errors from install log")
}
```

Note: `doctor.ReadErrors` needs to be exported. In `internal/logger/logger.go`, rename `ReadErrors` to `ReadErrors` (already exported) and add a convenience call in the doctor package or call `logger.ReadErrors` directly.

Correction: use `logger.ReadErrors` directly in `cmd/doctor.go`. Replace the `printRecentErrors` function:

```go
func printRecentErrors() {
	errors := logger.ReadErrors(10)
	if len(errors) == 0 {
		fmt.Println("\nNo recent errors logged.")
		return
	}
	fmt.Printf("\nRecent errors:\n")
	for _, e := range errors {
		fmt.Printf("  %s\n", e)
	}
}
```

And add the import:

```go
"github.com/agustinzamar/dotfiles/internal/logger"
```

Remove the `os.UserHomeDir` usage in `printRecentErrors`.

- [ ] **Step 6: Build and verify**

Run: `go build -o dotfiles . && ./dotfiles doctor`
Expected: prints health check with ✓/✗/⚠ per tool

- [ ] **Step 7: Verify the --log flag**

Run: `./dotfiles doctor --log`
Expected: prints recent errors or "No recent errors logged."

- [ ] **Step 8: Run all tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 9: Commit**

```bash
git add internal/doctor/check.go internal/doctor/check_test.go cmd/doctor.go
git commit -m "feat: add doctor command

Health check for all tools: verifies brew/cask installed, symlinks
point to correct targets, vscode extensions present, git clones
exist, template vars set. --log shows recent errors."
```

---

## Task 8: macOS Defaults Step Type

**Files:**
- Modify: `internal/manifest/manifest.go`
- Modify: `internal/executor/steps.go`
- Modify: `internal/executor/executor_test.go`
- Modify: `internal/executor/executor.go`
- Modify: `config/tools.yaml`

**Interfaces:**
- Consumes: new `Step` fields: `Domain`, `Key`, `Value`, `ValueType`
- Produces: `defaults` step type executed via `execDefaults()`

- [ ] **Step 1: Add Step fields**

In `internal/manifest/manifest.go`, add to the `Step` struct:

```go
Domain    string `yaml:"domain,omitempty"`
Key       string `yaml:"key,omitempty"`
Value     string `yaml:"value,omitempty"`
ValueType string `yaml:"valueType,omitempty"`
```

- [ ] **Step 2: Write failing tests**

Append to `internal/executor/executor_test.go`:

```go
func TestDefaultsSkip(t *testing.T) {
	step := manifest.Step{
		Type:      "defaults",
		Domain:    "com.apple.finder",
		Key:       "AppleShowAllExtensions",
		Value:     "true",
		ValueType: "bool",
	}
	result := execDefaults(step, func(s string) string { return s })
	if result.Status != "skipped" && result.Status != "installed" {
		t.Fatalf("expected skipped or installed, got %s: %s", result.Status, result.Msg)
	}
}
```

Note: this test is environment-dependent. If the default is already set, it skips. If not, it sets and reports installed. Both are valid.

- [ ] **Step 3: Run tests to verify they fail**

Run: `go test ./internal/executor/ -run TestDefaults -v`
Expected: FAIL — `execDefaults` doesn't exist

- [ ] **Step 4: Implement execDefaults**

In `internal/executor/steps.go`, add:

```go
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
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return Result{Status: "error", Msg: fmt.Sprintf("defaults write %s %s: %v", domain, key, err)}
	}
	return Result{Status: "installed", Msg: domain + " " + key}
}
```

- [ ] **Step 5: Wire into dispatcher**

In `internal/executor/executor.go`, add the case in the switch:

```go
case "defaults":
	return execDefaults(step, expand)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `go test ./internal/executor/ -run TestDefaults -v`
Expected: PASS

- [ ] **Step 7: Add macOS Defaults to tools.yaml**

In `config/tools.yaml`, add a new category before "Backup & Sync":

```yaml
  # ── macOS Defaults ───────────────────────────────────
  - name: "macOS Defaults"
    tools:
      - name: "Finder"
        description: "Show all extensions, pathbar, full path in title"
        checked: true
        steps:
          - type: defaults
            domain: com.apple.finder
            key: AppleShowAllExtensions
            value: "true"
            valueType: bool
          - type: defaults
            domain: com.apple.finder
            key: ShowPathbar
            value: "true"
            valueType: bool
          - type: defaults
            domain: com.apple.finder
            key: _FXShowPosixPathInTitle
            value: "true"
            valueType: bool

      - name: "Dock"
        description: "Autohide, no recents, left position"
        checked: true
        steps:
          - type: defaults
            domain: com.apple.dock
            key: autohide
            value: "true"
            valueType: bool
          - type: defaults
            domain: com.apple.dock
            key: show-recents
            value: "false"
            valueType: bool
          - type: defaults
            domain: com.apple.dock
            key: orientation
            value: "left"
            valueType: string

      - name: "Screenshots"
        description: "PNG format, save to Desktop"
        checked: true
        steps:
          - type: defaults
            domain: com.apple.screencapture
            key: type
            value: "png"
            valueType: string
          - type: defaults
            domain: com.apple.screencapture
            key: location
            value: "${HOME}/Desktop"
            valueType: string

      - name: "Text & Input"
        description: "Fast key repeat, always show scrollbars"
        checked: true
        steps:
          - type: defaults
            domain: NSGlobalDomain
            key: AppleShowScrollBars
            value: "Always"
            valueType: string
          - type: defaults
            domain: NSGlobalDomain
            key: KeyRepeat
            value: "2"
            valueType: int
          - type: defaults
            domain: NSGlobalDomain
            key: InitialKeyRepeat
            value: "15"
            valueType: int

      - name: "Misc"
        description: "No .DS_Store on network stores, disable Handoff"
        checked: true
        steps:
          - type: defaults
            domain: com.apple.desktopservices
            key: DSDontWriteNetworkStores
            value: "true"
            valueType: bool
          - type: defaults
            domain: com.apple.coreservices.useractivityd
            key: ActivityCacheAllowed
            value: "false"
            valueType: bool
```

- [ ] **Step 8: Run all tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 9: Build and verify**

Run: `go build -o dotfiles . && ./dotfiles list --category "macOS Defaults"`
Expected: lists 5 tools in the macOS Defaults category

- [ ] **Step 10: Commit**

```bash
git add internal/manifest/manifest.go internal/executor/steps.go internal/executor/executor.go internal/executor/executor_test.go config/tools.yaml
git commit -m "feat: add defaults step type and macOS Defaults category

New 'defaults' step type runs 'defaults write' with bool/int/string
values. Idempotent: skips if current value matches. Adds 5 curated
macOS default tool groups to the manifest."
```

---

## Task 9: TUI Progress Spinner

**Files:**
- Modify: `internal/tui/model.go`
- Modify: `internal/tui/styles.go`
- Modify: `go.mod` / `go.sum`

**Interfaces:**
- Consumes: `github.com/charmbracelet/bubbles/spinner`
- Produces: TUI shows spinner + tool name during install; progress counter in header

- [ ] **Step 1: Add spinner dependency**

Run:
```bash
go get github.com/charmbracelet/bubbles/spinner
```

- [ ] **Step 2: Write the implementation**

Replace `internal/tui/model.go`:

```go
package tui

import (
	"fmt"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/config"
	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/logger"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
)

type state int

const (
	stateSelecting state = iota
	stateInstalling
	stateDone
)

type toolItem struct {
	tool    manifest.Tool
	checked bool
}

type stepDoneMsg struct {
	toolName string
	result   executor.Result
	stepIdx  int
	totalSteps int
}

type installCompleteMsg struct {
	toolName string
	results  []executor.Result
}

type model struct {
	categories    []manifest.Category
	items         []toolItem
	cursor        int
	state         state
	messages      []string
	vars          map[string]string
	spinner       spinner.Model
	currentTool   string
	currentStep   int
	totalSteps    int
	installing    int
	totalToInstall int
	currentToolSteps []manifest.Step
	currentStepResults []executor.Result
	currentToolIdx int
}

func NewModel(m *manifest.Manifest) tea.Model {
	vars := config.GetVars()
	var items []toolItem
	for _, cat := range m.Categories {
		for _, t := range cat.Tools {
			items = append(items, toolItem{tool: t, checked: t.Checked})
		}
	}
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = SpinnerStyle
	return &model{
		categories: m.Categories,
		items:      items,
		state:      stateSelecting,
		vars:       vars,
		spinner:    s,
	}
}

func (m *model) Init() tea.Cmd {
	return m.spinner.Tick
}

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case tea.KeyMsg:
		if m.state == stateSelecting {
			switch msg.String() {
			case "ctrl+c", "q":
				return m, tea.Quit
			case "up", "k":
				if m.cursor > 0 {
					m.cursor--
				}
			case "down", "j":
				if m.cursor < len(m.items)-1 {
					m.cursor++
				}
			case " ":
				m.items[m.cursor].checked = !m.items[m.cursor].checked
			case "enter":
				m.collectVars()
				m.state = stateInstalling
				return m, m.startNextInstall(0)
			}
		}

	case stepDoneMsg:
		m.currentStepResults = append(m.currentStepResults, msg.result)
		logger.Log(msg.result.Status, msg.currentTool, msg.result.Msg)
		m.currentStep++
		if m.currentStep >= len(m.currentToolSteps) {
			m.messages = append(m.messages, m.formatResults(msg.toolName, m.currentStepResults))
			return m, m.startNextInstall(m.currentToolIdx + 1)
		}
		return m, m.runCurrentStep()

	case installCompleteMsg:
		m.messages = append(m.messages, m.formatResults(msg.toolName, msg.results))
		for _, r := range msg.results {
			logger.Log(r.Status, msg.toolName, r.Msg)
		}
		return m, m.startNextInstall(m.currentToolIdx + 1)
	}

	return m, nil
}

func (m *model) runCurrentStep() tea.Cmd {
	step := m.currentToolSteps[m.currentStep]
	m.currentStep = m.currentStep
	dotfilesDir := manifest.DotfilesDir()
	return func() tea.Msg {
		r := executor.Run(step, dotfilesDir, m.vars, false)
		return stepDoneMsg{
			toolName:   m.currentTool,
			result:     r,
			stepIdx:    m.currentStep,
			totalSteps: len(m.currentToolSteps),
		}
	}
}

func (m *model) startNextInstall(idx int) tea.Cmd {
	for i := idx; i < len(m.items); i++ {
		if m.items[i].checked {
			m.currentToolIdx = i
			m.currentTool = m.items[i].tool.Name
			m.currentToolSteps = m.items[i].tool.Steps
			m.currentStep = 0
			m.currentStepResults = nil
			m.installing++
			return m.runCurrentStep()
		}
	}
	m.state = stateDone
	return tea.Quit
}

func (m *model) formatResults(toolName string, results []executor.Result) string {
	var b strings.Builder
	for _, r := range results {
		icon := "\u2713"
		switch r.Status {
		case "skipped":
			icon = "\u2022"
		case "error":
			icon = "\u2717"
		}
		b.WriteString(fmt.Sprintf("  %s %s: %s\n", icon, toolName, r.Msg))
	}
	return strings.TrimRight(b.String(), "\n")
}

func (m *model) View() string {
	switch m.state {
	case stateSelecting:
		return m.selectionView()
	case stateInstalling:
		return m.installingView()
	case stateDone:
		return m.installingView()
	}
	return ""
}

func (m *model) selectionView() string {
	var b strings.Builder
	b.WriteString(TitleStyle.Render("Dotfiles Installer"))
	b.WriteString("\n")
	b.WriteString(HelpStyle.Render("j/k or \u2191/\u2193 navigate  Space toggle  Enter install  q quit"))
	b.WriteString("\n\n")

	currentCat := ""
	for i, item := range m.items {
		if item.tool.Category != currentCat {
			currentCat = item.tool.Category
			b.WriteString(CategoryStyle.Render(currentCat))
			b.WriteString("\n")
		}
		cursor := " "
		if m.cursor == i {
			cursor = CursorStyle.Render(">")
		}
		checkbox := "[ ]"
		if item.checked {
			checkbox = CheckedStyle.Render("[\u2713]")
		}
		name := UncheckedStyle.Render(item.tool.Name)
		if item.checked {
			name = CheckedStyle.Render(item.tool.Name)
		}
		if m.cursor == i {
			name = CursorStyle.Render(item.tool.Name)
		}
		b.WriteString(CheckboxStyle.Render(fmt.Sprintf("%s %s %s", cursor, checkbox, name)))
		b.WriteString("\n")
	}
	return b.String()
}

func (m *model) installingView() string {
	var b strings.Builder
	b.WriteString(TitleStyle.Render("Installing..."))
	b.WriteString("\n")

	if m.state == stateInstalling {
		b.WriteString(fmt.Sprintf("%s Installing %d/%d: %s\n",
			m.spinner.View(), m.installing, m.totalToInstall, m.currentTool))
	}

	for _, msg := range m.messages {
		b.WriteString(msg)
		b.WriteString("\n")
	}
	if m.state == stateDone {
		b.WriteString("\n" + SuccessStyle.Render("Done. Restart your terminal."))
	}
	return b.String()
}

func (m *model) collectVars() {
	m.totalToInstall = 0
	for _, item := range m.items {
		if !item.checked {
			continue
		}
		m.totalToInstall++
		for _, step := range item.tool.Steps {
			if step.Type == "template-symlink" {
				config.PromptMissing(step.Vars)
			}
		}
	}
	m.vars = config.GetVars()
}
```

- [ ] **Step 3: Add spinner style**

In `internal/tui/styles.go`, add:

```go
SpinnerStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#7dc4e4"))
```

- [ ] **Step 4: Build and verify**

Run: `go build -o dotfiles .`
Expected: compiles

- [ ] **Step 5: Run all tests**

Run: `go test ./...`
Expected: all pass

- [ ] **Step 6: Manual TUI test**

Run: `./dotfiles install`
Expected: spinner shows during install with tool name and progress counter (e.g., "⣾ Installing 1/15: bat")

- [ ] **Step 7: Commit**

```bash
go get github.com/charmbracelet/bubbles/spinner
git add internal/tui/model.go internal/tui/styles.go go.mod go.sum
git commit -m "feat: add TUI progress spinner during install

Shows spinner + current tool name + progress counter (N/total)
during installation. Per-step execution with live feedback."
```

---

## Task 10: LICENSE File

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Create LICENSE**

Create file `LICENSE` with the MIT license:

```
MIT License

Copyright (c) 2026 Agustin Zamar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Commit**

```bash
git add LICENSE
git commit -m "chore: add MIT license"
```

---

## Task 11: CI Workflow

**Files:**
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/test.yml`:

```yaml
name: test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.26'

      - name: Build
        run: go build -o dotfiles .

      - name: Test
        run: go test ./...
```

- [ ] **Step 2: Verify YAML is valid**

Run: `go test ./...`
Expected: all pass (workflow file is not tested by Go, but we confirm tests still pass)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add GitHub Actions test workflow

Runs go build and go test on macOS runner for all
pushes and PRs to main."
```

---

## Task 12: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update commands table**

In `README.md`, replace the Commands table:

```markdown
| Command | Description |
|---------|-------------|
| `dotfiles install` | Launch interactive TUI with category checklist |
| `dotfiles install --all` | Non-interactive batch install of all tools |
| `dotfiles install --all --dry-run` | Preview what would be installed |
| `dotfiles update` | `git pull` + `brew update && brew upgrade` + re-sync symlinks |
| `dotfiles list` | List all available tools in the manifest |
| `dotfiles doctor` | Check health of installed tools and symlinks |
| `dotfiles cleanup` | Remove `.backup` files from symlink operations |
```

- [ ] **Step 2: Add macOS Defaults section**

In `README.md`, in the "What's Included" section, add after "Backup & Sync":

```markdown
### macOS Defaults
- **Finder** — Show all extensions, pathbar, full path in title
- **Dock** — Autohide, no recents, left position
- **Screenshots** — PNG format, save to Desktop
- **Text & Input** — Fast key repeat, always show scrollbars
- **Misc** — No .DS_Store on network stores, disable Handoff
```

- [ ] **Step 3: Add Step Types entry**

In the Step Types table, add:

```markdown
| `defaults` | `defaults write <domain> <key> -<type> <value>` | `defaults read` matches expected value |
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README with new commands and macOS defaults"
```

---

## Self-Review

**1. Spec coverage:**
- ✅ `doctor` command — Task 7
- ✅ `list` command — Task 2
- ✅ `--dry-run` — Task 3
- ✅ Error propagation in `update.go` — Task 4
- ✅ `vars.json` permissions — Task 1
- ✅ Logging — Task 5
- ✅ Backup cleanup — Task 6
- ✅ macOS defaults — Task 8
- ✅ TUI progress indicator — Task 9
- ✅ LICENSE — Task 10
- ✅ CI — Task 11
- ✅ README updated — Task 12

**2. Placeholder scan:** No TBD/TODO found. All code blocks contain complete implementations.

**3. Type consistency:**
- `Run(step, dotfilesDir, vars, dryRun)` — signature consistent across Tasks 3, 4, 5, 7, 9
- `LinkResult{BackupCreated, BackupPath}` — defined in Task 6, used in cleanup
- `doctor.Result{Status, Msg}` — defined in Task 7, used in `cmd/doctor.go`
- `logger.Log(status, tool, detail)` — defined in Task 5, used in Tasks 5, 7, 9
- `Step.Domain/Key/Value/ValueType` — defined in Task 8, used in `execDefaults` and `checkDefaults`
- `doctor.Check(step, dotfilesDir, vars)` — defined in Task 7, uses `manifest.Step` fields from Task 8

All signatures match.
