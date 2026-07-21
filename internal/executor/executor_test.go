package executor

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

func TestSymlinkSnapshot(t *testing.T) {
	dir := t.TempDir()
	srcDir := filepath.Join(dir, "dotfiles")
	dstDir := filepath.Join(dir, "home")
	os.MkdirAll(srcDir, 0755)
	os.MkdirAll(dstDir, 0755)
	srcFile := filepath.Join(srcDir, "testfile")
	dstFile := filepath.Join(dstDir, ".testfile")
	os.WriteFile(srcFile, []byte("content"), 0644)

	ResetSnapshots()
	step := manifest.Step{
		Type: "symlink",
		From: "testfile",
		To:   dstFile,
	}
	result := Run(step, srcDir, nil, false)
	if result.Status != "installed" {
		t.Fatalf("expected installed, got %s: %s", result.Status, result.Msg)
	}

	entries := SnapshotEntries()
	if len(entries) != 1 {
		t.Fatalf("expected 1 snapshot entry, got %d", len(entries))
	}
	if entries[0].OriginalPath != dstFile {
		t.Fatalf("expected original path %s, got %s", dstFile, entries[0].OriginalPath)
	}
	if entries[0].Action != "symlinked" {
		t.Fatalf("expected action symlinked, got %s", entries[0].Action)
	}
}

func TestTemplateSymlinkSnapshot(t *testing.T) {
	dir := t.TempDir()
	srcDir := filepath.Join(dir, "dotfiles")
	dstDir := filepath.Join(dir, "home")
	os.MkdirAll(srcDir, 0755)
	os.MkdirAll(dstDir, 0755)
	srcFile := filepath.Join(srcDir, "testfile.tmpl")
	dstFile := filepath.Join(dstDir, ".testfile")
	os.WriteFile(srcFile, []byte("hello {{.Name}}"), 0644)

	ResetSnapshots()
	step := manifest.Step{
		Type: "template-symlink",
		From: "testfile.tmpl",
		To:   dstFile,
	}
	vars := map[string]string{"Name": "world"}
	result := Run(step, srcDir, vars, false)
	if result.Status != "installed" {
		t.Fatalf("expected installed, got %s: %s", result.Status, result.Msg)
	}

	renderedPath := strings.Replace(srcFile, filepath.Ext(srcFile), ".rendered"+filepath.Ext(srcFile), 1)
	entries := SnapshotEntries()
	if len(entries) != 2 {
		t.Fatalf("expected 2 snapshot entries, got %d", len(entries))
	}

	var renderedFound, symlinkFound bool
	for _, e := range entries {
		if e.OriginalPath == renderedPath {
			renderedFound = true
		}
		if e.OriginalPath == dstFile {
			symlinkFound = true
		}
	}
	if !renderedFound {
		t.Fatalf("missing rendered file snapshot entry for %s", renderedPath)
	}
	if !symlinkFound {
		t.Fatalf("missing symlink destination snapshot entry for %s", dstFile)
	}
}

func TestDryRunNoSnapshots(t *testing.T) {
	ResetSnapshots()
	step := manifest.Step{
		Type: "symlink",
		From: "testfile",
		To:   filepath.Join(t.TempDir(), ".testfile"),
	}
	result := Run(step, t.TempDir(), nil, true)
	if result.Status != "would-install" {
		t.Fatalf("expected would-install, got %s: %s", result.Status, result.Msg)
	}
	if len(SnapshotEntries()) != 0 {
		t.Fatalf("expected no snapshots in dry-run, got %d", len(SnapshotEntries()))
	}
}

