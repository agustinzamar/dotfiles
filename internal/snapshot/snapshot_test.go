package snapshot

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestTake_CreatesSnapshotFile(t *testing.T) {
	dotDir := t.TempDir()
	srcDir := t.TempDir()
	src := filepath.Join(srcDir, ".zshrc")
	os.WriteFile(src, []byte("export FOO=bar\n"), 0644)

	entry, err := Take(src, dotDir)
	if err != nil {
		t.Fatalf("Take() error = %v", err)
	}
	if entry.OriginalPath != src {
		t.Fatalf("OriginalPath = %q, want %q", entry.OriginalPath, src)
	}
	if entry.Action != "backed-up" {
		t.Fatalf("Action = %q, want %q", entry.Action, "backed-up")
	}
	if _, err := os.Stat(entry.SnapshotPath); os.IsNotExist(err) {
		t.Fatalf("snapshot file %s does not exist", entry.SnapshotPath)
	}
	data, _ := os.ReadFile(entry.SnapshotPath)
	if string(data) != "export FOO=bar\n" {
		t.Fatalf("snapshot content = %q, want %q", string(data), "export FOO=bar\n")
	}
}

func TestTake_FileDoesNotExist(t *testing.T) {
	dotDir := t.TempDir()
	entry, err := Take("/nonexistent/path/file.txt", dotDir)
	if err != nil {
		t.Fatalf("Take() error = %v", err)
	}
	if entry.Action != "created" {
		t.Fatalf("Action = %q, want %q", entry.Action, "created")
	}
}

func TestSaveAndLoadManifest(t *testing.T) {
	dotDir := t.TempDir()
	m := &Manifest{
		Timestamp: "20260721T120000",
		Entries: []Entry{
			{OriginalPath: "/Users/test/.zshrc", SnapshotPath: "/tmp/snap/.zshrc", Hash: "abc123", Action: "backed-up"},
		},
	}
	if err := SaveManifest(m, dotDir); err != nil {
		t.Fatalf("SaveManifest() error = %v", err)
	}

	loaded, err := LoadManifest("20260721T120000", dotDir)
	if err != nil {
		t.Fatalf("LoadManifest() error = %v", err)
	}
	if len(loaded.Entries) != 1 {
		t.Fatalf("got %d entries, want 1", len(loaded.Entries))
	}
	if loaded.Entries[0].OriginalPath != "/Users/test/.zshrc" {
		t.Fatalf("OriginalPath = %q, want %q", loaded.Entries[0].OriginalPath, "/Users/test/.zshrc")
	}
}

func TestRestore(t *testing.T) {
	dotDir := t.TempDir()
	origDir := t.TempDir()
	orig := filepath.Join(origDir, "testfile")
	os.WriteFile(orig, []byte("original content\n"), 0644)

	entry, err := Take(orig, dotDir)
	if err != nil {
		t.Fatalf("Take() error = %v", err)
	}

	os.WriteFile(orig, []byte("modified content\n"), 0644)

	if err := Restore(*entry); err != nil {
		t.Fatalf("Restore() error = %v", err)
	}

	data, _ := os.ReadFile(orig)
	if string(data) != "original content\n" {
		t.Fatalf("after restore content = %q, want %q", string(data), "original content\n")
	}
}

func TestListSnapshots(t *testing.T) {
	dotDir := t.TempDir()
	m1 := &Manifest{Timestamp: "20260721T100000"}
	m2 := &Manifest{Timestamp: "20260721T110000"}
	SaveManifest(m1, dotDir)
	SaveManifest(m2, dotDir)

	list, err := ListSnapshots(dotDir)
	if err != nil {
		t.Fatalf("ListSnapshots() error = %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("got %d snapshots, want 2", len(list))
	}
}

func TestPruneSnapshots(t *testing.T) {
	dotDir := t.TempDir()
	for i := 0; i < 5; i++ {
		ts := fmt.Sprintf("20260721T%06d", 100000+i)
		SaveManifest(&Manifest{Timestamp: ts}, dotDir)
	}
	if err := PruneSnapshots(dotDir, 2); err != nil {
		t.Fatalf("PruneSnapshots() error = %v", err)
	}
	list, _ := ListSnapshots(dotDir)
	if len(list) != 2 {
		t.Fatalf("after prune got %d snapshots, want 2", len(list))
	}
}
