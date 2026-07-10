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
		mackup := exec.Command("mackup", "backup", "dotfiles-custom")
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
