package logger

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var logPath string

func init() {
	home, _ := os.UserHomeDir()
	logPath = filepath.Join(home, ".dotfiles", ".log")
}

func SetPath(p string) {
	logPath = p
}

func Log(status, tool, detail string) {
	os.MkdirAll(filepath.Dir(logPath), 0755)
	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	ts := time.Now().UTC().Format(time.RFC3339)
	fmt.Fprintf(f, "%s [%s] %s: %s\n", ts, status, tool, detail)
}

func ReadErrors(limit int) []string {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil
	}
	var errors []string
	lines := strings.Split(string(data), "\n")
	for i := len(lines) - 1; i >= 0 && len(errors) < limit; i-- {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			continue
		}
		if strings.Contains(line, "[error]") {
			errors = append(errors, line)
		}
	}
	return errors
}
