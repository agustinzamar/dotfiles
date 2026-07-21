package lock

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAcquire_CreatesLockFile(t *testing.T) {
	dir := t.TempDir()
	lockPath := filepath.Join(dir, ".lock")
	l := New(lockPath)
	if err := l.Acquire(); err != nil {
		t.Fatalf("Acquire() error = %v", err)
	}
	defer l.Release()
	if _, err := os.Stat(lockPath); os.IsNotExist(err) {
		t.Fatalf("lock file %s not created", lockPath)
	}
}

func TestAcquire_BlocksConcurrent(t *testing.T) {
	dir := t.TempDir()
	lockPath := filepath.Join(dir, ".lock")
	l1 := New(lockPath)
	l2 := New(lockPath)
	if err := l1.Acquire(); err != nil {
		t.Fatalf("first Acquire() error = %v", err)
	}
	defer l1.Release()
	if err := l2.Acquire(); err == nil {
		t.Fatalf("second Acquire() should fail but didn't")
	}
}

func TestRelease_RemovesLockFile(t *testing.T) {
	dir := t.TempDir()
	lockPath := filepath.Join(dir, ".lock")
	l := New(lockPath)
	l.Acquire()
	if err := l.Release(); err != nil {
		t.Fatalf("Release() error = %v", err)
	}
	if _, err := os.Stat(lockPath); !os.IsNotExist(err) {
		t.Fatalf("lock file %s still exists after Release", lockPath)
	}
}