func TestResetSnapshots(t *testing.T) {
	dir := t.TempDir()
	srcDir := filepath.Join(dir, "dotfiles")
	dstDir := filepath.Join(dir, "home")
	os.MkdirAll(srcDir, 0755)
	os.MkdirAll(dstDir, 0755)
	srcFile := filepath.Join(srcDir, "testfile")
	dstFile := filepath.Join(dstDir, ".testfile")
	os.WriteFile(srcFile, []byte("content"), 0644)

	ResetSnapshots()
	step := manifest.Step{
		Type: "symlink",
		From: "testfile",
		To:   dstFile,
	}
	Run(step, srcDir, nil, false)
	if len(SnapshotEntries()) == 0 {
		t.Fatal("expected snapshots to be populated")
	}
	ResetSnapshots()
	if len(SnapshotEntries()) != 0 {
		t.Fatalf("expected snapshots to be cleared, got %d", len(SnapshotEntries()))
	}
}

func TestBrewSkip(t *testing.T) {
	// brew step with skip that checks for "go" binary (should be installed)
	step := manifest.Step{
		Type:    "brew",
		Package: "go",
		Skip:    "which go",
	}
	result := execBrew(step, func(s string) string { return s })
	if result.Status != "skipped" {
		t.Fatalf("expected skipped, got %s: %s", result.Status, result.Msg)
	}
}

func TestTapSkip(t *testing.T) {
	// tap step to a non-existent tap — should error since not tapped
	step := manifest.Step{
		Type: "tap",
		Repo: "nonexistent/tap-that-does-not-exist",
	}
	result := execTap(step, os.ExpandEnv)
	if result.Status == "skipped" {
		t.Fatal("expected error for non-existing tap, got skipped")
	}
	// expected: error (brew tap exits non-zero for non-existing repos)
	t.Logf("result: %s: %s", result.Status, result.Msg)
}

func TestRunSkip(t *testing.T) {
	step := manifest.Step{
		Type:    "run",
		Command: "echo should not run",
		Skip:    "true",
	}
	result := execRun(step, func(s string) string { return s })
	if result.Status != "skipped" {
		t.Fatalf("expected skipped, got %s: %s", result.Status, result.Msg)
	}
}

func TestRunExecute(t *testing.T) {
	dir := t.TempDir()
	doneFile := filepath.Join(dir, "done")
	step := manifest.Step{
		Type:    "run",
		Command: "touch " + doneFile,
		Skip:    "test -f " + doneFile,
	}
	result := execRun(step, func(s string) string { return s })
	if result.Status != "installed" {
		t.Fatalf("expected installed, got %s: %s", result.Status, result.Msg)
	}
	if _, err := os.Stat(doneFile); os.IsNotExist(err) {
		t.Fatal("expected done file to be created")
	}

	// Idempotent re-run
	result = execRun(step, func(s string) string { return s })
	if result.Status != "skipped" {
		t.Fatalf("expected skipped on re-run, got %s: %s", result.Status, result.Msg)
	}
}

func TestRunEnv(t *testing.T) {
	dir := t.TempDir()
	outFile := filepath.Join(dir, "output")
	step := manifest.Step{
		Type:    "run",
		Command: "echo $TEST_VAR > " + outFile,
		Env:     map[string]string{"TEST_VAR": "hello-world"},
	}
	result := execRun(step, func(s string) string { return s })
	if result.Status != "installed" {
		t.Fatalf("expected installed, got %s: %s", result.Status, result.Msg)
	}
	data, _ := os.ReadFile(outFile)
	expected := "hello-world\n"
	if string(data) != expected {
		t.Fatalf("expected %q, got %q", expected, string(data))
	}
}

func TestSymlinkExecute(t *testing.T) {
	dir := t.TempDir()
	srcDir := filepath.Join(dir, "dotfiles")
	dstDir := filepath.Join(dir, "home")
	os.MkdirAll(srcDir, 0755)
	os.MkdirAll(dstDir, 0755)
	srcFile := filepath.Join(srcDir, "testfile")
	dstFile := filepath.Join(dstDir, ".testfile")
	os.WriteFile(srcFile, []byte("content"), 0644)

	step := manifest.Step{
		Type: "symlink",
		From: "testfile",
		To:   dstFile,
	}
	result := execSymlink(step, srcDir, func(s string) string { return s })
	if result.Status != "installed" {
		t.Fatalf("expected installed, got %s: %s", result.Status, result.Msg)
	}

	// Idempotent re-run
	result = execSymlink(step, srcDir, func(s string) string { return s })
	if result.Status != "installed" {
		t.Fatalf("expected installed on re-run, got %s: %s", result.Status, result.Msg)
	}
}

