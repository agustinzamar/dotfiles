package cmd

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/spf13/cobra"
)

var uninstallAllFlag bool
var uninstallBasicFlag bool
var uninstallMacOSFlag bool
var uninstallDryRun bool
var uninstallProfileFlag string
var uninstallYesFlag bool

var uninstallCmd = &cobra.Command{
	Use:   "uninstall",
	Short: "Remove tools and configuration installed by dotfiles",
	RunE: func(cmd *cobra.Command, args []string) error {
		if !uninstallAllFlag && !uninstallBasicFlag && !uninstallMacOSFlag {
			return fmt.Errorf("specify one of --all, --basic, or --macos")
		}

		m, err := manifest.Load(manifest.DotfilesDir() + "/config/tools.yaml")
		if err != nil {
			return err
		}
		dotfilesDir := manifest.DotfilesDir()

		if !uninstallDryRun && !uninstallYesFlag && !confirmUninstall() {
			fmt.Println("Aborted.")
			return nil
		}

		removed, skipped := 0, 0
		for _, cat := range m.Categories {
			for _, t := range cat.Tools {
				if uninstallBasicFlag && !t.Basic {
					continue
				}
				if uninstallMacOSFlag && !t.MacOS {
					continue
				}
				if uninstallProfileFlag != "" && !t.MatchesProfile(uninstallProfileFlag) {
					continue
				}
				for _, step := range t.Steps {
					uninstallStep(step, t.Name, dotfilesDir, &removed, &skipped)
				}
				for _, f := range t.Features {
					if !f.Checked {
						continue
					}
					for _, step := range f.Steps {
						uninstallStep(step, t.Name+" > "+f.Name, dotfilesDir, &removed, &skipped)
					}
				}
			}
		}

		action := "removed"
		if uninstallDryRun {
			action = "would be removed"
		}
		fmt.Printf("\n%d step(s) %s, %d skipped.\n", removed, action, skipped)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(uninstallCmd)
	uninstallCmd.Flags().BoolVar(&uninstallAllFlag, "all", false, "Uninstall everything the manifest knows about")
	uninstallCmd.Flags().BoolVar(&uninstallBasicFlag, "basic", false, "Uninstall only the curated command-line essentials")
	uninstallCmd.Flags().BoolVar(&uninstallMacOSFlag, "macos", false, "Revert macOS-only tooling")
	uninstallCmd.Flags().BoolVar(&uninstallDryRun, "dry-run", false, "Preview what would be removed without making changes")
	uninstallCmd.Flags().StringVar(&uninstallProfileFlag, "profile", "", "Profile to filter tools (e.g. personal, work)")
	uninstallCmd.Flags().BoolVarP(&uninstallYesFlag, "yes", "y", false, "Skip the confirmation prompt")
	uninstallCmd.MarkFlagsMutuallyExclusive("all", "basic", "macos")
}

func confirmUninstall() bool {
	fmt.Print("This will remove symlinks, cloned repos, and installed packages managed by dotfiles. Continue? [y/N]: ")
	reader := bufio.NewReader(os.Stdin)
	val, _ := reader.ReadString('\n')
	val = strings.ToLower(strings.TrimSpace(val))
	return val == "y" || val == "yes"
}

func uninstallStep(step manifest.Step, label, dotfilesDir string, removed, skipped *int) {
	switch step.Type {
	case "symlink", "template-symlink":
		uninstallSymlink(step, label, dotfilesDir, removed, skipped)
	case "brew":
		runUninstall(label, step.Package, removed, skipped, "brew", "uninstall", step.Package)
	case "cask":
		runUninstall(label, step.Package, removed, skipped, "brew", "uninstall", "--cask", step.Package)
	case "tap":
		runUninstall(label, step.Repo, removed, skipped, "brew", "untap", step.Repo)
	case "vscode":
		runUninstall(label, step.Extension, removed, skipped, "code", "--uninstall-extension", step.Extension)
	case "omz-plugin":
		uninstallOMZPlugin(step, label, removed, skipped)
	case "git-clone":
		uninstallDir(os.ExpandEnv(step.Dest), label, removed, skipped)
	default:
		fmt.Printf("  %s: %s has no automatic revert, skipping\n", label, step.Type)
		*skipped++
	}
}

// uninstallSymlink removes a symlink only if it still points into dotfilesDir,
// so we never delete a file the user created or pointed elsewhere themselves.
func uninstallSymlink(step manifest.Step, label, dotfilesDir string, removed, skipped *int) {
	dst := os.ExpandEnv(step.To)
	target, err := os.Readlink(dst)
	if err != nil {
		*skipped++
		return
	}
	absDotfiles, _ := filepath.Abs(dotfilesDir)
	if !strings.HasPrefix(target, absDotfiles) {
		*skipped++
		return
	}

	if uninstallDryRun {
		fmt.Printf("  would remove: %s (%s)\n", dst, label)
		*removed++
		return
	}

	if err := os.Remove(dst); err != nil {
		fmt.Fprintf(os.Stderr, "  failed to remove %s: %v\n", dst, err)
		*skipped++
		return
	}

	backup := dst + ".backup"
	if _, err := os.Stat(backup); err == nil {
		if err := os.Rename(backup, dst); err != nil {
			fmt.Printf("  removed %s (backup restore failed: %v)\n", dst, err)
		} else {
			fmt.Printf("  removed %s, restored backup\n", dst)
		}
	} else {
		fmt.Printf("  removed %s\n", dst)
	}
	*removed++
}

func uninstallOMZPlugin(step manifest.Step, label string, removed, skipped *int) {
	name := step.Package
	if name == "" {
		parts := strings.Split(step.Repo, "/")
		name = strings.TrimSuffix(parts[len(parts)-1], ".git")
	}
	dest := os.ExpandEnv("${HOME}/.oh-my-zsh/custom/plugins/" + name)
	uninstallDir(dest, label, removed, skipped)
}

func uninstallDir(dest, label string, removed, skipped *int) {
	if dest == "" {
		*skipped++
		return
	}
	if _, err := os.Stat(dest); os.IsNotExist(err) {
		*skipped++
		return
	}
	if uninstallDryRun {
		fmt.Printf("  would remove: %s (%s)\n", dest, label)
		*removed++
		return
	}
	if err := os.RemoveAll(dest); err != nil {
		fmt.Fprintf(os.Stderr, "  failed to remove %s: %v\n", dest, err)
		*skipped++
		return
	}
	fmt.Printf("  removed %s\n", dest)
	*removed++
}

func runUninstall(label, name string, removed, skipped *int, args ...string) {
	if name == "" {
		*skipped++
		return
	}
	if uninstallDryRun {
		fmt.Printf("  would run: %s\n", strings.Join(args, " "))
		*removed++
		return
	}
	fmt.Fprintf(os.Stderr, "  %s (%s)...", label, name)
	cmd := exec.Command(args[0], args[1:]...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		fmt.Fprintf(os.Stderr, " ✗ (%s)\n", msg)
		*skipped++
		return
	}
	fmt.Fprintln(os.Stderr, " ✓")
	*removed++
}
