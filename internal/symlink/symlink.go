package symlink

import (
	"fmt"
	"os"
	"path/filepath"
)

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
		// Resolve through intermediate symlinks (e.g., ~/.dotfiles -> ~/Documents/repos/dotfiles)
		resolved, err := filepath.EvalSymlinks(dst)
		if err == nil && resolved == src {
			return result, nil
		}
		target, _ := os.Readlink(dst)
		return result, fmt.Errorf("%s is already symlinked to %s (not %s) — skipping", dst, target, src)
	}
	if _, err := os.Lstat(dst); err == nil {
		if err := os.RemoveAll(dst); err != nil {
			return result, fmt.Errorf("remove %s: %w", dst, err)
		}
		result.BackupCreated = true
		result.BackupPath = dst + ".removed"
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return result, err
	}
	return result, os.Symlink(src, dst)
}

func Link(src, dst string) error {
	_, err := LinkWithResult(src, dst)
	return err
}