func TestGitClone(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "clone-dest")
	step := manifest.Step{
		Type: "git-clone",
		Repo: "https://github.com/agustinzamar/dotfiles.git",
		Dest: dest,
	}
	result := execGitClone(step, func(s string) string { return s })
	if result.Status == "error" {
		t.Logf("clone failed (expected if offline): %s", result.Msg)
	}
}

func TestOMZPlugin(t *testing.T) {
	step := manifest.Step{
		Type:    "omz-plugin",
		Package: "test-plugin",
	}
	dest := os.ExpandEnv("${HOME}/.oh-my-zsh/custom/plugins/test-plugin")
	// simulate skip by creating dest
	os.MkdirAll(dest, 0755)
	defer os.RemoveAll(dest)

	result := execOMZPlugin(step, os.ExpandEnv)
	if result.Status != "skipped" {
		t.Fatalf("expected skipped, got %s: %s", result.Status, result.Msg)
	}
	os.RemoveAll(dest)
}

func TestOMZPluginDeriveName(t *testing.T) {
	step := manifest.Step{
		Type: "omz-plugin",
		Repo: "https://github.com/zsh-users/zsh-autosuggestions",
	}
	dest := os.ExpandEnv("${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions")
	os.MkdirAll(dest, 0755)
	defer os.RemoveAll(dest)

	result := execOMZPlugin(step, os.ExpandEnv)
	if result.Status != "skipped" {
		t.Fatalf("expected skipped, got %s: %s", result.Status, result.Msg)
	}
	os.RemoveAll(dest)
}

func TestVSCodeSkip(t *testing.T) {
	// If code is not installed, this test will call code --list-extensions which may fail
	_, err := exec.LookPath("code")
	if err != nil {
		t.Skip("code not installed, skipping vscode test")
	}
	step := manifest.Step{
		Type:      "vscode",
		Extension: "nonexistent.extension-12345",
	}
	// This extension doesn't exist, so it should result in an error
	result := execVSCode(step, func(s string) string { return s })
	if result.Status != "error" {
		t.Fatalf("expected error for non-existing extension, got %s: %s", result.Status, result.Msg)
	}
}

func TestRunDispatcher(t *testing.T) {
	step := manifest.Step{
		Type:    "run",
		Command: "echo ok",
		Skip:    "true",
	}
	result := Run(step, "", nil, false)
	if result.Status != "skipped" {
		t.Fatalf("expected skipped, got %s", result.Status)
	}
}

func TestUnknownStep(t *testing.T) {
	result := Run(manifest.Step{Type: "nonexistent"}, "", nil, false)
	if result.Status != "error" {
		t.Fatalf("expected error, got %s", result.Status)
	}
}

func TestDryRunBrewWouldInstall(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "nonexistent-package-xyz",
		Skip:    "which nonexistent-package-xyz",
	}
	result := Run(step, "", nil, true)
	if result.Status != "would-install" {
		t.Fatalf("expected would-install, got %s: %s", result.Status, result.Msg)
	}
}

func TestDryRunBrewWouldSkip(t *testing.T) {
	step := manifest.Step{
		Type:    "brew",
		Package: "go",
		Skip:    "which go",
	}
	result := Run(step, "", nil, true)
	if result.Status != "would-skip" {
		t.Fatalf("expected would-skip, got %s: %s", result.Status, result.Msg)
	}
}

func TestDefaultsSkip(t *testing.T) {
	step := manifest.Step{
		Type:      "defaults",
		Domain:    "com.apple.finder",
		Key:       "AppleShowAllExtensions",
		Value:     "true",
		ValueType: "bool",
	}
	result := execDefaults(step, func(s string) string { return s })
	if result.Status != "skipped" && result.Status != "installed" {
		t.Fatalf("expected skipped or installed, got %s: %s", result.Status, result.Msg)
	}
}
