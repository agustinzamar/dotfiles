package symlink

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLink_FreshSymlink(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("content"), 0644)

	if err := Link(src, dst); err != nil {
		t.Fatalf("Link failed: %v", err)
	}

	linkTarget, err := os.Readlink(dst)
	if err != nil {
		t.Fatalf("Readlink failed: %v", err)
	}
	if linkTarget != src {
		t.Fatalf("expected %q, got %q", src, linkTarget)
	}
}

func TestLink_Idempotent(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("content"), 0644)

	Link(src, dst)
	if err := Link(src, dst); err != nil {
		t.Fatalf("idempotent Link failed: %v", err)
	}
}

func TestLink_BackupExistingFile(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("new content"), 0644)
	os.WriteFile(dst, []byte("old content"), 0644)

	if err := Link(src, dst); err != nil {
		t.Fatalf("Link failed: %v", err)
	}

	if _, err := os.Lstat(dst); os.IsNotExist(err) {
		t.Fatal("destination should exist after link")
	}
	linkTarget, _ := os.Readlink(dst)
	if linkTarget != src {
		t.Fatalf("expected symlink to %s, got %s", src, linkTarget)
	}
}

func TestLink_WrongSymlinkError(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	other := filepath.Join(dir, "other")
	os.WriteFile(src, []byte("content"), 0644)
	os.WriteFile(other, []byte("other"), 0644)
	os.Symlink(other, dst)

	if err := Link(src, dst); err == nil {
		t.Fatal("expected error for wrong symlink target")
	}
}

func TestLinkResult_BackupCreated(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("new"), 0644)
	os.WriteFile(dst, []byte("old"), 0644)

	result, err := LinkWithResult(src, dst, "")
	if err != nil {
		t.Fatalf("LinkWithResult failed: %v", err)
	}
	if !result.BackupCreated {
		t.Fatal("expected BackupCreated=true")
	}
}

func TestLinkResult_NoBackup(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("content"), 0644)

	result, err := LinkWithResult(src, dst, "")
	if err != nil {
		t.Fatalf("LinkWithResult failed: %v", err)
	}
	if result.BackupCreated {
		t.Fatal("expected BackupCreated=false for fresh symlink")
	}
}

func TestLinkWithSnapshot(t *testing.T) {
	dotDir := t.TempDir()
	srcDir := t.TempDir()
	src := filepath.Join(srcDir, "source")
	dst := filepath.Join(t.TempDir(), "target")
	os.WriteFile(src, []byte("content"), 0644)
	os.WriteFile(dst, []byte("existing content"), 0644)

	result, err := LinkWithResult(src, dst, dotDir)
	if err != nil {
		t.Fatalf("LinkWithResult() error = %v", err)
	}
	if result.SnapshotEntry == nil {
		t.Fatalf("expected SnapshotEntry, got nil")
	}
	if result.SnapshotEntry.Action != "symlinked" {
		t.Fatalf("Action = %q, want %q", result.SnapshotEntry.Action, "symlinked")
	}
	if _, err := os.Stat(result.SnapshotEntry.SnapshotPath); os.IsNotExist(err) {
		t.Fatalf("snapshot file %s does not exist", result.SnapshotEntry.SnapshotPath)
	}
	target, _ := os.Readlink(dst)
	if target != src {
		t.Fatalf("symlink target = %q, want %q", target, src)
	}
}
