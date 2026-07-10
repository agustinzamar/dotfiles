package logger

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLog_WritesEntry(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	Log("installed", "bat", "brew")

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("ReadFile failed: %v", err)
	}
	line := string(data)
	if !strings.Contains(line, "installed") {
		t.Fatalf("expected 'installed' in log, got %q", line)
	}
	if !strings.Contains(line, "bat") {
		t.Fatalf("expected 'bat' in log, got %q", line)
	}
	if !strings.Contains(line, "brew") {
		t.Fatalf("expected 'brew' in log, got %q", line)
	}
}

func TestLog_AppendsMultiple(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	Log("installed", "bat", "brew")
	Log("skipped", "fzf", "brew")
	Log("error", "herd", "cask: exit status 1")

	data, _ := os.ReadFile(logPath)
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 log lines, got %d", len(lines))
	}
}

func TestLog_CreatesParentDir(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "nested", "deep", "test.log")

	Log("installed", "bat", "brew")

	if _, err := os.Stat(logPath); err != nil {
		t.Fatalf("log file not created: %v", err)
	}
}

func TestLog_TimestampFormat(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	before := time.Now().UTC().Format(time.RFC3339)
	Log("installed", "bat", "brew")
	after := time.Now().UTC().Format(time.RFC3339)

	data, _ := os.ReadFile(logPath)
	line := string(data)

	parts := strings.Fields(line)
	if len(parts) < 1 {
		t.Fatalf("expected timestamp in log, got %q", line)
	}
	ts := parts[0]
	if ts < before || ts > after {
		t.Fatalf("timestamp %q not between %q and %q", ts, before, after)
	}
}

func TestReadErrors(t *testing.T) {
	dir := t.TempDir()
	logPath = filepath.Join(dir, "test.log")

	Log("installed", "bat", "brew")
	Log("error", "herd", "cask: exit 1")
	Log("skipped", "fzf", "brew")
	Log("error", "phpstorm", "cask: exit 1")

	errors := ReadErrors(2)
	if len(errors) != 2 {
		t.Fatalf("expected 2 errors, got %d", len(errors))
	}
	if !strings.Contains(errors[0], "phpstorm") {
		t.Fatalf("expected phpstorm in first error, got %q", errors[0])
	}
	if !strings.Contains(errors[1], "herd") {
		t.Fatalf("expected herd in second error, got %q", errors[1])
	}
}
