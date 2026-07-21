package symlink

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/agustinzamar/dotfiles/internal/snapshot"
)

type LinkResult struct {
	BackupCreated bool
	BackupPath    string
	SnapshotEntry *snapshot.Entry
}

func Link(src, dst string) error {
	_, err := LinkWithResult(src, dst, "")
	return err
}

func LinkWithResult(src, dst string, dotfilesDir string) (LinkResult, error) {
	absSrc, err := filepath.Abs(src)
	if err != nil {
		return LinkResult{}, fmt.Errorf("abs src: %w", err)
	}
	absDst, err := filepath.Abs(dst)
	if err != nil {
		return LinkResult{}, fmt.Errorf("abs dst: %w", err)
	}

	if _, err := os.Stat(absSrc); os.IsNotExist(err) {
		return LinkResult{}, fmt.Errorf("source %s does not exist", absSrc)
	}

	var snapEntry *snapshot.Entry
	backupCreated := false

	currentTarget, err := os.Readlink(absDst)
	if err == nil {
		if currentTarget == absSrc {
			return LinkResult{SnapshotEntry: &snapshot.Entry{OriginalPath: absDst, Action: "skipped"}}, nil
		}
		return LinkResult{}, fmt.Errorf("symlink %s already points to %s, not %s", absDst, currentTarget, absSrc)
	}

	if _, statErr := os.Stat(absDst); statErr == nil {
		if dotfilesDir != "" {
			entry, snapErr := snapshot.Take(absDst, dotfilesDir)
			if snapErr != nil {
				return LinkResult{}, fmt.Errorf("snapshot before symlink: %w", snapErr)
			}
			snapEntry = entry
		}
		backupCreated = true
	}

	if err := os.MkdirAll(filepath.Dir(absDst), 0755); err != nil {
		return LinkResult{}, fmt.Errorf("mkdir parent: %w", err)
	}

	if err := os.Remove(absDst); err != nil && !os.IsNotExist(err) {
		return LinkResult{}, fmt.Errorf("remove dst: %w", err)
	}

	if err := os.Symlink(absSrc, absDst); err != nil {
		return LinkResult{}, fmt.Errorf("symlink: %w", err)
	}

	if snapEntry == nil {
		snapEntry = &snapshot.Entry{OriginalPath: absDst, Action: "created"}
	}
	snapEntry.Action = "symlinked"

	return LinkResult{
		BackupCreated: backupCreated,
		SnapshotEntry: snapEntry,
	}, nil
}
