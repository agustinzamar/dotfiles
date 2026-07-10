# Mackup + Backup Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mackup for sensitive file backup/restore across MacBooks, and a `dotfiles backup` command that runs mackup, then commits and pushes all dotfiles repo changes.

**Architecture:** Mackup handles sensitive files (`~/.ssh/config`, `~/.dotfiles-custom/shell/.aliases`) via cloud sync (iCloud/Dropbox). A new `dotfiles backup` command runs `mackup backup`, then git adds/commits/pushes the dotfiles repo with a timestamped message listing affected files.

**Tech Stack:** Go, Cobra, mackup (brew), os/exec

## Global Constraints

- Follow existing command patterns in `cmd/` (RunE, init() registration, manifest.DotfilesDir())
- Commit format: `backup: YYYY-MM-DD HH:MM` with body listing affected files
- Mackup config goes in `~/.mackup/` (user's home, not repo)
- Sensitive files stay out of git — mackup syncs them via cloud only

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `cmd/backup.go` | Create | New `dotfiles backup` command |
| `config/tools.yaml` | Modify | Add mackup to Utilities section |
| `docs/mackup-example.cfg` | Create | Example mackup config for reference |

---

### Task 1: Add mackup to tools.yaml

**Files:**
- Modify: `config/tools.yaml:522-531`

- [ ] **Step 1: Add mackup tool entry**

Add before the Finetune entry in the Utilities section:

```yaml
      - name: "mackup"
        description: "Backup app configs to cloud storage"
        checked: true
        steps:
          - type: brew
            package: mackup
```

- [ ] **Step 2: Verify YAML parses correctly**

Run: `cd /Users/agustin/Documents/repos/dotfiles && go run . list | grep -i mackup`
Expected: Shows "mackup" in the list

- [ ] **Step 3: Commit**

```bash
git add config/tools.yaml
git commit -m "feat: add mackup to tools manifest"
```

---

### Task 2: Create mackup configuration file

**Files:**
- Create: `docs/mackup-example.cfg`

- [ ] **Step 1: Create example mackup config**

```ini
[application]
name = dotfiles-custom

[configuration_files]
${HOME}/.dotfiles-custom/shell/.aliases
${HOME}/.ssh/config
```

This is a reference file. The actual config lives at `~/.mackup/dotfiles-custom.cfg` on each machine (not committed).

- [ ] **Step 2: Create the actual mackup config on this machine**

Run:
```bash
mkdir -p ~/.mackup
cp /Users/agustin/Documents/repos/dotfiles/docs/mackup-example.cfg ~/.mackup/dotfiles-custom.cfg
```

- [ ] **Step 3: Verify mackup recognizes the config**

Run: `mackup list dotfiles-custom`
Expected: Lists the tracked files

- [ ] **Step 4: Commit the example**

```bash
git add docs/mackup-example.cfg
git commit -m "docs: add example mackup config for sensitive files"
```

---

### Task 3: Create the backup command

**Files:**
- Create: `cmd/backup.go`

- [ ] **Step 1: Write the backup command**

```go
package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var backupCmd = &cobra.Command{
	Use:   "backup",
	Short: "Run mackup backup, then commit and push dotfiles changes",
	RunE: func(cmd *cobra.Command, args []string) error {
		dotfilesDir := manifest.DotfilesDir()

		// Step 1: Run mackup backup
		fmt.Println("Running mackup backup...")
		mackup := exec.Command("mackup", "backup")
		mackup.Stdout = os.Stdout
		mackup.Stderr = os.Stderr
		if err := mackup.Run(); err != nil {
			fmt.Fprintf(os.Stderr, "  mackup backup failed: %v\n", err)
			fmt.Println("  Continuing with git backup...")
		}

		// Step 2: Check for changes
		status := exec.Command("git", "-C", dotfilesDir, "status", "--porcelain")
		out, err := status.Output()
		if err != nil {
			return fmt.Errorf("git status failed: %w", err)
		}
		if len(strings.TrimSpace(string(out))) == 0 {
			fmt.Println("No changes to commit.")
			return nil
		}

		// Step 3: Collect list of changed files
		files := strings.Split(strings.TrimSpace(string(out)), "\n")
		var filenames []string
		for _, f := range files {
			parts := strings.SplitN(strings.TrimSpace(f), " ", 2)
			if len(parts) > 1 {
				filenames = append(filenames, parts[1])
			}
		}

		// Step 4: Stage all changes
		fmt.Println("Staging changes...")
		add := exec.Command("git", "-C", dotfilesDir, "add", "-A")
		add.Stdout = os.Stdout
		add.Stderr = os.Stderr
		if err := add.Run(); err != nil {
			return fmt.Errorf("git add failed: %w", err)
		}

		// Step 5: Commit with timestamp and file list
		now := time.Now().Format("2006-01-02 15:04")
		msg := fmt.Sprintf("backup: %s\n\nFiles:\n", now)
		for _, f := range filenames {
			msg += fmt.Sprintf("- %s\n", f)
		}

		fmt.Printf("Committing: backup: %s (%d files)\n", now, len(filenames))
		commit := exec.Command("git", "-C", dotfilesDir, "commit", "-m", msg)
		commit.Stdout = os.Stdout
		commit.Stderr = os.Stderr
		if err := commit.Run(); err != nil {
			return fmt.Errorf("git commit failed: %w", err)
		}

		// Step 6: Push
		fmt.Println("Pushing...")
		push := exec.Command("git", "-C", dotfilesDir, "push")
		push.Stdout = os.Stdout
		push.Stderr = os.Stderr
		if err := push.Run(); err != nil {
			return fmt.Errorf("git push failed: %w", err)
		}

		fmt.Println("Backup complete.")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(backupCmd)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/agustin/Documents/repos/dotfiles && go build .`
Expected: No errors

- [ ] **Step 3: Verify the command appears**

Run: `go run . --help`
Expected: Shows `backup` in the command list

- [ ] **Step 4: Verify dry-run (no mackup config yet, should warn but continue)**

Run: `go run . backup`
Expected: mackup warning, then "No changes to commit" (if clean repo)

- [ ] **Step 5: Commit**

```bash
git add cmd/backup.go
git commit -m "feat: add backup command (mackup + git commit + push)"
```

---

### Task 4: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add backup command to the Commands table**

Add after the `cleanup` row:

```markdown
| `dotfiles backup` | Mackup sync + commit & push dotfiles changes |
```

- [ ] **Step 2: Add mackup to the Utilities section**

Add after Finetune in the "What's Included" section:

```markdown
- **mackup** — Backup sensitive configs (SSH, shell aliases) to cloud storage
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add backup command and mackup to README"
```

---

## Verification

After all tasks:

1. `go run . backup` — should run mackup, report no changes (if clean)
2. Make a test change to any file, then `go run . backup` — should commit and push
3. `git log --oneline -3` — should show the backup commit format
