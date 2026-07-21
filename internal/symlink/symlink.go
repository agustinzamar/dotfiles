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
	src = filepath.Clean(src)
	dst = filepath.Clean(dst)
	result := LinkResult{}

	if _, err := os.Stat(src); err != nil {
		return result, fmt.Errorf("source %s does not exist — skipping symlink to %s", src, dst)
	}

	if existing, err := os.Readlink(dst); err == nil {
		if existing == src {
			return result, nil
		}
		resolved, err := filepath.EvalSymlinks(dst)
		if err == nil && resolved == src {
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
	os.Remove(dst)
	return result, os.Symlink(src, dst)
}

func Link(src, dst string) error {
	_, err := LinkWithResult(src, dst)
	return err
}
