package snapshot

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type Entry struct {
	OriginalPath string `json:"original_path"`
	SnapshotPath string `json:"snapshot_path"`
	Hash         string `json:"hash"`
	Action       string `json:"action"`
}

type Manifest struct {
	Timestamp string  `json:"timestamp"`
	Entries   []Entry `json:"entries"`
}

func snapsDir(dotfilesDir string) string {
	return filepath.Join(dotfilesDir, "snapshots")
}

func Take(originalPath string, dotfilesDir string) (*Entry, error) {
	fi, err := os.Stat(originalPath)
	if os.IsNotExist(err) {
		return &Entry{OriginalPath: originalPath, Action: "created"}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("stat %s: %w", originalPath, err)
	}
	if fi.IsDir() {
		return nil, fmt.Errorf("cannot snapshot directory: %s", originalPath)
	}

	hash, err := fileHash(originalPath)
	if err != nil {
		return nil, fmt.Errorf("hash %s: %w", originalPath, err)
	}

	ts := time.Now().Format("20060102T150405")
	rel := strings.TrimLeft(originalPath, "/")
	snapPath := filepath.Join(snapsDir(dotfilesDir), ts, rel)

	if err := os.MkdirAll(filepath.Dir(snapPath), 0755); err != nil {
		return nil, fmt.Errorf("mkdir snapshot dir: %w", err)
	}

	if err := copyFile(originalPath, snapPath); err != nil {
		return nil, fmt.Errorf("copy to snapshot: %w", err)
	}

	return &Entry{
		OriginalPath: originalPath,
		SnapshotPath: snapPath,
		Hash:         hash,
		Action:       "backed-up",
	}, nil
}

func fileHash(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", h.Sum(nil)), nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func SaveManifest(m *Manifest, dotfilesDir string) error {
	dir := filepath.Join(snapsDir(dotfilesDir), m.Timestamp)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	path := filepath.Join(dir, "manifest.json")
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

func LoadManifest(ts string, dotfilesDir string) (*Manifest, error) {
	path := filepath.Join(snapsDir(dotfilesDir), ts, "manifest.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	return &m, nil
}

func Restore(entry Entry) error {
	switch entry.Action {
	case "backed-up", "symlinked":
		if entry.SnapshotPath == "" {
			return fmt.Errorf("no snapshot path for restore: %s", entry.OriginalPath)
		}
		if err := copyFile(entry.SnapshotPath, entry.OriginalPath); err != nil {
			return fmt.Errorf("restore %s: %w", entry.OriginalPath, err)
		}
	case "created":
		if err := os.Remove(entry.OriginalPath); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("remove created file %s: %w", entry.OriginalPath, err)
		}
	case "skipped":
	}
	return nil
}

func ListSnapshots(dotfilesDir string) ([]string, error) {
	dir := snapsDir(dotfilesDir)
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var timestamps []string
	for _, e := range entries {
		if e.IsDir() {
			timestamps = append(timestamps, e.Name())
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(timestamps)))
	return timestamps, nil
}

func LatestManifest(dotfilesDir string) (*Manifest, error) {
	list, err := ListSnapshots(dotfilesDir)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, fmt.Errorf("no snapshots found")
	}
	return LoadManifest(list[0], dotfilesDir)
}

func PruneSnapshots(dotfilesDir string, keep int) error {
	list, err := ListSnapshots(dotfilesDir)
	if err != nil {
		return err
	}
	if len(list) <= keep {
		return nil
	}
	for _, ts := range list[keep:] {
		dir := filepath.Join(snapsDir(dotfilesDir), ts)
		if err := os.RemoveAll(dir); err != nil {
			return fmt.Errorf("remove snapshot %s: %w", ts, err)
		}
	}
	return nil
}
