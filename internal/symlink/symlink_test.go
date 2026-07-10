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

	backup := dst + ".backup"
	if _, err := os.Stat(backup); os.IsNotExist(err) {
		t.Fatal("backup file not created")
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
