package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSaveVars_FilePermissions(t *testing.T) {
	dir := t.TempDir()
	home := os.Getenv("HOME")
	os.Setenv("HOME", dir)
	defer os.Setenv("HOME", home)

	varsCachePath = filepath.Join(dir, ".dotfiles-custom", "vars.json")

	vars := map[string]string{"TestKey": "test-value"}
	if err := SaveVars(vars); err != nil {
		t.Fatalf("SaveVars failed: %v", err)
	}

	info, err := os.Stat(varsCachePath)
	if err != nil {
		t.Fatalf("Stat failed: %v", err)
	}
	perm := info.Mode().Perm()
	if perm != 0600 {
		t.Fatalf("expected 0600, got %o", perm)
	}
}

func TestSaveVars_OverwriteFixesExistingPerms(t *testing.T) {
	dir := t.TempDir()
	home := os.Getenv("HOME")
	os.Setenv("HOME", dir)
	defer os.Setenv("HOME", home)

	varsCachePath = filepath.Join(dir, ".dotfiles-custom", "vars.json")

	if err := SaveVars(map[string]string{"A": "b"}); err != nil {
		t.Fatalf("first SaveVars failed: %v", err)
	}
	if err := os.Chmod(varsCachePath, 0644); err != nil {
		t.Fatalf("chmod to 0644 failed: %v", err)
	}

	if err := SaveVars(map[string]string{"C": "d"}); err != nil {
		t.Fatalf("second SaveVars failed: %v", err)
	}

	info, err := os.Stat(varsCachePath)
	if err != nil {
		t.Fatalf("Stat failed: %v", err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("expected 0600 after overwrite, got %o", info.Mode().Perm())
	}
}
