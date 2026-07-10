package symlink

import (
	"fmt"
	"os"
	"path/filepath"
)

func Link(src, dst string) error {
	if existing, err := os.Readlink(dst); err == nil {
		if existing == src {
			return nil
		}
			target, _ := os.Readlink(dst)
			return fmt.Errorf("%s is already symlinked to %s (not %s) — skipping", dst, target, src)
	}
	if _, err := os.Lstat(dst); err == nil {
		backup := dst + ".backup"
		if err := os.Rename(dst, backup); err != nil {
			return fmt.Errorf("backup %s: %w", dst, err)
		}
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	return os.Symlink(src, dst)
}
