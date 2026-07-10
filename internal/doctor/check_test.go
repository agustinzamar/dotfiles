package doctor

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

func TestCheckBrew_OK(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "go",
		Skip:    "which go",
	}
	result := Check(step, "", nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckBrew_Missing(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "nonexistent-package-xyz",
		Skip:    "which nonexistent-package-xyz",
	}
	result := Check(step, "", nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckSymlink_OK(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("content"), 0644)
	os.Symlink(src, dst)

	step := manifest.Step{
		Type: "symlink",
		From: "src",
		To:   dst,
	}
	result := Check(step, dir, nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckSymlink_Missing(t *testing.T) {
	dir := t.TempDir()
	step := manifest.Step{
		Type: "symlink",
		From: "nonexistent",
		To:   filepath.Join(dir, "missing-dst"),
	}
	result := Check(step, dir, nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckSymlink_BrokenTarget(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	other := filepath.Join(dir, "other")
	os.WriteFile(src, []byte("content"), 0644)
	os.WriteFile(other, []byte("other"), 0644)
	os.Symlink(other, dst)

	step := manifest.Step{
		Type: "symlink",
		From: "src",
		To:   dst,
	}
	result := Check(step, dir, nil)
	if result.Status != "broken" {
		t.Fatalf("expected broken, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckGitClone_OK(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "existing")
	os.MkdirAll(dest, 0755)

	step := manifest.Step{
		Type: "git-clone",
		Dest: dest,
	}
	result := Check(step, "", nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckGitClone_Missing(t *testing.T) {
	step := manifest.Step{
		Type: "git-clone",
		Dest: "/nonexistent/path/that/does/not/exist",
	}
	result := Check(step, "", nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckRun_OK(t *testing.T) {
	step := manifest.Step{
		Type: "run",
		Skip: "true",
	}
	result := Check(step, "", nil)
	if result.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s", result.Status, result.Msg)
	}
}

func TestCheckRun_Missing(t *testing.T) {
	step := manifest.Step{
		Type: "run",
		Skip: "false",
	}
	result := Check(step, "", nil)
	if result.Status != "missing" {
		t.Fatalf("expected missing, got %s: %s", result.Status, result.Msg)
	}
}
