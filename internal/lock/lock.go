package lock

import (
	"fmt"
	"os"
	"path/filepath"
)

type Lock struct {
	path string
	file *os.File
}

func New(path string) *Lock {
	return &Lock{path: path}
}

func (l *Lock) Acquire() error {
	if err := os.MkdirAll(filepath.Dir(l.path), 0755); err != nil {
		return fmt.Errorf("mkdir for lock: %w", err)
	}
	f, err := os.OpenFile(l.path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		if os.IsExist(err) {
			return fmt.Errorf("lock file exists at %s — another install may be running; remove it manually if stuck", l.path)
		}
		return fmt.Errorf("acquire lock: %w", err)
	}
	l.file = f
	return nil
}

func (l *Lock) Release() error {
	if l.file != nil {
		l.file.Close()
		l.file = nil
	}
	if err := os.Remove(l.path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("release lock: %w", err)
	}
	return nil
}
