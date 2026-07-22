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

	evalDst, errDst := filepath.EvalSymlinks(absDst)
	evalSrc, errSrc := filepath.EvalSymlinks(absSrc)
	if errDst == nil && errSrc == nil && evalDst == evalSrc {
		return LinkResult{SnapshotEntry: &snapshot.Entry{OriginalPath: absDst, Action: "skipped"}}, nil
	}

	var snapEntry *snapshot.Entry
	backupCreated := false
	var backupPath string
	repaired := false

	currentTarget, err := os.Readlink(absDst)
	if err == nil {
		if currentTarget == absSrc {
			return LinkResult{SnapshotEntry: &snapshot.Entry{OriginalPath: absDst, Action: "skipped"}}, nil
		}
		if rerr := os.Remove(absDst); rerr != nil && !os.IsNotExist(rerr) {
			return LinkResult{}, fmt.Errorf("remove old symlink: %w", rerr)
		}
		repaired = true
	} else if _, statErr := os.Stat(absDst); statErr == nil {
		if dotfilesDir != "" {
			entry, snapErr := snapshot.Take(absDst, dotfilesDir)
			if snapErr != nil {
				return LinkResult{}, fmt.Errorf("snapshot before symlink: %w", snapErr)
			}
			snapEntry = entry
		} else {
			backupPath = absDst + ".backup"
			if err := os.Rename(absDst, backupPath); err != nil {
				return LinkResult{}, fmt.Errorf("backup rename: %w", err)
			}
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

	if snapEntry == nil && !repaired {
		snapEntry = &snapshot.Entry{OriginalPath: absDst, Action: "created"}
	}
	if snapEntry != nil {
		snapEntry.Action = "symlinked"
	}

	return LinkResult{
		BackupCreated: backupCreated,
		BackupPath:    backupPath,
		SnapshotEntry: snapEntry,
	}, nil
}
