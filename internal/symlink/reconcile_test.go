package symlink

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

func TestReconcile_CreatesMissingSymlink(t *testing.T) {
	dotDir := t.TempDir()
	homeDir := t.TempDir()
	src := filepath.Join(dotDir, "src")
	dst := filepath.Join(homeDir, "dst")
	os.WriteFile(src, []byte("content"), 0644)

	step := manifest.Step{
		Type: "symlink",
		From: "src",
		To:   dst,
	}
	result := Reconcile(step, dotDir, nil, func(s string) string { return s })
	if !result.Repaired {
		t.Fatalf("expected repaired=true for missing symlink, got %t: %s", result.Repaired, result.Msg)
	}
	if result.Msg != "created" {
		t.Fatalf("expected msg 'created', got %s", result.Msg)
	}

	linkTarget, _ := os.Readlink(dst)
	if linkTarget != src {
		t.Fatalf("expected %q, got %q", src, linkTarget)
	}
}

func TestReconcile_RepairsWrongTarget(t *testing.T) {
	dotDir := t.TempDir()
	homeDir := t.TempDir()
	src := filepath.Join(dotDir, "src")
	dst := filepath.Join(homeDir, "dst")
	other := filepath.Join(homeDir, "other")
	os.WriteFile(src, []byte("content"), 0644)
	os.WriteFile(other, []byte("other"), 0644)
	os.Symlink(other, dst)

	step := manifest.Step{
		Type: "symlink",
		From: "src",
		To:   dst,
	}
	result := Reconcile(step, dotDir, nil, func(s string) string { return s })
	if !result.Repaired {
		t.Fatalf("expected repaired=true for wrong target, got %t: %s", result.Repaired, result.Msg)
	}

	linkTarget, _ := os.Readlink(dst)
	if linkTarget != src {
		t.Fatalf("symlink not repaired: got %q, want %q", linkTarget, src)
	}
}

func TestReconcile_SkipsCorrectSymlink(t *testing.T) {
	dotDir := t.TempDir()
	homeDir := t.TempDir()
	src := filepath.Join(dotDir, "src")
	dst := filepath.Join(homeDir, "dst")
	os.WriteFile(src, []byte("content"), 0644)
	os.Symlink(src, dst)

	step := manifest.Step{
		Type: "symlink",
		From: "src",
		To:   dst,
	}
	result := Reconcile(step, dotDir, nil, func(s string) string { return s })
	if result.Repaired {
		t.Fatalf("expected not repaired for correct symlink, got %t: %s", result.Repaired, result.Msg)
	}
	if result.Msg != "already correct" {
		t.Fatalf("expected msg 'already correct', got %s", result.Msg)
	}
}
